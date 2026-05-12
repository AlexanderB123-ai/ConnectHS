-- App Store requirement (any UGC social app): users must be able to report
-- objectionable content + accounts. We expose two RPCs — one each for
-- reporting a user or a post — that both write into `public.reports`.
--
-- The `reports` table itself is service-role only (no client SELECT/UPDATE
-- policies); this RPC is the single client-side write surface. Reasons are
-- a closed set so triage tooling can group them.

-- Limit reasons to a known set to keep triage queries clean.
CREATE OR REPLACE FUNCTION public.report_user(
  p_target_id UUID,
  p_reason    TEXT,
  p_details   TEXT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_uid = p_target_id THEN RAISE EXCEPTION 'Cannot report yourself'; END IF;
  IF p_reason NOT IN ('spam','harassment','inappropriate','impersonation','other') THEN
    RAISE EXCEPTION 'Invalid reason';
  END IF;

  INSERT INTO public.reports (reporter_id, reported_user_id, reason, details)
  VALUES (v_uid, p_target_id, p_reason, NULLIF(p_details, ''));
END $$;

CREATE OR REPLACE FUNCTION public.report_post(
  p_post_id UUID,
  p_reason  TEXT,
  p_details TEXT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid    UUID := auth.uid();
  v_exists BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_reason NOT IN ('spam','harassment','inappropriate','impersonation','other') THEN
    RAISE EXCEPTION 'Invalid reason';
  END IF;

  -- Make sure the reporter could actually see the post (RLS-equivalent
  -- check: post exists and reporter is in its group).
  SELECT EXISTS (
    SELECT 1 FROM public.posts p
    WHERE p.id = p_post_id
      AND p.deleted_at IS NULL
      AND public.is_group_member(p.group_id)
  ) INTO v_exists;
  IF NOT v_exists THEN RAISE EXCEPTION 'Post not visible'; END IF;

  INSERT INTO public.reports (reporter_id, reported_post_id, reason, details)
  VALUES (v_uid, p_post_id, p_reason, NULLIF(p_details, ''));
END $$;

DO $$
DECLARE
  fn TEXT;
  signatures TEXT[] := ARRAY[
    'public.report_user(uuid, text, text)',
    'public.report_post(uuid, text, text)'
  ];
BEGIN
  FOREACH fn IN ARRAY signatures LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', fn);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $$;
