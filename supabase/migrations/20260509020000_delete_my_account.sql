-- App Store requirement (since iOS 14, App Review Guideline 5.1.1(v)): apps
-- that support account creation must let users delete their accounts from
-- inside the app. We do soft-deletion now and rely on a future periodic
-- purge to clear out auth.users + storage objects past a 30-day grace
-- window (gives users a chance to undo by re-signing-in within the window).
--
-- This RPC:
--   - sets users.deleted_at on the caller's public.users row
--   - marks every group_memberships.left_at for the caller (so their
--     groups no longer see them; RLS already filters left_at IS NULL)
--   - soft-deletes the caller's posts (sets posts.deleted_at) so they
--     fall out of feeds + archives
--
-- Avatars + post JPEGs in Storage are NOT purged here — that runs out of
-- band via the `purge-deleted-accounts` edge function (daily cron, see
-- supabase/functions/README.md). It picks up users where deleted_at is
-- older than 30 days and removes their storage objects, public.users row
-- (cascades to memberships/posts/reactions/blocks/etc.), and auth.users
-- row in one shot.

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  UPDATE public.users
    SET deleted_at = NOW()
    WHERE id = v_uid;

  UPDATE public.group_memberships
    SET left_at = NOW()
    WHERE user_id = v_uid AND left_at IS NULL;

  UPDATE public.posts
    SET deleted_at = NOW()
    WHERE author_id = v_uid AND deleted_at IS NULL;

  -- Drop device tokens so push goes silent immediately.
  DELETE FROM public.device_tokens WHERE user_id = v_uid;
END $$;

REVOKE EXECUTE ON FUNCTION public.delete_my_account() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.delete_my_account() FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO service_role;
