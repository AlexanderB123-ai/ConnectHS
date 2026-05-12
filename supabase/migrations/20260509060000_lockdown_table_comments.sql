-- Annotate the three server-only tables that intentionally have RLS enabled
-- but no policies. The advisor flags this as INFO ("RLS enabled, no policy")
-- because in normal use it's a footgun — a developer enables RLS, forgets
-- to add a policy, and locks the table out for everyone.
--
-- For these three tables that's the *intended* posture: clients must never
-- read or write them directly; access happens only via SECURITY DEFINER
-- RPCs and edge functions running with the service role.
--
--   daily_prompts       — global pool of prompt copy. Read by the
--                         memory-engine + dispatch-daily-prompt edge
--                         functions; clients never read it (the prompt
--                         text travels over APNs).
--   notification_sends  — push idempotency ledger. Inserted by send-push
--                         edge function. Clients never need to see it.
--   reports             — moderation queue. Inserted by report_user /
--                         report_post SECURITY DEFINER RPCs. Read by
--                         human moderators in the Supabase dashboard
--                         (service role / dashboard auth bypasses RLS).
--                         Clients must NEVER list other people's reports.

comment on table public.daily_prompts is
  'Server-only: prompt pool consumed by edge functions. RLS deliberately has '
  'zero policies — clients reach the prompt text via APNs payloads, not by '
  'querying this table. Do not add a SELECT policy without a clear use case.';

comment on table public.notification_sends is
  'Server-only: push-send idempotency ledger written by the send-push edge '
  'function. RLS deliberately has zero policies — clients have no business '
  'reading their own send history. Do not add policies.';

comment on table public.reports is
  'Server-only moderation queue. Inserted via report_user() / report_post() '
  'SECURITY DEFINER RPCs (which set reporter_id from auth.uid()). RLS '
  'deliberately has zero policies — surfacing one user''s reports to anyone '
  'else (or to the reporter themselves) would create a harassment vector. '
  'Read access is intentionally limited to service role / dashboard.';
