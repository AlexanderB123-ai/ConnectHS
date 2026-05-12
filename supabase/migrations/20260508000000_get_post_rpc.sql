-- F6 Widget + deep-link routing: single-post lookup by id.
-- Returns the same column shape as get_feed so the iOS client can decode
-- straight into FeedPost. RLS is enforced via is_group_member, so a caller
-- who isn't in the post's group gets zero rows (matching the storage
-- bucket SELECT policy semantics).

CREATE OR REPLACE FUNCTION public.get_post(p_post_id UUID)
RETURNS TABLE (
  post_id           UUID,
  author_id         UUID,
  author_name       TEXT,
  author_avatar     TEXT,
  front_image_path  TEXT,
  back_image_path   TEXT,
  caption           TEXT,
  posted_at         TIMESTAMPTZ,
  is_late           BOOLEAN,
  view_count        INTEGER,
  reaction_summary  JSONB,
  group_id          UUID,
  prompt_date       DATE
) LANGUAGE SQL SECURITY DEFINER STABLE AS $$
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
    ) sub),
    p.group_id,
    p.prompt_date
  FROM public.posts p
  JOIN public.users u ON u.id = p.author_id
  WHERE p.id = p_post_id
    AND p.deleted_at IS NULL
    AND public.is_group_member(p.group_id);
$$;
