-- spec/05: long-press a reaction pill in PostDetailView shows who reacted
-- with that emoji. RLS on reactions already restricts visibility to group
-- members; the RPC just joins to users so the client gets display_name +
-- avatar_url in one round-trip.

CREATE OR REPLACE FUNCTION public.list_post_reactors(
  p_post_id  UUID,
  p_reaction public.reaction_type
)
RETURNS TABLE (
  user_id      UUID,
  display_name TEXT,
  avatar_url   TEXT,
  reacted_at   TIMESTAMPTZ
)
LANGUAGE SQL SECURITY DEFINER STABLE
SET search_path = public, pg_temp AS $$
  SELECT u.id, u.display_name, u.avatar_url, r.created_at
  FROM public.reactions r
  JOIN public.users u ON u.id = r.user_id
  JOIN public.posts p ON p.id = r.post_id
  WHERE r.post_id = p_post_id
    AND r.reaction = p_reaction
    AND p.deleted_at IS NULL
    AND public.is_group_member(p.group_id)
  ORDER BY r.created_at ASC;
$$;

REVOKE EXECUTE ON FUNCTION public.list_post_reactors(uuid, public.reaction_type) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_post_reactors(uuid, public.reaction_type) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_post_reactors(uuid, public.reaction_type) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_post_reactors(uuid, public.reaction_type) TO service_role;
