# Edge functions — push pipeline

These functions ship the F8 server side per `spec/08-notifications.md`. They
intentionally **stay undeployed** until paid Apple Developer enrollment lands
on 2026-06-16, at which point we'll have the APNs `.p8` key needed to sign
provider tokens.

## Layout

```
supabase/functions/
├── _shared/
│   ├── supabase.ts          service-role Supabase client + URL helpers
│   ├── apns.ts              ES256 JWT signer + APNs HTTP/2 push
│   └── push-policy.ts       per-kind toggle, quiet hours, daily-cap gate
├── send-push/               internal entrypoint; one user, one notification
├── dispatch-new-post/       pg_net trigger receiver; fans new_post out
├── dispatch-reaction/       pg_net trigger receiver; fans reaction_received to author
├── dispatch-daily-prompt/   cron every 15m; emits "⏰ time to connecths"
├── memory-engine/           cron hourly; emits memory_resurface at 09:00 local
├── purge-deleted-accounts/  cron daily; hard-deletes accounts past 30-day grace
└── README.md                you are here
```

`send-push` is the only function that talks to APNs. The others are dispatchers
that construct payloads and `fetch(/functions/v1/send-push)` with the
service-role key.

## Deployment (run once after Apple Developer enrollment)

### 1. Set Supabase secrets

```bash
supabase secrets set \
  APNS_KEY_ID=ABCD123456 \
  APNS_TEAM_ID=ABCD123456 \
  APNS_PRIVATE_KEY="$(cat AuthKey_ABCD123456.p8)" \
  APNS_BUNDLE_ID=com.connecths.ConnectHS \
  APNS_ENV=sandbox
```

`APNS_ENV=sandbox` for development/TestFlight builds, `production` for App
Store. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are pre-injected by the
Supabase runtime; nothing to do for those.

### 2. Apply the migration

```bash
supabase db push
```

This adds the `notification_sends` log table and the `daily_prompt` value to
the `notification_kind` enum.

### 3. Deploy the functions

```bash
supabase functions deploy send-push
supabase functions deploy dispatch-new-post
supabase functions deploy dispatch-reaction
supabase functions deploy dispatch-daily-prompt
supabase functions deploy memory-engine
supabase functions deploy purge-deleted-accounts --no-verify-jwt
```

`send-push` and `dispatch-new-post` should set `--no-verify-jwt` so the
internal callers (siblings + the pg_net trigger) can authenticate via the
service-role bearer instead of a user JWT.

### 4. Wire the pg_net trigger for new posts

Run this SQL once via the Supabase SQL editor or `supabase db remote
commit`. The trigger fires `dispatch-new-post` on every successful insert
into `public.posts`.

```sql
CREATE OR REPLACE FUNCTION public.fanout_new_post()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_url TEXT := current_setting('app.settings.functions_url') || '/dispatch-new-post';
  v_key TEXT := current_setting('app.settings.service_role_key');
BEGIN
  PERFORM net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'authorization', 'Bearer ' || v_key,
      'content-type', 'application/json'
    ),
    body    := jsonb_build_object('post_id', NEW.id)
  );
  RETURN NEW;
END $$;

CREATE TRIGGER trg_fanout_new_post
  AFTER INSERT ON public.posts
  FOR EACH ROW
  EXECUTE FUNCTION public.fanout_new_post();

-- Reactions trigger — fires dispatch-reaction on each reaction insert.
CREATE OR REPLACE FUNCTION public.fanout_new_reaction()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public, pg_temp AS $$
DECLARE
  v_url TEXT := current_setting('app.settings.functions_url') || '/dispatch-reaction';
  v_key TEXT := current_setting('app.settings.service_role_key');
BEGIN
  PERFORM net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'authorization', 'Bearer ' || v_key,
      'content-type', 'application/json'
    ),
    body    := jsonb_build_object(
      'post_id',     NEW.post_id,
      'reactor_id',  NEW.user_id,
      'reaction',    NEW.reaction
    )
  );
  RETURN NEW;
END $$;

CREATE TRIGGER trg_fanout_new_reaction
  AFTER INSERT ON public.reactions
  FOR EACH ROW
  EXECUTE FUNCTION public.fanout_new_reaction();
```

Two database settings need to exist (set via `ALTER DATABASE … SET …` once):
- `app.settings.functions_url` → `https://<project>.functions.supabase.co/v1`
- `app.settings.service_role_key` → service role JWT

### 5. Schedule the cron jobs

```sql
-- memory-engine, top of every hour
SELECT cron.schedule(
  'memory-engine',
  '0 * * * *',
  $$ SELECT net.http_post(
       url     := current_setting('app.settings.functions_url') || '/memory-engine',
       headers := jsonb_build_object('authorization', 'Bearer ' || current_setting('app.settings.service_role_key'))
     ); $$
);

-- daily-prompt, every 15 minutes
SELECT cron.schedule(
  'dispatch-daily-prompt',
  '*/15 * * * *',
  $$ SELECT net.http_post(
       url     := current_setting('app.settings.functions_url') || '/dispatch-daily-prompt',
       headers := jsonb_build_object('authorization', 'Bearer ' || current_setting('app.settings.service_role_key'))
     ); $$
);

-- purge-deleted-accounts, once a day at 03:30 UTC (off-peak). Processes
-- up to 25 expired accounts per invocation; if a backlog accumulates the
-- next run picks up the rest.
SELECT cron.schedule(
  'purge-deleted-accounts',
  '30 3 * * *',
  $$ SELECT net.http_post(
       url     := current_setting('app.settings.functions_url') || '/purge-deleted-accounts',
       headers := jsonb_build_object(
         'authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
         'content-type', 'application/json'
       ),
       body    := '{}'::jsonb
     ); $$
);
```

## Local test

You can exercise `send-push` against the sandbox once you have a sandbox APNs
key + a real device token (the simulator can't receive remote pushes):

```bash
curl -X POST http://localhost:54321/functions/v1/send-push \
  -H "authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "content-type: application/json" \
  -d '{
    "user_id": "<uuid>",
    "kind": "new_post",
    "title": "test push",
    "body": "from local",
    "deep_link": "connecths://post/<uuid>"
  }'
```

## Acceptance criteria mapping

The spec/08 acceptance bullets map to these functions:

| Bullet | Function |
|---|---|
| APNs token registers on app foreground | iOS `PushService` (already shipped) |
| 410 Gone deletes the dead token | `send-push` (`deadDeleted` in response) |
| `daily_prompt` notification fires at the scheduled randomized time | `dispatch-daily-prompt` |
| `new_post` push fires within 30s of post insert | `dispatch-new-post` via pg_net trigger |
| `memory_resurface` push fires when memories exist | `memory-engine` |
| `reaction_received` push fires when someone reacts | `dispatch-reaction` via pg_net trigger on `reactions` INSERT |
| Reaction-storm throttling (per-post, per-recipient) | `dispatch-reaction` 5-minute cooldown via `notification_sends` lookup |
| Account deletion: storage + auth.users hard-delete after 30-day grace | `purge-deleted-accounts` daily cron |
| Quiet hours respected | `push-policy.decide` |
| Daily cap of 5 enforced | `push-policy.decide` + `notification_sends` table |
| Per-kind toggles honored | `push-policy.decide` reads `notification_settings` |
| Sign-out removes APNs token | iOS `PushService.unregisterCurrentDevice` (already shipped) |

All bullets covered.
