// Periodic cleanup. Hard-deletes users whose `public.users.deleted_at` is
// older than the 30-day grace window: removes their post JPEGs and avatar
// from Storage, drops the public.users row (cascades to memberships, posts,
// reactions, blocks, notification_settings, notification_sends, …), and
// deletes the auth.users row so the email/phone is freed for re-registration.
//
// Designed to run on pg_cron once a day; processes up to BATCH_SIZE accounts
// per invocation so a backlog doesn't blow the function timeout. The 30-day
// grace lets a user recover an accidental deletion by signing back in within
// the window — `delete_my_account` already drops device tokens so push goes
// silent immediately, but the user's data sits ready to revive until purge.
//
// Auth: this function is server-only (`verify_jwt = false`). It MUST be
// reachable only from inside the Supabase project (pg_cron → pg_net →
// edge function with the service-role key in the Authorization header).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { adminClient } from "../_shared/supabase.ts"

const GRACE_DAYS = 30
const BATCH_SIZE = 25

interface PurgeResult {
  user_id: string
  storage_objects_deleted: number
  auth_user_deleted: boolean
  error?: string
}

serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405)

  const supabase = adminClient()

  const cutoff = new Date(
    Date.now() - GRACE_DAYS * 24 * 60 * 60 * 1000
  ).toISOString()

  const { data: users, error: usersErr } = await supabase
    .from("users")
    .select("id")
    .lt("deleted_at", cutoff)
    .not("deleted_at", "is", null)
    .limit(BATCH_SIZE)

  if (usersErr) return json({ error: usersErr.message }, 500)
  if (!users || users.length === 0) {
    return json({ purged: 0, message: "no accounts past grace window" })
  }

  const results: PurgeResult[] = []

  for (const user of users) {
    results.push(await purgeOne(supabase, user.id))
  }

  return json({ purged: results.length, results })
})

async function purgeOne(supabase: ReturnType<typeof adminClient>, userId: string): Promise<PurgeResult> {
  let storageCount = 0

  try {
    // 1. Collect every post-image path owned by this user. Even though the
    //    posts row will cascade-delete in step 4, the storage objects do
    //    NOT — Postgres doesn't know about Storage. We must purge them
    //    explicitly first.
    const { data: posts, error: postsErr } = await supabase
      .from("posts")
      .select("front_path, back_path")
      .eq("author_id", userId)
    if (postsErr) throw new Error(`posts lookup: ${postsErr.message}`)

    const postPaths: string[] = []
    for (const p of posts ?? []) {
      if (p.front_path) postPaths.push(p.front_path as string)
      if (p.back_path) postPaths.push(p.back_path as string)
    }

    if (postPaths.length > 0) {
      const { error: rmErr } = await supabase.storage
        .from("posts")
        .remove(postPaths)
      if (rmErr) throw new Error(`posts storage remove: ${rmErr.message}`)
      storageCount += postPaths.length
    }

    // 2. Avatar lives at `avatars/{user_id}/avatar.jpg`. We don't read the
    //    avatar_url column — the path is deterministic, and the column may
    //    be null for users who never set an avatar.
    const avatarPath = `${userId}/avatar.jpg`
    const { error: avErr } = await supabase.storage
      .from("avatars")
      .remove([avatarPath])
    // .remove succeeds even if the object doesn't exist; we don't bump
    // storageCount unless we know it was actually there. Skipping for
    // simplicity — the count is best-effort telemetry, not a guarantee.
    if (avErr) throw new Error(`avatar storage remove: ${avErr.message}`)

    // 3. Hard-delete public.users — cascades to group_memberships, posts,
    //    reactions, post_views, user_blocks (both sides), notification_settings,
    //    notification_sends, device_tokens. All FKs are ON DELETE CASCADE
    //    per the initial schema.
    const { error: userDelErr } = await supabase
      .from("users")
      .delete()
      .eq("id", userId)
    if (userDelErr) throw new Error(`users delete: ${userDelErr.message}`)

    // 4. Drop auth.users so the phone/email can be re-registered. supabase-js
    //    exposes this as `auth.admin.deleteUser`; service role required.
    const { error: authErr } = await supabase.auth.admin.deleteUser(userId)
    if (authErr) throw new Error(`auth.admin.deleteUser: ${authErr.message}`)

    return {
      user_id: userId,
      storage_objects_deleted: storageCount,
      auth_user_deleted: true
    }
  } catch (e) {
    return {
      user_id: userId,
      storage_objects_deleted: storageCount,
      auth_user_deleted: false,
      error: e instanceof Error ? e.message : String(e)
    }
  }
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" }
  })
}
