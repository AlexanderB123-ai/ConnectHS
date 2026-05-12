// Triggered by a `pg_net` HTTP POST from the trg_fanout_new_reaction trigger
// on public.reactions (AFTER INSERT). Sends a `reaction_received` push to the
// post author so they know someone reacted. We deliberately do NOT push when
// the reactor IS the author (no self-notifications).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { adminClient, functionsBaseURL, serviceRoleKey } from "../_shared/supabase.ts"

interface DispatchRequest {
  post_id: string
  reactor_id: string
  reaction: string  // matches public.reaction_type enum value
}

const REACTION_EMOJI: Record<string, string> = {
  heart: "❤️",
  fire: "🔥",
  laugh: "😂",
  wow: "😮",
  sad: "😢",
  thumbs_up: "👍"
}

serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405)

  let body: DispatchRequest
  try {
    body = await req.json() as DispatchRequest
  } catch {
    return json({ error: "invalid json" }, 400)
  }
  if (!body.post_id || !body.reactor_id || !body.reaction) {
    return json({ error: "post_id, reactor_id, reaction required" }, 400)
  }

  const supabase = adminClient()

  const { data: post, error: postErr } = await supabase
    .from("posts")
    .select("id, group_id, author_id, deleted_at")
    .eq("id", body.post_id)
    .maybeSingle()
  if (postErr) return json({ error: postErr.message }, 500)
  if (!post || post.deleted_at) return json({ skipped: "post missing or deleted" })

  // Don't notify the author when they react to their own post.
  if (post.author_id === body.reactor_id) {
    return json({ skipped: "self-reaction" })
  }

  // If the post author has blocked the reactor, suppress the notification —
  // the block already hides the reactor's posts/memories from the author,
  // so a reaction push would leak the blocked user's continued presence.
  const { data: block } = await supabase
    .from("user_blocks")
    .select("id")
    .eq("blocker_id", post.author_id)
    .eq("blocked_id", body.reactor_id)
    .maybeSingle()
  if (block) return json({ skipped: "recipient blocked reactor" })

  // Per-(post, recipient) cooldown. A user spam-toggling reactions on the
  // same post would otherwise generate one push per toggle — which both
  // hammers the recipient's lock screen and burns their daily cap. We send
  // at most one reaction_received per post per 5 minutes; subsequent
  // reactions are visible in-app (the pill count updates over realtime),
  // they just don't ring the recipient's phone again.
  const REACTION_COOLDOWN_MIN = 5
  const cooldownCutoff = new Date(
    Date.now() - REACTION_COOLDOWN_MIN * 60_000
  ).toISOString()
  const { data: recent } = await supabase
    .from("notification_sends")
    .select("id")
    .eq("user_id", post.author_id)
    .eq("kind", "reaction_received")
    .eq("post_id", post.id)
    .gte("sent_at", cooldownCutoff)
    .limit(1)
    .maybeSingle()
  if (recent) return json({ skipped: "reaction cooldown active" })

  // Look up reactor's display name for the title copy.
  const { data: reactor } = await supabase
    .from("users")
    .select("display_name")
    .eq("id", body.reactor_id)
    .maybeSingle()
  const reactorName = (reactor?.display_name ?? "someone").toLowerCase()
  const emoji = REACTION_EMOJI[body.reaction] ?? "💬"

  const sendPushURL = `${functionsBaseURL()}/send-push`
  const auth = `Bearer ${serviceRoleKey()}`

  const response = await fetch(sendPushURL, {
    method: "POST",
    headers: { authorization: auth, "content-type": "application/json" },
    body: JSON.stringify({
      user_id: post.author_id,
      kind: "reaction_received",
      title: `${reactorName} reacted ${emoji} to your moment`,
      body: "",
      deep_link: `connecths://post/${post.id}`,
      thread_id: `reactions-${post.id}`,
      post_id: post.id
    })
  })

  return json({ status: response.status })
})

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" }
  })
}
