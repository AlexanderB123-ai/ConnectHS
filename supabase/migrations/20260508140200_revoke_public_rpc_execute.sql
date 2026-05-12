-- Follow-on to 20260508140100: REVOKEing from `anon` doesn't help while
-- PUBLIC still has EXECUTE (anon inherits via PUBLIC). Drop PUBLIC's grant
-- too, then re-grant the role we actually want — `authenticated` — and the
-- service role for edge functions.
--
-- After this, the only paths to call these RPCs are:
--   - signed-in users (authenticated role)
--   - service-role edge functions (which already had their grant)

DO $$
DECLARE
  fn TEXT;
  signatures TEXT[] := ARRAY[
    'public.is_group_member(uuid)',
    'public.create_group(text, text)',
    'public.create_invite(uuid, integer)',
    'public.redeem_invite(text)',
    'public.create_post(uuid, uuid, text, text, text, date)',
    'public.toggle_reaction(uuid, public.reaction_type)',
    'public.mark_viewed(uuid)',
    'public.get_feed(uuid, date)',
    'public.get_archive(uuid, date, integer, boolean)',
    'public.get_memories(uuid, date)',
    'public.get_post(uuid)'
  ];
BEGIN
  FOREACH fn IN ARRAY signatures LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', fn);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $$;
