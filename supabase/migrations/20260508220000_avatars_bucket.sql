-- Avatars: per-user profile photo. Stored at avatars/{user_id}/avatar.jpg
-- so the path encodes ownership and can be RLS-checked without a join.
--
-- Read policy is intentionally permissive — any signed-in user can fetch
-- any other user's avatar (group members see each other's faces in feed,
-- post detail, settings, etc.). Write/update/delete restricted to the
-- owner.
--
-- We also add a small `set_avatar_url(p_url)` RPC so the client doesn't
-- need direct UPDATE permission on the users table — the RPC is the only
-- way to flip the column.

INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', false)
ON CONFLICT (id) DO NOTHING;

-- Authenticated users can read any avatar (cross-group identity).
CREATE POLICY avatars_storage_select
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'avatars');

-- Owner-only write: path must start with the caller's UUID.
CREATE POLICY avatars_storage_insert
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY avatars_storage_update
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY avatars_storage_delete
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- RPC for the client to set its own avatar URL on the users row. The path
-- string the client passes here is the same one it just wrote to Storage;
-- we trust the path because RLS already enforced ownership at upload time.
CREATE OR REPLACE FUNCTION public.set_avatar_url(p_url TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  UPDATE public.users
    SET avatar_url = NULLIF(p_url, ''),
        updated_at = NOW()
    WHERE id = v_uid;
END $$;

REVOKE EXECUTE ON FUNCTION public.set_avatar_url(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_avatar_url(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_avatar_url(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_avatar_url(text) TO service_role;
