// Internal entrypoint other dispatchers (dispatch-new-post, memory-engine,
// dispatch-daily-prompt) call to actually deliver one notification kind to
// one user. Applies the policy gate, fans out to every device token the user
// has registered, deletes 410-Gone tokens, logs the send.
//
// Not intended to be called from the iOS client directly — `verify_jwt` in
// the function config is `false`; we expect Bearer auth with the service-role
// key from sibling functions.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { adminClient } from "../_shared/supabase.ts"
import { configFromEnv, sendAPNs } from "../_shared/apns.ts"
import {
  decide,
  recordSend,
  type NotificationKind
} from "../_shared/push-policy.ts"

interface SendPushRequest {
  user_id: string
  kind: NotificationKind
  title: string
  body: string
  deep_link: string
  thread_id?: string
  post_id?: string
  // memory + daily_prompt outrank the daily cap per spec; pass true to skip.
  bypass_cap?: boolean
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405)
  }

  let body: SendPushRequest
  try {
    body = await req.json() as SendPushRequest
  } catch {
    return json({ error: "invalid json" }, 400)
  }
  if (!body.user_id || !body.kind || !body.title || !body.deep_link) {
    return json({ error: "user_id, kind, title, deep_link required" }, 400)
  }

  const supabase = adminClient()

  const { data: user, error: userErr } = await supabase
    .from("users")
    .select("id, timezone")
    .eq("id", body.user_id)
    .maybeSingle()
  if (userErr || !user) {
    return json({ error: "user not found", details: userErr?.message }, 404)
  }

  if (!body.bypass_cap) {
    const decision = await decide(
      supabase,
      { userId: user.id, timezone: user.timezone },
      body.kind
    )
    if (!decision.allowed) {
      return json({ skipped: decision.reason })
    }
  }

  const { data: tokens, error: tokensErr } = await supabase
    .from("device_tokens")
    .select("apns_token")
    .eq("user_id", user.id)
  if (tokensErr) return json({ error: tokensErr.message }, 500)
  if (!tokens || tokens.length === 0) {
    return json({ skipped: "no devices" })
  }

  const cfg = configFromEnv()
  const results = await Promise.allSettled(
    tokens.map((t) =>
      sendAPNs({
        apnsToken: t.apns_token,
        title: body.title,
        body: body.body,
        threadId: body.thread_id,
        deepLink: body.deep_link
      }, cfg)
    )
  )

  const deadTokens = results
    .filter((r): r is PromiseFulfilledResult<Awaited<ReturnType<typeof sendAPNs>>> => r.status === "fulfilled")
    .filter((r) => r.value.isDead)
    .map((r) => r.value.apnsToken)

  if (deadTokens.length > 0) {
    await supabase.from("device_tokens").delete().in("apns_token", deadTokens)
  }

  const anySent = results.some(
    (r) => r.status === "fulfilled" && !r.value.isDead && r.value.status < 300
  )
  if (anySent) {
    await recordSend(supabase, user.id, body.kind, body.post_id)
  }

  return json({
    attempted: tokens.length,
    deadDeleted: deadTokens.length,
    results: results.map((r) =>
      r.status === "fulfilled"
        ? { status: r.value.status, dead: r.value.isDead }
        : { error: String(r.reason) }
    )
  })
})

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" }
  })
}
