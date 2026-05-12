-- ConnectHS Initial Schema
-- All tables, enums, indexes, RLS policies, and RPC functions

-- ============================================================
-- ENUMS
-- ============================================================

CREATE TYPE auth_method AS ENUM ('phone', 'apple');
CREATE TYPE group_member_role AS ENUM ('admin', 'member');
CREATE TYPE invite_status AS ENUM ('pending', 'accepted', 'expired', 'revoked');
CREATE TYPE reaction_type AS ENUM (
  'heart', 'fire', 'laugh', 'wow', 'sad', 'thumbs_up'
);
CREATE TYPE moment_kind AS ENUM ('dual_photo');
CREATE TYPE notification_kind AS ENUM (
  'new_post', 'memory_resurface', 'group_invite_accepted', 'reaction_received'
);

-- ============================================================
-- USERS — extends Supabase auth.users
-- ============================================================
CREATE TABLE public.users (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name    TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 40),
  phone_number    TEXT UNIQUE,
  apple_user_id   TEXT UNIQUE,
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

-- ============================================================
-- GROUPS
-- ============================================================
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

-- ============================================================
-- GROUP MEMBERSHIPS
-- ============================================================
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

-- ============================================================
-- GROUP INVITES
-- ============================================================
CREATE TABLE public.group_invites (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  invite_code     TEXT NOT NULL UNIQUE,
  created_by      UUID NOT NULL REFERENCES public.users(id),
  max_uses        INTEGER,
  uses_count      INTEGER NOT NULL DEFAULT 0,
  expires_at      TIMESTAMPTZ NOT NULL,
  status          invite_status NOT NULL DEFAULT 'pending',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_invites_code ON public.group_invites(invite_code);

-- ============================================================
-- POSTS
-- ============================================================
CREATE TABLE public.posts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  author_id       UUID NOT NULL REFERENCES public.users(id),
  kind            moment_kind NOT NULL DEFAULT 'dual_photo',
  front_image_path TEXT NOT NULL,
  back_image_path  TEXT NOT NULL,
  caption          TEXT CHECK (char_length(caption) <= 140),
  prompt_date     DATE NOT NULL,
  prompt_time     TIMESTAMPTZ NOT NULL,
  posted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  is_late         BOOLEAN NOT NULL DEFAULT FALSE,
  is_archived     BOOLEAN NOT NULL DEFAULT FALSE,
  deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_posts_group_date  ON public.posts(group_id, prompt_date DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_posts_author      ON public.posts(author_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_posts_anniversary ON public.posts(group_id, EXTRACT(MONTH FROM prompt_date), EXTRACT(DAY FROM prompt_date)) WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX idx_posts_one_per_day_per_group
  ON public.posts(group_id, author_id, prompt_date)
  WHERE deleted_at IS NULL;

-- ============================================================
-- REACTIONS
-- ============================================================
CREATE TABLE public.reactions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id         UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reaction        reaction_type NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (post_id, user_id, reaction)
);

CREATE INDEX idx_reactions_post ON public.reactions(post_id);

-- ============================================================
-- POST VIEWS
-- ============================================================
CREATE TABLE public.post_views (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id         UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  viewed_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (post_id, user_id)
);

CREATE INDEX idx_post_views_post ON public.post_views(post_id);

-- ============================================================
-- DEVICE TOKENS (APNs)
-- ============================================================
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

-- ============================================================
-- NOTIFICATION SETTINGS
-- ============================================================
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

-- ============================================================
-- DAILY PROMPTS
-- ============================================================
CREATE TABLE public.daily_prompts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  prompt_date     DATE NOT NULL,
  prompt_time     TIMESTAMPTZ NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (group_id, prompt_date)
);

CREATE INDEX idx_daily_prompts_date ON public.daily_prompts(prompt_date);

-- ============================================================
-- REPORTS
-- ============================================================
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

-- ============================================================
-- ROW-LEVEL SECURITY — enable on ALL tables
-- ============================================================

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

-- ============================================================
-- RLS HELPER FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_group_member(gid UUID)
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.group_memberships
    WHERE group_id = gid AND user_id = auth.uid() AND left_at IS NULL
  );
$$;

-- ============================================================
-- RLS POLICIES — users
-- ============================================================

CREATE POLICY users_self_select ON public.users FOR SELECT
  USING (id = auth.uid());

CREATE POLICY users_shared_group_select ON public.users FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.group_memberships m1
    JOIN public.group_memberships m2 ON m1.group_id = m2.group_id
    WHERE m1.user_id = auth.uid() AND m2.user_id = public.users.id
      AND m1.left_at IS NULL AND m2.left_at IS NULL
  ));

CREATE POLICY users_self_update ON public.users FOR UPDATE
  USING (id = auth.uid());

CREATE POLICY users_self_insert ON public.users FOR INSERT
  WITH CHECK (id = auth.uid());

-- ============================================================
-- RLS POLICIES — groups
-- ============================================================

CREATE POLICY groups_member_select ON public.groups FOR SELECT
  USING (public.is_group_member(id));

CREATE POLICY groups_creator_insert ON public.groups FOR INSERT
  WITH CHECK (created_by = auth.uid());

CREATE POLICY groups_admin_update ON public.groups FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM public.group_memberships
    WHERE group_id = public.groups.id AND user_id = auth.uid()
      AND role = 'admin' AND left_at IS NULL
  ));

-- ============================================================
-- RLS POLICIES — group_memberships
-- ============================================================

CREATE POLICY memberships_group_select ON public.group_memberships FOR SELECT
  USING (public.is_group_member(group_id));

-- ============================================================
-- RLS POLICIES — group_invites (readable by group members)
-- ============================================================

CREATE POLICY invites_member_select ON public.group_invites FOR SELECT
  USING (public.is_group_member(group_id));

-- ============================================================
-- RLS POLICIES — posts
-- ============================================================

CREATE POLICY posts_member_select ON public.posts FOR SELECT
  USING (public.is_group_member(group_id) AND deleted_at IS NULL);

CREATE POLICY posts_self_insert ON public.posts FOR INSERT
  WITH CHECK (author_id = auth.uid() AND public.is_group_member(group_id));

CREATE POLICY posts_self_update ON public.posts FOR UPDATE
  USING (author_id = auth.uid());

-- ============================================================
-- RLS POLICIES — reactions
-- ============================================================

CREATE POLICY reactions_member_select ON public.reactions FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.posts p WHERE p.id = post_id AND public.is_group_member(p.group_id)
  ));

CREATE POLICY reactions_self_insert ON public.reactions FOR INSERT
  WITH CHECK (user_id = auth.uid() AND EXISTS (
    SELECT 1 FROM public.posts p WHERE p.id = post_id AND public.is_group_member(p.group_id)
  ));

CREATE POLICY reactions_self_delete ON public.reactions FOR DELETE
  USING (user_id = auth.uid());

-- ============================================================
-- RLS POLICIES — post_views
-- ============================================================

CREATE POLICY views_self_insert ON public.post_views FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY views_author_select ON public.post_views FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.posts p WHERE p.id = post_id AND p.author_id = auth.uid()
  ));

-- ============================================================
-- RLS POLICIES — device_tokens, notification_settings (self only)
-- ============================================================

CREATE POLICY device_tokens_self ON public.device_tokens FOR ALL
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY notification_settings_self ON public.notification_settings FOR ALL
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ============================================================
-- RPC FUNCTIONS
-- ============================================================

-- Create a new group and add the creator as admin
CREATE OR REPLACE FUNCTION public.create_group(
  p_name TEXT,
  p_emoji TEXT
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  new_group_id UUID;
BEGIN
  INSERT INTO public.groups (name, emoji, created_by)
  VALUES (p_name, p_emoji, auth.uid())
  RETURNING id INTO new_group_id;

  INSERT INTO public.group_memberships (group_id, user_id, role)
  VALUES (new_group_id, auth.uid(), 'admin');

  RETURN new_group_id;
END $$;

-- Generate an invite link for a group
CREATE OR REPLACE FUNCTION public.create_invite(
  p_group_id UUID,
  p_max_uses INTEGER DEFAULT NULL
) RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  code TEXT;
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
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  invite RECORD;
  current_member_count INTEGER;
BEGIN
  SELECT * INTO invite FROM public.group_invites
  WHERE invite_code = p_code AND status = 'pending'
    AND expires_at > NOW()
    AND (max_uses IS NULL OR uses_count < max_uses)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired invite';
  END IF;

  SELECT COUNT(*) INTO current_member_count FROM public.group_memberships
    WHERE group_id = invite.group_id AND left_at IS NULL;

  IF current_member_count >= 25 THEN
    RAISE EXCEPTION 'Group is full';
  END IF;

  IF EXISTS (SELECT 1 FROM public.group_memberships
             WHERE group_id = invite.group_id AND user_id = auth.uid() AND left_at IS NULL) THEN
    RETURN invite.group_id;
  END IF;

  INSERT INTO public.group_memberships (group_id, user_id, role)
  VALUES (invite.group_id, auth.uid(), 'member');

  UPDATE public.group_invites SET uses_count = uses_count + 1
    WHERE id = invite.id;

  RETURN invite.group_id;
END $$;

-- Toggle a reaction
CREATE OR REPLACE FUNCTION public.toggle_reaction(
  p_post_id UUID,
  p_reaction reaction_type
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER AS $$
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
RETURNS VOID
LANGUAGE SQL SECURITY DEFINER AS $$
  INSERT INTO public.post_views (post_id, user_id)
  VALUES (p_post_id, auth.uid())
  ON CONFLICT DO NOTHING;
$$;

-- Get today's feed for a group
CREATE OR REPLACE FUNCTION public.get_feed(p_group_id UUID, p_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
  post_id UUID,
  author_id UUID,
  author_name TEXT,
  author_avatar TEXT,
  front_image_path TEXT,
  back_image_path TEXT,
  caption TEXT,
  posted_at TIMESTAMPTZ,
  is_late BOOLEAN,
  view_count INTEGER,
  reaction_summary JSONB
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
    ) sub)
  FROM public.posts p
  JOIN public.users u ON u.id = p.author_id
  WHERE p.group_id = p_group_id
    AND p.prompt_date = p_date
    AND p.deleted_at IS NULL
    AND public.is_group_member(p.group_id)
  ORDER BY p.posted_at DESC;
$$;

-- Memory Engine: get "on this day in past years" for a group
CREATE OR REPLACE FUNCTION public.get_memories(p_group_id UUID, p_today DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
  post_id UUID,
  prompt_date DATE,
  years_ago INTEGER,
  author_name TEXT,
  front_image_path TEXT,
  back_image_path TEXT,
  caption TEXT
) LANGUAGE SQL SECURITY DEFINER STABLE AS $$
  SELECT
    p.id,
    p.prompt_date,
    EXTRACT(YEAR FROM AGE(p_today, p.prompt_date))::INT AS years_ago,
    u.display_name,
    p.front_image_path,
    p.back_image_path,
    p.caption
  FROM public.posts p
  JOIN public.users u ON u.id = p.author_id
  WHERE p.group_id = p_group_id
    AND EXTRACT(MONTH FROM p.prompt_date) = EXTRACT(MONTH FROM p_today)
    AND EXTRACT(DAY FROM p.prompt_date)   = EXTRACT(DAY FROM p_today)
    AND p.prompt_date < p_today
    AND p.deleted_at IS NULL
    AND public.is_group_member(p.group_id)
  ORDER BY p.prompt_date DESC;
$$;
