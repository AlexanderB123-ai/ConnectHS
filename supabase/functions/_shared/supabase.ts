// Service-role Supabase client for edge functions. Never ship this in the
// iOS binary — service role bypasses RLS.

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.46.0"

export function adminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  if (!url || !key) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
  }
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false }
  })
}

export function functionsBaseURL(): string {
  const url = Deno.env.get("SUPABASE_URL")
  if (!url) throw new Error("SUPABASE_URL must be set")
  return `${url}/functions/v1`
}

export function serviceRoleKey(): string {
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  if (!key) throw new Error("SUPABASE_SERVICE_ROLE_KEY must be set")
  return key
}
