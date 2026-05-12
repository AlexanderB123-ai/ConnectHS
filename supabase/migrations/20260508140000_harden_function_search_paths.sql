-- Pin `search_path` on every public function the database linter flagged as
-- `function_search_path_mutable`. The risk: a SECURITY DEFINER function with
-- an unpinned search_path will resolve unqualified names against the caller's
-- search_path, so a hostile temp schema can shadow built-ins (`pg_catalog.…`)
-- or table-name lookups and run code with the function owner's privileges.
-- Pinning to (public, pg_temp) makes resolution deterministic.
--
-- We use ALTER FUNCTION rather than CREATE OR REPLACE so the bodies stay
-- exactly as the original migrations defined them — no risk of subtle
-- behavior drift from re-typing.

ALTER FUNCTION public.is_group_member(uuid)                                  SET search_path = public, pg_temp;
ALTER FUNCTION public.create_group(text, text)                               SET search_path = public, pg_temp;
ALTER FUNCTION public.create_invite(uuid, integer)                           SET search_path = public, pg_temp;
ALTER FUNCTION public.redeem_invite(text)                                    SET search_path = public, pg_temp;
ALTER FUNCTION public.create_post(uuid, uuid, text, text, text, date)        SET search_path = public, pg_temp;
ALTER FUNCTION public.toggle_reaction(uuid, public.reaction_type)            SET search_path = public, pg_temp;
ALTER FUNCTION public.mark_viewed(uuid)                                      SET search_path = public, pg_temp;
ALTER FUNCTION public.get_feed(uuid, date)                                   SET search_path = public, pg_temp;
ALTER FUNCTION public.get_archive(uuid, date, integer, boolean)              SET search_path = public, pg_temp;
ALTER FUNCTION public.get_memories(uuid, date)                               SET search_path = public, pg_temp;
ALTER FUNCTION public.get_post(uuid)                                         SET search_path = public, pg_temp;
ALTER FUNCTION public.create_default_notification_settings()                 SET search_path = public, pg_temp;
