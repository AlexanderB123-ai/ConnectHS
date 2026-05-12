-- App Store guideline 1.2: UGC apps must let users block other users. We
-- model blocks as a one-directional edge (blocker_id → blocked_id) so a
-- mutual block is two rows; this matches Twitter/IG semantics and keeps
-- the filter SQL simple.
--
-- Filter wiring: each of the post-listing RPCs (get_feed, get_archive,
-- get_memories) gets an extra NOT-IN-blocked-authors clause. We don't
-- modify base-table RLS for this — RLS already gates by group membership,
-- and adding blocks-aware predicates everywhere would be expensive and
-- error-prone. Filtering at the RPC layer is good enough since the iOS
-- client never reads `posts` directly.

CREATE TABLE IF NOT EXISTS public.user_blocks (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  blocked_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker ON public.user_blocks(blocker_id);

ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;

-- A user can read + write only their own blocks.
CREATE POLICY user_blocks_self ON public.user_blocks
  FOR ALL TO authenticated
  USING (blocker_id = auth.uid())
  WITH CHECK (blocker_id = auth.uid());

-- ============================================================
-- Block / unblock / list
-- ============================================================

CREATE OR REPLACE FUNCTION public.block_user(p_target_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_uid = p_target_id THEN RAISE EXCEPTION 'Cannot block yourself'; END IF;
  INSERT INTO public.user_blocks (blocker_id, blocked_id)
  VALUES (v_uid, p_target_id)
  ON CONFLICT (blocker_id, blocked_id) DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION public.unblock_user(p_target_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  DELETE FROM public.user_blocks
    WHERE blocker_id = v_uid AND blocked_id = p_target_id;
END $$;

CREATE OR REPLACE FUNCTION public.list_my_blocked_users()
RETURNS TABLE (
  user_id      UUID,
  display_name TEXT,
  avatar_url   TEXT,
  blocked_at   TIMESTAMPTZ
)
LANGUAGE SQL SECURITY DEFINER STABLE
SET search_path = public, pg_temp AS $$
  SELECT u.id, u.display_name, u.avatar_url, b.created_at
  FROM public.user_blocks b
  JOIN public.users u ON u.id = b.blocked_id
  WHERE b.blocker_id = auth.uid()
  ORDER BY b.created_at DESC;
$$;

-- ============================================================
-- Filter blocked authors out of the existing post-listing RPCs
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_feed(p_group_id UUID, p_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
  post_id UUID,
  author_id UUID,
  author_name TEXT,
  author_avatar TEXT,
  front_image_path TEXT,
  back_image_path TEXT,
  caption TEXT,
  posted_at TIMESTAMPTZ,
  is_late BOOLEAN,
  view_count INTEGER,
  reaction_summary JSONB
) LANGUAGE SQL SECURITY DEFINER STABLE
SET search_path = public, pg_temp AS $$
  SELECT
    p.id,
    p.author_id,
    u.display_name,
    u.avatar_url,
    p.front_image_path,
    p.back_image_path,
    p.caption,
    p.posted_at,
    p.is_late,
    (SELECT COUNT(*)::INT FROM public.post_views WHERE post_id = p.id),
    (SELECT jsonb_object_agg(reaction, cnt) FROM (
      SELECT reaction, COUNT(*)::INT AS cnt
      FROM public.reactions WHERE post_id = p.id
      GROUP BY reaction
    ) sub)
  FROM public.posts p
  JOIN public.users u ON u.id = p.author_id
  WHERE p.group_id = p_group_id
    AND p.prompt_date = p_date
    AND p.deleted_at IS NULL
    AND public.is_group_member(p.group_id)
    AND p.author_id NOT IN (
      SELECT blocked_id FROM public.user_blocks WHERE blocker_id = auth.uid()
    )
  ORDER BY p.posted_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_archive(
  p_group_id  UUID,
  p_before    DATE DEFAULT NULL,
  p_limit     INTEGER DEFAULT 60,
  p_only_mine BOOLEAN DEFAULT FALSE
) RETURNS TABLE (
  post_id           UUID,
  author_id         UUID,
  author_name       TEXT,
  author_avatar     TEXT,
  front_image_path  TEXT,
  back_image_path   TEXT,
  caption           TEXT,
  prompt_date       DATE,
  posted_at         TIMESTAMPTZ,
  is_late           BOOLEAN,
  view_count        INTEGER,
  reaction_summary  JSONB
) LANGUAGE SQL SECURITY DEFINER STABLE
SET search_path = public, pg_temp AS $$
  SELECT
    p.id,
    p.author_id,
    u.display_name,
    u.avatar_url,
    p.front_image_path,
    p.back_image_path,
    p.caption,
    p.prompt_date,
    p.posted_at,
    p.is_late,
    (SELECT COUNT(*)::INT FROM public.post_views WHERE post_id = p.id),
    (SELECT jsonb_object_agg(reaction, cnt) FROM (
      SELECT reaction, COUNT(*)::INT AS cnt
      FROM public.reactions WHERE post_id = p.id
      GROUP BY reaction
    ) sub)
  FROM public.posts p
  JOIN public.users u ON u.id = p.author_id
  WHERE p.group_id = p_group_id
    AND p.deleted_at IS NULL
    AND public.is_group_member(p.group_id)
    AND (p_before IS NULL OR p.prompt_date < p_before)
    AND (NOT p_only_mine OR p.author_id = auth.uid())
    AND p.author_id NOT IN (
      SELECT blocked_id FROM public.user_blocks WHERE blocker_id = auth.uid()
    )
  ORDER BY p.prompt_date DESC, p.posted_at DESC
  LIMIT GREATEST(p_limit, 1);
$$;

CREATE OR REPLACE FUNCTION public.get_memories(p_group_id UUID, p_today DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
  post_id UUID,
  prompt_date DATE,
  years_ago INTEGER,
  author_name TEXT,
  front_image_path TEXT,
  back_image_path TEXT,
  caption TEXT
) LANGUAGE SQL SECURITY DEFINER STABLE
SET search_path = public, pg_temp AS $$
  SELECT
    p.id,
    p.prompt_date,
    EXTRACT(YEAR FROM AGE(p_today, p.prompt_date))::INT AS years_ago,
    u.display_name,
    p.front_image_path,
    p.back_image_path,
    p.caption
  FROM public.posts p
  JOIN public.users u ON u.id = p.author_id
  WHERE p.group_id = p_group_id
    AND p.deleted_at IS NULL
    AND public.is_group_member(p.group_id)
    AND p.prompt_date < p_today
    AND p.author_id NOT IN (
      SELECT blocked_id FROM public.user_blocks WHERE blocker_id = auth.uid()
    )
    AND (
      (
        EXTRACT(MONTH FROM p.prompt_date) = EXTRACT(MONTH FROM p_today)
        AND EXTRACT(DAY FROM p.prompt_date) = EXTRACT(DAY FROM p_today)
      )
      OR
      (
        EXTRACT(MONTH FROM p_today) = 2
        AND EXTRACT(DAY FROM p_today) = 28
        AND EXTRACT(MONTH FROM (p_today + INTERVAL '1 day')) = 3
        AND EXTRACT(MONTH FROM p.prompt_date) = 2
        AND EXTRACT(DAY FROM p.prompt_date) = 29
      )
    )
  ORDER BY p.prompt_date DESC;
$$;

-- ============================================================
-- Grants
-- ============================================================

DO $$
DECLARE
  fn TEXT;
  signatures TEXT[] := ARRAY[
    'public.block_user(uuid)',
    'public.unblock_user(uuid)',
    'public.list_my_blocked_users()'
  ];
BEGIN
  FOREACH fn IN ARRAY signatures LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', fn);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $$;
