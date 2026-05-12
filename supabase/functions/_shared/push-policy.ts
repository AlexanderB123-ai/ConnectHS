// Decides whether a given push should be delivered for a given user. Mirrors
// the rules in spec/08-notifications.md:
//   - per-kind opt-out (notification_settings.{kind}_enabled)
//   - quiet hours (notification_settings.daily_prompt_window_start/end)
//   - daily cap (5/user/day; can be bypassed for memory + daily_prompt)
//
// The daily cap reads from public.notification_sends, populated by send-push.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.46.0"

export type NotificationKind =
  | "daily_prompt"
  | "new_post"
  | "memory_resurface"
  | "reaction_received"
  | "group_invite_accepted"

export interface UserContext {
  userId: string
  timezone: string  // IANA identifier, e.g. "America/New_York"
}

export interface PushDecision {
  allowed: boolean
  reason?: string
}

export const DAILY_CAP = 5

const KIND_TO_SETTING: Record<NotificationKind, string | null> = {
  daily_prompt: "daily_prompt_enabled",
  new_post: "new_post_enabled",
  memory_resurface: "memory_enabled",
  reaction_received: "reaction_enabled",
  group_invite_accepted: null   // always send — opt-out lives elsewhere
}

export async function decide(
  supabase: SupabaseClient,
  user: UserContext,
  kind: NotificationKind
): Promise<PushDecision> {
  const { data: settings, error: settingsErr } = await supabase
    .from("notification_settings")
    .select("daily_prompt_enabled, new_post_enabled, memory_enabled, reaction_enabled, daily_prompt_window_start, daily_prompt_window_end")
    .eq("user_id", user.userId)
    .maybeSingle()
  if (settingsErr) return { allowed: false, reason: settingsErr.message }

  // Missing row shouldn't happen (trg_create_default_notification_settings
  // backfills) but guard anyway — treat as default-on, default-window.
  const s = settings ?? {
    daily_prompt_enabled: true,
    new_post_enabled: true,
    memory_enabled: true,
    reaction_enabled: true,
    daily_prompt_window_start: "10:00:00",
    daily_prompt_window_end: "22:00:00"
  }

  const settingCol = KIND_TO_SETTING[kind]
  if (settingCol && (s as Record<string, unknown>)[settingCol] === false) {
    return { allowed: false, reason: `${kind} disabled by user` }
  }

  if (!withinWindow(user.timezone, s.daily_prompt_window_start as string, s.daily_prompt_window_end as string)) {
    return { allowed: false, reason: "outside quiet hours" }
  }

  const todayStart = startOfTodayUTC(user.timezone)
  const { count, error: countErr } = await supabase
    .from("notification_sends")
    .select("*", { count: "exact", head: true })
    .eq("user_id", user.userId)
    .gte("sent_at", todayStart.toISOString())
  if (countErr) return { allowed: false, reason: countErr.message }
  if ((count ?? 0) >= DAILY_CAP) {
    return { allowed: false, reason: "daily cap reached" }
  }

  return { allowed: true }
}

export async function recordSend(
  supabase: SupabaseClient,
  userId: string,
  kind: NotificationKind,
  postId?: string | null
): Promise<void> {
  const { error } = await supabase.from("notification_sends").insert({
    user_id: userId,
    kind,
    post_id: postId ?? null
  })
  if (error) console.error("Failed to log notification send:", error)
}

// MARK: - Time helpers

function withinWindow(tz: string, startTime: string, endTime: string): boolean {
  const minutes = nowMinutesIn(tz)
  const start = parseClock(startTime)
  const end = parseClock(endTime)
  if (start <= end) {
    return minutes >= start && minutes < end
  }
  // Wrap around midnight (e.g. 22:00–08:00)
  return minutes >= start || minutes < end
}

function nowMinutesIn(tz: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    hour12: false,
    hour: "2-digit",
    minute: "2-digit"
  }).formatToParts(new Date())
  const hh = Number(parts.find((p) => p.type === "hour")!.value)
  const mm = Number(parts.find((p) => p.type === "minute")!.value)
  return hh * 60 + mm
}

function parseClock(hms: string): number {
  const [h, m] = hms.split(":").map(Number)
  return h * 60 + m
}

function startOfTodayUTC(tz: string): Date {
  // Compute "now in tz" as a clock string, subtract those elapsed ms from
  // the UTC instant. Result is the UTC moment of local midnight today.
  const now = new Date()
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    hour12: false,
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  }).formatToParts(now)
  const h = Number(parts.find((p) => p.type === "hour")!.value)
  const m = Number(parts.find((p) => p.type === "minute")!.value)
  const s = Number(parts.find((p) => p.type === "second")!.value)
  const elapsedMs = ((h * 3600) + (m * 60) + s) * 1000
  return new Date(now.getTime() - elapsedMs)
}
