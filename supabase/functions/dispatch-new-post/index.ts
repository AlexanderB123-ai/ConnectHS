// Triggered by a `pg_net` HTTP POST from the trg_fanout_new_post trigger on
// public.posts. Receives the post_id, looks up the author + group, fans a
// new_post push out to every other group member via send-push.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { adminClient, functionsBaseURL, serviceRoleKey } from "../_shared/supabase.ts"

interface DispatchRequest {
  post_id: string
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405)
  }

  let body: DispatchRequest
  try {
    body = await req.json() as DispatchRequest
  } catch {
    return json({ error: "invalid json" }, 400)
  }
  if (!body.post_id) return json({ error: "post_id required" }, 400)

  const supabase = adminClient()

  const { data: post, error: postErr } = await supabase
    .from("posts")
    .select("id, group_id, author_id, caption, deleted_at, users:author_id(display_name)")
    .eq("id", body.post_id)
    .maybeSingle()
  if (postErr) return json({ error: postErr.message }, 500)
  if (!post || post.deleted_at) return json({ skipped: "post missing or deleted" })

  const authorName = ((post.users as unknown) as { display_name?: string })?.display_name ?? "someone"
  const captionPreview = (post.caption ?? "").slice(0, 60)

  const { data: members, error: memErr } = await supabase
    .from("group_memberships")
    .select("user_id")
    .eq("group_id", post.group_id)
    .is("left_at", null)
    .neq("user_id", post.author_id)
  if (memErr) return json({ error: memErr.message }, 500)

  // Skip recipients who have blocked the post author — receiving a push
  // about someone you've blocked breaks the block's expectation.
  const { data: blockers } = await supabase
    .from("user_blocks")
    .select("blocker_id")
    .eq("blocked_id", post.author_id)
  const blockerSet = new Set((blockers ?? []).map((row) => row.blocker_id))
  const recipients = (members ?? []).filter((m) => !blockerSet.has(m.user_id))

  const sendPushURL = `${functionsBaseURL()}/send-push`
  const auth = `Bearer ${serviceRoleKey()}`

  const dispatch = await Promise.allSettled(recipients.map((m) =>
    fetch(sendPushURL, {
      method: "POST",
      headers: { authorization: auth, "content-type": "application/json" },
      body: JSON.stringify({
        user_id: m.user_id,
        kind: "new_post",
        title: `${authorName.toLowerCase()} just posted`,
        body: captionPreview,
        deep_link: `connecths://post/${post.id}`,
        thread_id: `group-${post.group_id}`,
        post_id: post.id
      })
    })
  ))

  const failures = dispatch.filter((r) => r.status === "rejected").length
  return json({
    fanout: recipients.length,
    skipped_blocked: (members?.length ?? 0) - recipients.length,
    failures
  })
})

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" }
  })
}
