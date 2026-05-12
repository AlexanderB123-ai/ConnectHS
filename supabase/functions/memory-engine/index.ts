// Cron-driven (hourly). For each user whose local time is currently 09:00,
// query get_memories for each of their groups and dispatch a memory_resurface
// push if the result set is non-empty. Memories outrank the daily cap per
// spec (set bypass_cap so the user gets the memory even if they hit the cap
// from new_post pushes earlier in the day).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { adminClient, functionsBaseURL, serviceRoleKey } from "../_shared/supabase.ts"

interface MemoryRow {
  post_id: string
  prompt_date: string
  years_ago: number
  author_name: string
  front_image_path: string
  back_image_path: string
  caption: string | null
}

serve(async (_req) => {
  const supabase = adminClient()

  const { data: users, error: usersErr } = await supabase
    .from("users")
    .select("id, display_name, timezone")
    .is("deleted_at", null)
  if (usersErr) return json({ error: usersErr.message }, 500)

  const sendPushURL = `${functionsBaseURL()}/send-push`
  const auth = `Bearer ${serviceRoleKey()}`
  const today = isoDate(new Date())

  let dispatched = 0
  let scanned = 0
  for (const user of users ?? []) {
    if (!isNineAMLocal(user.timezone)) continue
    scanned++

    const { data: memberships } = await supabase
      .from("group_memberships")
      .select("group_id")
      .eq("user_id", user.id)
      .is("left_at", null)

    for (const m of memberships ?? []) {
      const { data: memories } = await supabase
        .rpc("get_memories", { p_group_id: m.group_id, p_today: today })
      const rows = (memories ?? []) as MemoryRow[]
      if (rows.length === 0) continue

      const top = rows[0]
      const others = rows.length > 1 ? ` +${rows.length - 1}` : ""
      const body = (top.caption && top.caption.trim().length > 0)
        ? top.caption
        : `with ${top.author_name.toLowerCase()}${others}`

      await fetch(sendPushURL, {
        method: "POST",
        headers: { authorization: auth, "content-type": "application/json" },
        body: JSON.stringify({
          user_id: user.id,
          kind: "memory_resurface",
          title: `📸 memory from ${top.years_ago}yr ago`,
          body,
          deep_link: `connecths://memory/${top.post_id}`,
          thread_id: `memory-${m.group_id}`,
          post_id: top.post_id,
          bypass_cap: true
        })
      })
      dispatched++
    }
  }

  return json({ scanned, dispatched })
})

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10)
}

function isNineAMLocal(tz: string): boolean {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    hour12: false,
    hour: "2-digit"
  }).formatToParts(new Date())
  return parts.find((p) => p.type === "hour")?.value === "09"
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" }
  })
}
