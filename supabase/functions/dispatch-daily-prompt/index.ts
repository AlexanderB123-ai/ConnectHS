// Cron-driven (every 15 min). For each active group that hasn't received
// today's prompt yet AND has at least one user currently inside their
// daily_prompt window, insert a daily_prompts row (UNIQUE on group_id +
// prompt_date is the canonical dedup) and fan out a daily_prompt push.
//
// We let send-push enforce the per-user quiet hours; this dispatcher only
// gates by "is the prompt already sent today for this group."

import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { adminClient, functionsBaseURL, serviceRoleKey } from "../_shared/supabase.ts"

serve(async (_req) => {
  const supabase = adminClient()

  const today = new Date().toISOString().slice(0, 10)

  const { data: groups, error: groupsErr } = await supabase
    .from("groups")
    .select("id, name, emoji")
    .is("deleted_at", null)
  if (groupsErr) return json({ error: groupsErr.message }, 500)

  const sendPushURL = `${functionsBaseURL()}/send-push`
  const auth = `Bearer ${serviceRoleKey()}`

  let dispatched = 0
  let skipped = 0
  for (const group of groups ?? []) {
    // Race-safe: rely on the UNIQUE constraint on (group_id, prompt_date)
    // for dedup. If insert fails with unique violation, another dispatcher
    // already won — skip.
    const { error: insertErr } = await supabase
      .from("daily_prompts")
      .insert({
        group_id: group.id,
        prompt_date: today,
        prompt_time: new Date().toISOString()
      })
    if (insertErr) {
      if ((insertErr as { code?: string }).code === "23505") {
        skipped++
        continue
      }
      console.error(`daily_prompts insert failed for ${group.id}:`, insertErr.message)
      continue
    }

    const { data: members } = await supabase
      .from("group_memberships")
      .select("user_id")
      .eq("group_id", group.id)
      .is("left_at", null)

    await Promise.allSettled((members ?? []).map((m) =>
      fetch(sendPushURL, {
        method: "POST",
        headers: { authorization: auth, "content-type": "application/json" },
        body: JSON.stringify({
          user_id: m.user_id,
          kind: "daily_prompt",
          title: "⏰ time to connecths",
          body: "your daily moment is waiting",
          deep_link: "connecths://camera",
          thread_id: `prompt-${group.id}`,
          bypass_cap: true
        })
      })
    ))
    dispatched++
  }

  return json({ dispatched, skipped })
})

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" }
  })
}
