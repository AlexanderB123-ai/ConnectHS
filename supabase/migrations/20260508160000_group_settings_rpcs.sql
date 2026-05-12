-- F2 group settings: RPCs for the GroupSettingsView surface.
--
--   list_group_members(p_group_id)  →  flat (user_id, display_name, avatar_url, role, joined_at)
--   leave_group(p_group_id)         →  marks caller's membership left_at; auto-promotes oldest
--                                       non-admin member if caller was the last admin and the
--                                       group still has other members
--   remove_member(p_group_id, p_user_id)  →  admin-only; sets target's left_at; refuses if
--                                             target is the last admin
--   update_group(p_group_id, p_name, p_emoji)  →  admin-only edit of name/emoji
--   promote_admin(p_group_id, p_user_id)  →  admin-only role bump member→admin
--
-- All SECURITY DEFINER, search_path pinned, EXECUTE granted only to
-- authenticated + service_role (PUBLIC + anon revoked).

-- ============================================================
-- list_group_members
-- ============================================================
CREATE OR REPLACE FUNCTION public.list_group_members(p_group_id UUID)
RETURNS TABLE (
  user_id        UUID,
  display_name   TEXT,
  avatar_url     TEXT,
  role           public.group_member_role,
  joined_at      TIMESTAMPTZ
)
LANGUAGE SQL SECURITY DEFINER STABLE
SET search_path = public, pg_temp AS $$
  SELECT u.id, u.display_name, u.avatar_url, m.role, m.joined_at
  FROM public.group_memberships m
  JOIN public.users u ON u.id = m.user_id
  WHERE m.group_id = p_group_id
    AND m.left_at IS NULL
    AND public.is_group_member(p_group_id)
  ORDER BY m.role DESC, m.joined_at ASC;
$$;

-- ============================================================
-- leave_group
-- ============================================================
CREATE OR REPLACE FUNCTION public.leave_group(p_group_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid           UUID := auth.uid();
  v_role          public.group_member_role;
  v_admin_count   INT;
  v_other_count   INT;
  v_promote_id    UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT role INTO v_role
  FROM public.group_memberships
  WHERE group_id = p_group_id AND user_id = v_uid AND left_at IS NULL;
  IF v_role IS NULL THEN RAISE EXCEPTION 'Not a member of that group'; END IF;

  IF v_role = 'admin' THEN
    SELECT COUNT(*) INTO v_admin_count FROM public.group_memberships
    WHERE group_id = p_group_id AND role = 'admin' AND left_at IS NULL;

    IF v_admin_count <= 1 THEN
      -- Only admin leaving. Auto-promote oldest non-admin member if any.
      SELECT user_id INTO v_promote_id
      FROM public.group_memberships
      WHERE group_id = p_group_id AND user_id <> v_uid AND left_at IS NULL
      ORDER BY joined_at ASC
      LIMIT 1;

      IF v_promote_id IS NOT NULL THEN
        UPDATE public.group_memberships
          SET role = 'admin'
          WHERE group_id = p_group_id AND user_id = v_promote_id;
      END IF;
    END IF;
  END IF;

  UPDATE public.group_memberships
    SET left_at = NOW()
    WHERE group_id = p_group_id AND user_id = v_uid AND left_at IS NULL;
END $$;

-- ============================================================
-- remove_member
-- ============================================================
CREATE OR REPLACE FUNCTION public.remove_member(p_group_id UUID, p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid          UUID := auth.uid();
  v_caller_role  public.group_member_role;
  v_target_role  public.group_member_role;
  v_admin_count  INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_uid = p_user_id THEN RAISE EXCEPTION 'Use leave_group to remove yourself'; END IF;

  SELECT role INTO v_caller_role
  FROM public.group_memberships
  WHERE group_id = p_group_id AND user_id = v_uid AND left_at IS NULL;
  IF v_caller_role IS NULL OR v_caller_role <> 'admin' THEN
    RAISE EXCEPTION 'Only admins can remove members';
  END IF;

  SELECT role INTO v_target_role
  FROM public.group_memberships
  WHERE group_id = p_group_id AND user_id = p_user_id AND left_at IS NULL;
  IF v_target_role IS NULL THEN RAISE EXCEPTION 'Target is not a member'; END IF;

  IF v_target_role = 'admin' THEN
    SELECT COUNT(*) INTO v_admin_count FROM public.group_memberships
    WHERE group_id = p_group_id AND role = 'admin' AND left_at IS NULL;
    IF v_admin_count <= 1 THEN RAISE EXCEPTION 'Cannot remove the last admin'; END IF;
  END IF;

  UPDATE public.group_memberships
    SET left_at = NOW()
    WHERE group_id = p_group_id AND user_id = p_user_id AND left_at IS NULL;
END $$;

-- ============================================================
-- update_group
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_group(
  p_group_id UUID,
  p_name     TEXT,
  p_emoji    TEXT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid          UUID := auth.uid();
  v_caller_role  public.group_member_role;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT role INTO v_caller_role
  FROM public.group_memberships
  WHERE group_id = p_group_id AND user_id = v_uid AND left_at IS NULL;
  IF v_caller_role IS NULL OR v_caller_role <> 'admin' THEN
    RAISE EXCEPTION 'Only admins can edit group details';
  END IF;

  IF char_length(trim(p_name)) NOT BETWEEN 1 AND 60 THEN
    RAISE EXCEPTION 'Name must be 1-60 characters';
  END IF;

  UPDATE public.groups
    SET name = trim(p_name),
        emoji = NULLIF(p_emoji, ''),
        updated_at = NOW()
    WHERE id = p_group_id;
END $$;

-- ============================================================
-- promote_admin
-- ============================================================
CREATE OR REPLACE FUNCTION public.promote_admin(p_group_id UUID, p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid          UUID := auth.uid();
  v_caller_role  public.group_member_role;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT role INTO v_caller_role
  FROM public.group_memberships
  WHERE group_id = p_group_id AND user_id = v_uid AND left_at IS NULL;
  IF v_caller_role IS NULL OR v_caller_role <> 'admin' THEN
    RAISE EXCEPTION 'Only admins can promote';
  END IF;

  UPDATE public.group_memberships
    SET role = 'admin'
    WHERE group_id = p_group_id AND user_id = p_user_id AND left_at IS NULL;
END $$;

-- ============================================================
-- Grants — match the existing RPC pattern (authenticated + service_role only)
-- ============================================================
DO $$
DECLARE
  fn TEXT;
  signatures TEXT[] := ARRAY[
    'public.list_group_members(uuid)',
    'public.leave_group(uuid)',
    'public.remove_member(uuid, uuid)',
    'public.update_group(uuid, text, text)',
    'public.promote_admin(uuid, uuid)'
  ];
BEGIN
  FOREACH fn IN ARRAY signatures LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', fn);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $$;
