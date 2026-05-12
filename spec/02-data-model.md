# 02 — Data Model

The full Postgres schema. Apply this to Supabase **before** writing any Swift model code, then have the agent read the live schema via Supabase MCP and generate Codable models.

## Conventions

- All primary keys are `UUID` (default `gen_random_uuid()`).
- All timestamps are `timestamptz` UTC. Client converts to local.
- Soft deletes via `deleted_at` column where user content can be removed.
- Snake_case column names (Postgres convention). Swift `CodingKeys` map to camelCase.

## Entity relationship overview

```
users
  ├── group_memberships ── groups
  │                          └── group_invites
  └── posts
       ├── reactions
       └── post_views

device_tokens (APNs)
notification_settings
daily_prompts
reports
```

## Enums

```sql
CREATE TYPE auth_method AS ENUM ('phone', 'apple');
CREATE TYPE group_member_role AS ENUM ('admin', 'member');
CREATE TYPE invite_status AS ENUM ('pending', 'accepted', 'expired', 'revoked');
CREATE TYPE reaction_type AS ENUM ('heart', 'fire', 'laugh', 'wow', 'sad', 'thumbs_up');
CREATE TYPE moment_kind AS ENUM ('dual_photo');
CREATE TYPE notification_kind AS ENUM (
  'new_post', 'memory_resurface', 'group_invite_accepted', 'reaction_received'
);
```

## Tables

### users
Extends Supabase `auth.users`.

```sql
CREATE TABLE public.users (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name    TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 40),
  phone_number    TEXT UNIQUE,                         -- E.164; null if Apple-only
  apple_user_id   TEXT UNIQUE,                         -- Apple's stable sub
  auth_method     auth_method NOT NULL,
  avatar_url      TEXT,
  high_school     TEXT,
  grad_year       INTEGER CHECK (grad_year BETWEEN 2020 AND 2035),
  birthday        DATE,
  timezone        TEXT NOT NULL DEFAULT 'America/New_York',
  is_age_verified BOOLEAN NOT NULL DEFAULT FALSE,
  is_blocked      BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_users_phone ON public.users(phone_number) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_apple ON public.users(apple_user_id) WHERE deleted_at IS NULL;
```

### groups

```sql
CREATE TABLE public.groups (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
  emoji           TEXT,
  created_by      UUID NOT NULL REFERENCES public.users(id),
  member_limit    INTEGER NOT NULL DEFAULT 25 CHECK (member_limit BETWEEN 5 AND 25),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_groups_created_by ON public.groups(created_by);
```

### group_memberships

```sql
CREATE TABLE public.group_memberships (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role            group_member_role NOT NULL DEFAULT 'member',
  joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  left_at         TIMESTAMPTZ,
  UNIQUE (group_id, user_id)
);

CREATE INDEX idx_memberships_group ON public.group_memberships(group_id) WHERE left_at IS NULL;
CREATE INDEX idx_memberships_user  ON public.group_memberships(user_id)  WHERE left_at IS NULL;
```

### group_invites

```sql
CREATE TABLE public.group_invites (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  invite_code     TEXT NOT NULL UNIQUE,                -- 8-char shortcode
  created_by      UUID NOT NULL REFERENCES public.users(id),
  max_uses        INTEGER,                             -- null = unlimited (within cap)
  uses_count      INTEGER NOT NULL DEFAULT 0,
  expires_at      TIMESTAMPTZ NOT NULL,                -- default 7 days
  status          invite_status NOT NULL DEFAULT 'pending',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_invites_code ON public.group_invites(invite_code);
```

### posts

```sql
CREATE TABLE public.posts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  author_id       UUID NOT NULL REFERENCES public.users(id),
  kind            moment_kind NOT NULL DEFAULT 'dual_photo',
  front_image_path TEXT NOT NULL,                      -- e.g. "posts/{id}/front.webp"
  back_image_path  TEXT NOT NULL,
  caption          TEXT CHECK (char_length(caption) <= 140),
  prompt_date     DATE NOT NULL,                       -- calendar day this satisfies
  prompt_time     TIMESTAMPTZ NOT NULL,                -- when ConnectHS notified
  posted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  is_late         BOOLEAN NOT NULL DEFAULT FALSE,      -- posted_at > prompt_time + 2h
  is_archived     BOOLEAN NOT NULL DEFAULT FALSE,
  deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_posts_group_date  ON public.posts(group_id, prompt_date DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_posts_author      ON public.posts(author_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_posts_anniversary ON public.posts(group_id, EXTRACT(MONTH FROM prompt_date), EXTRACT(DAY FROM prompt_date)) WHERE deleted_at IS NULL;

-- One post per user per group per day
CREATE UNIQUE INDEX idx_posts_one_per_day_per_group
  ON public.posts(group_id, author_id, prompt_date)
  WHERE deleted_at IS NULL;
```

### reactions

```sql
CREATE TABLE public.reactions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id         UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reaction        reaction_type NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (post_id, user_id, reaction)
);

CREATE INDEX idx_reactions_post ON public.reactions(post_id);
```

### post_views

```sql
CREATE TABLE public.post_views (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id         UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  viewed_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (post_id, user_id)
);

CREATE INDEX idx_post_views_post ON public.post_views(post_id);
```

### device_tokens

```sql
CREATE TABLE public.device_tokens (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  apns_token      TEXT NOT NULL,
  device_id       TEXT NOT NULL,
  app_version     TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, device_id)
);

CREATE INDEX idx_device_tokens_user ON public.device_tokens(user_id);
```

### notification_settings

```sql
CREATE TABLE public.notification_settings (
  user_id              UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  daily_prompt_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  daily_prompt_window_start TIME NOT NULL DEFAULT '10:00',
  daily_prompt_window_end   TIME NOT NULL DEFAULT '22:00',
  new_post_enabled     BOOLEAN NOT NULL DEFAULT TRUE,
  memory_enabled       BOOLEAN NOT NULL DEFAULT TRUE,
  reaction_enabled     BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### daily_prompts

```sql
CREATE TABLE public.daily_prompts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  prompt_date     DATE NOT NULL,
  prompt_time     TIMESTAMPTZ NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (group_id, prompt_date)
);

CREATE INDEX idx_daily_prompts_date ON public.daily_prompts(prompt_date);
```

### reports

```sql
CREATE TABLE public.reports (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id     UUID NOT NULL REFERENCES public.users(id),
  reported_user_id UUID REFERENCES public.users(id),
  reported_post_id UUID REFERENCES public.posts(id),
  reason          TEXT NOT NULL,
  details         TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at     TIMESTAMPTZ,
  resolution_note TEXT
);

CREATE INDEX idx_reports_unresolved ON public.reports(created_at) WHERE resolved_at IS NULL;
```

## Row-Level Security (RLS)

**Every table has RLS enabled. This is non-negotiable.**

```sql
ALTER TABLE public.users               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groups              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_memberships   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_invites       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reactions           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_views          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_tokens       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_prompts       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports             ENABLE ROW LEVEL SECURITY;

-- Helper function
CREATE OR REPLACE FUNCTION public.is_group_member(gid UUID)
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.group_memberships
    WHERE group_id = gid AND user_id = auth.uid() AND left_at IS NULL
  );
$$;
```

### Policies

**users** — see self always; see other users only via shared group:

```sql
CREATE POLICY users_self_select ON public.users FOR SELECT USING (id = auth.uid());

CREATE POLICY users_shared_group_select ON public.users FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.group_memberships m1
    JOIN public.group_memberships m2 ON m1.group_id = m2.group_id
    WHERE m1.user_id = auth.uid() AND m2.user_id = public.users.id
      AND m1.left_at IS NULL AND m2.left_at IS NULL
  )
);

CREATE POLICY users_self_update ON public.users FOR UPDATE USING (id = auth.uid());
```

**groups** — members only:

```sql
CREATE POLICY groups_member_select ON public.groups FOR SELECT
  USING (public.is_group_member(id));

CREATE POLICY groups_creator_insert ON public.groups FOR INSERT
  WITH CHECK (created_by = auth.uid());

CREATE POLICY groups_admin_update ON public.groups FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM public.group_memberships
    WHERE group_id = public.groups.id AND user_id = auth.uid()
      AND role = 'admin' AND left_at IS NULL
  )
);
```

**group_memberships** — members can see roster:

```sql
CREATE POLICY memberships_group_select ON public.group_memberships FOR SELECT
  USING (public.is_group_member(group_id));
```

**posts**:

```sql
CREATE POLICY posts_member_select ON public.posts FOR SELECT
  USING (public.is_group_member(group_id) AND deleted_at IS NULL);

CREATE POLICY posts_self_insert ON public.posts FOR INSERT
  WITH CHECK (author_id = auth.uid() AND public.is_group_member(group_id));

CREATE POLICY posts_self_update ON public.posts FOR UPDATE
  USING (author_id = auth.uid());
```

**reactions**:

```sql
CREATE POLICY reactions_member_select ON public.reactions FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_id AND public.is_group_member(p.group_id))
);

CREATE POLICY reactions_self_insert ON public.reactions FOR INSERT WITH CHECK (
  user_id = auth.uid() AND
  EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_id AND public.is_group_member(p.group_id))
);

CREATE POLICY reactions_self_delete ON public.reactions FOR DELETE
  USING (user_id = auth.uid());
```

**post_views** — write self only; read by post author:

```sql
CREATE POLICY views_self_insert ON public.post_views FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY views_author_select ON public.post_views FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_id AND p.author_id = auth.uid())
);
```

**device_tokens, notification_settings** — self only:

```sql
CREATE POLICY device_tokens_self ON public.device_tokens FOR ALL
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY notification_settings_self ON public.notification_settings FOR ALL
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
```

## RPC functions (server-side, called from client)

```sql
-- Create a new group, add creator as admin
CREATE OR REPLACE FUNCTION public.create_group(p_name TEXT, p_emoji TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE new_group_id UUID;
BEGIN
  INSERT INTO public.groups (name, emoji, created_by)
  VALUES (p_name, p_emoji, auth.uid())
  RETURNING id INTO new_group_id;

  INSERT INTO public.group_memberships (group_id, user_id, role)
  VALUES (new_group_id, auth.uid(), 'admin');

  RETURN new_group_id;
END $$;

-- Generate an invite code
CREATE OR REPLACE FUNCTION public.create_invite(p_group_id UUID, p_max_uses INTEGER DEFAULT NULL)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE code TEXT;
BEGIN
  IF NOT public.is_group_member(p_group_id) THEN
    RAISE EXCEPTION 'Not a group member';
  END IF;

  code := encode(gen_random_bytes(6), 'base64');
  code := replace(replace(replace(code, '/', ''), '+', ''), '=', '');
  code := substring(code from 1 for 8);

  INSERT INTO public.group_invites (group_id, invite_code, created_by, max_uses, expires_at)
  VALUES (p_group_id, code, auth.uid(), p_max_uses, NOW() + INTERVAL '7 days');

  RETURN code;
END $$;

-- Redeem an invite
CREATE OR REPLACE FUNCTION public.redeem_invite(p_code TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE invite RECORD; current_member_count INTEGER;
BEGIN
  SELECT * INTO invite FROM public.group_invites
  WHERE invite_code = p_code AND status = 'pending'
    AND expires_at > NOW()
    AND (max_uses IS NULL OR uses_count < max_uses)
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Invalid or expired invite'; END IF;

  SELECT COUNT(*) INTO current_member_count FROM public.group_memberships
    WHERE group_id = invite.group_id AND left_at IS NULL;

  IF current_member_count >= 25 THEN RAISE EXCEPTION 'Group is full'; END IF;

  IF EXISTS (SELECT 1 FROM public.group_memberships
             WHERE group_id = invite.group_id AND user_id = auth.uid() AND left_at IS NULL) THEN
    RETURN invite.group_id;
  END IF;

  INSERT INTO public.group_memberships (group_id, user_id, role)
  VALUES (invite.group_id, auth.uid(), 'member');

  UPDATE public.group_invites SET uses_count = uses_count + 1 WHERE id = invite.id;
  RETURN invite.group_id;
END $$;

-- Toggle reaction
CREATE OR REPLACE FUNCTION public.toggle_reaction(p_post_id UUID, p_reaction reaction_type)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.reactions
             WHERE post_id = p_post_id AND user_id = auth.uid() AND reaction = p_reaction) THEN
    DELETE FROM public.reactions
      WHERE post_id = p_post_id AND user_id = auth.uid() AND reaction = p_reaction;
    RETURN FALSE;
  ELSE
    INSERT INTO public.reactions (post_id, user_id, reaction)
      VALUES (p_post_id, auth.uid(), p_reaction);
    RETURN TRUE;
  END IF;
END $$;

-- Mark a post as viewed
CREATE OR REPLACE FUNCTION public.mark_viewed(p_post_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER AS $$
  INSERT INTO public.post_views (post_id, user_id) VALUES (p_post_id, auth.uid())
  ON CONFLICT DO NOTHING;
$$;

-- Get today's feed for a group
CREATE OR REPLACE FUNCTION public.get_feed(p_group_id UUID, p_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
  post_id UUID, author_id UUID, author_name TEXT, author_avatar TEXT,
  front_image_path TEXT, back_image_path TEXT, caption TEXT,
  posted_at TIMESTAMPTZ, is_late BOOLEAN,
  view_count INTEGER, reaction_summary JSONB
) LANGUAGE SQL SECURITY DEFINER STABLE AS $$
  SELECT
    p.id, p.author_id, u.display_name, u.avatar_url,
    p.front_image_path, p.back_image_path, p.caption,
    p.posted_at, p.is_late,
    (SELECT COUNT(*)::INT FROM public.post_views WHERE post_id = p.id),
    (SELECT jsonb_object_agg(reaction, cnt) FROM (
      SELECT reaction, COUNT(*)::INT AS cnt FROM public.reactions
      WHERE post_id = p.id GROUP BY reaction
    ) sub)
  FROM public.posts p
  JOIN public.users u ON u.id = p.author_id
  WHERE p.group_id = p_group_id AND p.prompt_date = p_date
    AND p.deleted_at IS NULL AND public.is_group_member(p.group_id)
  ORDER BY p.posted_at DESC;
$$;

-- Memory Engine: get "on this day" content
CREATE OR REPLACE FUNCTION public.get_memories(p_group_id UUID, p_today DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
  post_id UUID, prompt_date DATE, years_ago INTEGER,
  author_name TEXT, front_image_path TEXT, back_image_path TEXT, caption TEXT
) LANGUAGE SQL SECURITY DEFINER STABLE AS $$
  SELECT
    p.id, p.prompt_date,
    EXTRACT(YEAR FROM AGE(p_today, p.prompt_date))::INT,
    u.display_name, p.front_image_path, p.back_image_path, p.caption
  FROM public.posts p
  JOIN public.users u ON u.id = p.author_id
  WHERE p.group_id = p_group_id
    AND EXTRACT(MONTH FROM p.prompt_date) = EXTRACT(MONTH FROM p_today)
    AND EXTRACT(DAY FROM p.prompt_date)   = EXTRACT(DAY FROM p_today)
    AND p.prompt_date < p_today
    AND p.deleted_at IS NULL AND public.is_group_member(p.group_id)
  ORDER BY p.prompt_date DESC;
$$;
```

## Storage buckets

```
posts/                            (private; signed URLs only)
  {post_id}/
    front.webp                    1080x1080, ~70-100 KB, quality 80
    back.webp                     1080x1080, ~70-100 KB
    front_thumb.webp              256x256, ~15 KB
    back_thumb.webp               256x256, ~15 KB

avatars/                          (public read; self write)
  {user_id}.webp                  256x256
```

Image format: WebP, quality 80, max edge 1080px. Generate 256x256 thumbnails server-side via `process-upload` Edge Function on storage `object_inserted` event.

## Acceptance criteria for this spec

- [ ] All 11 tables created with correct constraints
- [ ] All RLS policies applied and tested with two users in different groups (no cross-group leakage)
- [ ] All RPC functions return expected results
- [ ] `posts/` and `avatars/` buckets created with correct policies
- [ ] Indices created (verify query plans use them)
- [ ] Test: a member can read their group's posts; a non-member cannot
- [ ] Test: a user cannot insert a post for another user (`author_id` mismatch)
- [ ] Test: invite redemption fails when group is full (25 members)
