-- F8 Push: ensure every user has a notification_settings row.
-- The settings row stores per-kind toggles and quiet-hours bounds; downstream
-- push dispatch reads it before sending. Keeping the insert in a trigger
-- (rather than a client-side upsert) means the row exists even for users who
-- predate the push wiring and for service-role test fixtures.

CREATE OR REPLACE FUNCTION public.create_default_notification_settings()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.notification_settings (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_create_default_notification_settings ON public.users;
CREATE TRIGGER trg_create_default_notification_settings
AFTER INSERT ON public.users
FOR EACH ROW EXECUTE FUNCTION public.create_default_notification_settings();

-- Backfill rows for any existing users that don't have settings yet.
INSERT INTO public.notification_settings (user_id)
SELECT u.id FROM public.users u
LEFT JOIN public.notification_settings ns ON ns.user_id = u.id
WHERE ns.user_id IS NULL;
