-- Revoke EXECUTE from the `anon` role on every RPC. These are all
-- post-auth operations (create groups, post moments, react, browse the
-- archive, etc.) — there's no legitimate reason an unauthenticated PostgREST
-- caller should reach them. The `authenticated` grant stays as-is; that's
-- the role our iOS client uses after sign-in.
--
-- Without this, anon can call the RPC, hit `auth.uid()` returning NULL, and
-- get a clear error or empty result. Functional but noisy and an
-- enumeration risk. Revoking pushes the failure to the boundary instead.

REVOKE EXECUTE ON FUNCTION public.is_group_member(uuid)                              FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_group(text, text)                           FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_invite(uuid, integer)                       FROM anon;
REVOKE EXECUTE ON FUNCTION public.redeem_invite(text)                                FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_post(uuid, uuid, text, text, text, date)    FROM anon;
REVOKE EXECUTE ON FUNCTION public.toggle_reaction(uuid, public.reaction_type)        FROM anon;
REVOKE EXECUTE ON FUNCTION public.mark_viewed(uuid)                                  FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_feed(uuid, date)                               FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_archive(uuid, date, integer, boolean)          FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_memories(uuid, date)                           FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_post(uuid)                                     FROM anon;
