-- F4 Archive: paginated query for the permanent timeline
-- Same column shape as get_feed so the client can reuse FeedPost / PostDetailView.
-- Pagination is keyset-style on prompt_date: pass the smallest prompt_date you've
-- already loaded as `p_before` to fetch the next page (strictly older).

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
) LANGUAGE SQL SECURITY DEFINER STABLE AS $$
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
  ORDER BY p.prompt_date DESC, p.posted_at DESC
  LIMIT GREATEST(p_limit, 1);
$$;
