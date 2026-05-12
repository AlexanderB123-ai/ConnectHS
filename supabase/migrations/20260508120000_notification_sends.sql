-- F8 push: log of every push the server actually dispatched, used by the
-- send-push edge function to enforce the per-user daily cap and by future
-- analytics. We log AFTER a successful APNs hand-off, not on dead tokens.
--
-- The table is service-role only; clients never read or write it directly.

ALTER TYPE notification_kind ADD VALUE IF NOT EXISTS 'daily_prompt';

CREATE TABLE IF NOT EXISTS public.notification_sends (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  kind      notification_kind NOT NULL,
  post_id   UUID REFERENCES public.posts(id) ON DELETE SET NULL,
  sent_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Daily-cap query: COUNT(*) WHERE user_id = ? AND sent_at >= start-of-today
CREATE INDEX IF NOT EXISTS idx_notification_sends_user_day
  ON public.notification_sends(user_id, sent_at DESC);

ALTER TABLE public.notification_sends ENABLE ROW LEVEL SECURITY;
-- Intentionally no policies — only the service role accesses this table.
