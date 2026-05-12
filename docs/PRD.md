# ConnectHS — Product Requirements Document (v1.0)

**Owner:** Alexander Baig
**Document type:** Engineering-ready PRD for Claude Code
**Target launch:** June 18, 2026 (Apple Developer enrollment Day 1, TestFlight Day 2, public App Store release Week 1 of summer adoption window)
**Platform:** iOS 17+ native (iPhone), with WidgetKit home-screen widget
**Doc version:** 1.0 — initial build spec

---

## 0. How to use this document

This PRD is written to be handed directly to Claude Code as a build spec. It contains:

- The complete v1 (MVP) feature definition
- Full data model (Postgres / Supabase) with SQL DDL
- Auth flow specs (phone OTP + Sign in with Apple)
- Screen-by-screen UX specs with state diagrams
- Widget spec (WidgetKit)
- API contracts (Supabase RPC + Edge Functions)
- Push notification specs
- Storage and security model (Row-Level Security policies)
- Acceptance criteria per feature
- Build order and milestone dates
- Out-of-scope features (explicit list to prevent scope creep)

**Build philosophy:** This is a *consumer social* product. The single biggest predictor of failure is shipping a feature-rich product that nobody can figure out in 30 seconds. Every screen is built for "first-time user, distracted, on a subway." Polish and empty-state UX matter more than feature count.

---

## 1. Product overview

### 1.1 The product in one sentence
**ConnectHS is a closed, small-group iOS app that lets a high school friend group share a daily dual-camera "moment" — and keeps every moment forever, surfacing them as shared memories — so the friendships survive the great separation of college.**

### 1.2 The 10-second pitch (what users will read on the App Store)
> Your group chat is going to die. ConnectHS is the place your high school friends actually still live — after.
> One photo a day, dual-camera. Closed group, 5-25 friends. Every memory kept forever.

### 1.3 Target user
- **Primary:** High school seniors (Class of 2026), ages 17-18, U.S., heading to college in fall 2026.
- **Secondary:** College freshmen and sophomores still trying to maintain HS friendships (ages 18-20).
- **Critical adoption window:** June 1 - August 31, 2026 (the summer between graduation and college start).

### 1.4 Core problem statement
After high school, friend groups scatter geographically. Group chats die within ~3 months (universal observation). Existing apps (Snapchat, Instagram, BeReal, Locket) are not purpose-built for the small, durable, graduating-class-cohort use case. The pain is real, named ("the great separation" — TikTok), and underserved.

### 1.5 Core insight & product wedge
Two structural facts shape the product:

1. **Robin Dunbar's research:** ~9 minutes of contact per day sustains a close friendship; 100 days of insufficient contact decays it materially.
2. **BeReal's failure mode:** novelty without iteration, no memory layer, prompt-as-chore. Locket's success mode: ambient widget, narrow surface area, no public feed.

**The wedge:** A BeReal-style daily dual-camera prompt for a *closed friend group*, but with **permanent archive** and a **memory engine** that resurfaces shared past moments. The memory layer is the compound-interest feature — the longer the user is on the app, the more valuable it gets.

### 1.6 Anti-goals (explicit non-features)
The following are deliberate exclusions to prevent BeReal/Geneva-style overscope:

- ❌ No public feed, no algorithmic feed, no discovery
- ❌ No follower counts, no public profiles, no usernames-as-vanity
- ❌ No streaks (Snapchat trains anxiety; we use the Memory Engine for habit instead)
- ❌ No DMs / chat / messaging surface in v1 (group chat is the death pattern we're fighting)
- ❌ No filters, AR, lenses, or stickers in v1
- ❌ No video posts in v1 (photos only — keeps storage bill flat and ships faster)
- ❌ No stranger discovery — closed graph only
- ❌ No NFTs, crypto, Web3, AI avatars
- ❌ No ads ever; data is never sold

### 1.7 Success metrics

| Metric | Target | Source / benchmark |
|---|---|---|
| W1 retention | ≥ 50% | Andrew Chen network-effect threshold |
| W4 retention | ≥ 30% | Andrew Chen network-effect threshold |
| DAU/MAU ratio | ≥ 0.3 by month 6 | Locket precedent |
| Average group size at activation | 8-12 | Sweet spot per research |
| Posts per active user per week | ≥ 4 | Daily prompt = 7, allow for weekend dropoff |
| Crash-free sessions | ≥ 99.5% | App Store quality benchmark |
| Sign-up to first post (TTV) | < 60 seconds | Onboarding success threshold |
| Group full-formation rate (≥3 friends accept) | ≥ 60% of inviters | Cold-start health |

---

## 2. v1 (MVP) Feature Scope — what gets built

The v1 scope is deliberately narrow. Four features. Build them well.

### 2.1 In-scope features (v1)

| # | Feature | Priority | Owner of complexity |
|---|---|---|---|
| F1 | **Auth** — Phone number + Sign in with Apple | P0 | Supabase Auth |
| F2 | **Closed friend group** (5-25 people, phone-verified, invite-by-link) | P0 | Postgres + RLS |
| F3 | **Daily dual-camera moment** (front + back simultaneous capture, BeReal-style with our improvements) | P0 | AVFoundation `AVCaptureMultiCamSession` |
| F4 | **Memory Engine** (daily resurfacing of "X year(s) ago today" content) | P0 | Edge Function cron + push |
| F5 | **Permanent archive** (browsable timeline of every moment ever posted) | P0 | Database query + UI |
| F6 | **Home-screen widget** (latest moment from group, tap-to-open) | P0 | WidgetKit |
| F7 | **Async reactions** (emoji-only in v1, no text comments) | P0 | Postgres |
| F8 | **Push notifications** (new posts, memory resurfacing) | P0 | APNs via Supabase Edge Functions |

### 2.2 Out-of-scope (v1) — explicit deferral list

These are good ideas. They are not v1.

- Voice notes as a moment type → v1.5 (post-launch month 2)
- Text status as a moment type → v1.5
- Multiple groups per user → v2 (post-launch month 3)
- Async voice/video replies → v2
- Calendar / reunion features → v2
- Premium subscription tier → v2 (post-launch month 6)
- Optional location sharing → v2
- Android version → v2 (build only after iOS PMF)
- Shared albums / collaborative memories → v2
- Birthday / anniversary tracking → v2

---

## 3. Tech stack & architecture

### 3.1 Client (iOS)

| Layer | Choice | Rationale |
|---|---|---|
| Language | Swift 5.9+ | Native is required for widget + dual-camera quality |
| UI framework | SwiftUI (primary) + UIKit (camera, where needed) | SwiftUI for speed; UIKit for AVFoundation hosts |
| Min iOS version | iOS 17.0 | Interactive Widgets, StandBy, modern Camera API; ~92% of active iPhones as of late 2025 |
| Camera | AVFoundation `AVCaptureMultiCamSession` | True simultaneous front+back capture (BeReal mechanic) |
| Widget | WidgetKit (small + medium sizes) + App Group shared container | Native, low-latency, image-based |
| Local storage | SwiftData (iOS 17+) | Modern Core Data successor; works seamlessly with SwiftUI |
| Networking | URLSession + Supabase Swift SDK | Official SDK handles auth, realtime, RLS |
| Async | Swift Concurrency (`async`/`await`, `Actor`) | Modern, safer than Combine for this scope |
| Image handling | `PHPickerViewController` (read-only), `ImageIO` for compression | Privacy-first photo access |
| Push | APNs via `UNUserNotificationCenter` + Supabase Edge Function trigger | Native iOS push; no Firebase |
| Analytics | PostHog (self-hostable, open-source, privacy-friendly) | No Mixpanel / Segment / Amplitude — too noisy for an "anti-attention" brand |
| Crash reporting | Sentry | Standard, free tier sufficient for v1 |

### 3.2 Backend

| Layer | Choice | Rationale |
|---|---|---|
| Hosted platform | **Supabase** (managed; Pro plan ~$25/mo at launch, scales with usage) | Postgres + Auth + Storage + Realtime + Edge Functions in one |
| Database | Postgres 15 with Row-Level Security (RLS) | Closed-graph privacy is enforced *at the database layer*, not in app code |
| Auth | Supabase Auth (Phone OTP via Twilio + Sign in with Apple OIDC) | Free for both methods; Twilio billed per-OTP (~$0.0079/OTP US) |
| Storage | Supabase Storage (S3-compatible, with signed URLs) | Photos stored as `webp` and `jpeg`, served via CDN-cached signed URLs |
| Realtime | Supabase Realtime (Postgres LISTEN/NOTIFY) | New post notifications pushed to widgets without polling |
| Background jobs | Supabase Edge Functions (Deno runtime) + `pg_cron` | Memory Engine runs daily at 09:00 user-local; APNs push dispatch |
| File CDN | Supabase Storage CDN (Cloudflare) | Free; included in Storage |

### 3.3 Third-party services

| Service | Purpose | Cost (v1) |
|---|---|---|
| Supabase (Pro) | Backend platform | $25/mo + usage |
| Twilio | Phone OTP delivery | ~$0.008/SMS US |
| Apple Push Notification service | iOS push (free with developer account) | $0 |
| Sentry | Crash reporting | $0 (developer plan) |
| PostHog Cloud | Product analytics | $0 (free tier <1M events/mo) |
| Apple Developer Program | App Store distribution | $99/year (enroll June 16, 2026) |

**Total monthly run-rate at 0-1K users:** ~$30/mo + Twilio (estimate $20/mo at this scale) = **~$50/mo total**. At 100K MAU, expect ~$300-500/mo.

### 3.4 Repository structure

```
connecths/
├── ios/                          # Xcode workspace
│   ├── ConnectHS.xcworkspace
│   ├── ConnectHS/                # Main app target
│   │   ├── App/
│   │   │   ├── ConnectHSApp.swift
│   │   │   └── AppDelegate.swift
│   │   ├── Auth/                 # Onboarding, OTP, Apple SSO
│   │   ├── Group/                # Group creation, invite, member list
│   │   ├── Camera/               # Dual-camera capture
│   │   ├── Feed/                 # Today's moments view
│   │   ├── Archive/              # Permanent timeline browser
│   │   ├── Memory/               # Memory Engine UI
│   │   ├── Profile/              # Settings, account
│   │   ├── Components/           # Shared SwiftUI views
│   │   ├── Models/               # Codable types matching DB schema
│   │   ├── Services/             # SupabaseClient, AuthService, etc.
│   │   ├── Storage/              # SwiftData / cache layer
│   │   └── Resources/            # Assets, Localizable.strings
│   ├── ConnectHSWidget/          # WidgetKit extension target
│   │   ├── ConnectHSWidget.swift
│   │   ├── WidgetProvider.swift
│   │   └── WidgetViews.swift
│   ├── Shared/                   # App Group shared code (used by app + widget)
│   │   ├── SharedDefaults.swift
│   │   └── SharedImageCache.swift
│   └── ConnectHSTests/           # Unit + UI tests
├── supabase/
│   ├── migrations/               # SQL migrations (versioned)
│   ├── functions/                # Edge Functions (Deno/TypeScript)
│   │   ├── memory-engine/        # Daily resurface job
│   │   ├── send-push/            # APNs dispatcher
│   │   └── invite-redeem/        # Group invite link redemption
│   ├── seed.sql                  # Local dev seed data
│   └── config.toml
├── docs/
│   ├── PRD.md                    # this document
│   ├── DATA_MODEL.md
│   └── API.md
├── .github/workflows/            # CI: lint, test, build
└── README.md
```

---

## 4. Data model (Postgres / Supabase)

All tables use UUIDv4 primary keys. All timestamps are `timestamptz` in UTC; client converts to local. Soft-delete via `deleted_at` is used everywhere user content can be removed.

### 4.1 Schema overview

```
users
  └── group_memberships ──┐
                          ├── groups
  └── posts ──────────────┤    └── group_invites
       └── reactions      │
       └── post_views     │
                          │
device_tokens (APNs)      │
notification_settings ────┘
```

### 4.2 SQL DDL (full)

```sql
-- ============================================================
-- ENUMS
-- ============================================================

CREATE TYPE auth_method AS ENUM ('phone', 'apple');
CREATE TYPE group_member_role AS ENUM ('admin', 'member');
CREATE TYPE invite_status AS ENUM ('pending', 'accepted', 'expired', 'revoked');
CREATE TYPE reaction_type AS ENUM (
  'heart', 'fire', 'laugh', 'wow', 'sad', 'thumbs_up'
);
CREATE TYPE moment_kind AS ENUM ('dual_photo'); -- v1.5 will add 'voice', 'text'
CREATE TYPE notification_kind AS ENUM (
  'new_post', 'memory_resurface', 'group_invite_accepted', 'reaction_received'
);

-- ============================================================
-- USERS — extends Supabase auth.users
-- ============================================================
CREATE TABLE public.users (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name    TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 40),
  phone_number    TEXT UNIQUE,                         -- E.164; null if Apple-only
  apple_user_id   TEXT UNIQUE,                         -- Apple's stable sub
  auth_method     auth_method NOT NULL,
  avatar_url      TEXT,                                -- supabase storage path
  high_school     TEXT,                                -- self-reported, free text
  grad_year       INTEGER CHECK (grad_year BETWEEN 2020 AND 2035),
  birthday        DATE,                                -- optional, used for age gate
  timezone        TEXT NOT NULL DEFAULT 'America/New_York',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ,
  -- Wellbeing / safety
  is_age_verified BOOLEAN NOT NULL DEFAULT FALSE,      -- 13+ self-attestation
  is_blocked      BOOLEAN NOT NULL DEFAULT FALSE       -- abuse / TOS
);

CREATE INDEX idx_users_phone ON public.users(phone_number) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_apple ON public.users(apple_user_id) WHERE deleted_at IS NULL;

-- ============================================================
-- GROUPS — the closed friend group
-- ============================================================
CREATE TABLE public.groups (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
  emoji           TEXT,                                -- optional group emoji icon
  created_by      UUID NOT NULL REFERENCES public.users(id),
  member_limit    INTEGER NOT NULL DEFAULT 25 CHECK (member_limit BETWEEN 5 AND 25),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_groups_created_by ON public.groups(created_by);

-- ============================================================
-- GROUP MEMBERSHIPS — many-to-many user <-> group
-- ============================================================
CREATE TABLE public.group_memberships (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role            group_member_role NOT NULL DEFAULT 'member',
  joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  left_at         TIMESTAMPTZ,                         -- null if still a member
  UNIQUE (group_id, user_id)
);

CREATE INDEX idx_memberships_group ON public.group_memberships(group_id) WHERE left_at IS NULL;
CREATE INDEX idx_memberships_user  ON public.group_memberships(user_id)  WHERE left_at IS NULL;

-- ============================================================
-- GROUP INVITES — short-lived invite links
-- ============================================================
CREATE TABLE public.group_invites (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  invite_code     TEXT NOT NULL UNIQUE,                -- 8-char shortcode, unguessable
  created_by      UUID NOT NULL REFERENCES public.users(id),
  max_uses        INTEGER,                             -- null = unlimited (within group cap)
  uses_count      INTEGER NOT NULL DEFAULT 0,
  expires_at      TIMESTAMPTZ NOT NULL,                -- default 7 days from create
  status          invite_status NOT NULL DEFAULT 'pending',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_invites_code ON public.group_invites(invite_code);

-- ============================================================
-- POSTS — a "moment" — in v1 always a dual-camera photo pair
-- ============================================================
CREATE TABLE public.posts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  author_id       UUID NOT NULL REFERENCES public.users(id),
  kind            moment_kind NOT NULL DEFAULT 'dual_photo',
  -- Dual photo storage
  front_image_path TEXT NOT NULL,                      -- e.g. "posts/{post_id}/front.webp"
  back_image_path  TEXT NOT NULL,
  caption          TEXT CHECK (char_length(caption) <= 140),
  -- Timing
  prompt_date     DATE NOT NULL,                       -- the calendar day this satisfies
  prompt_time     TIMESTAMPTZ NOT NULL,                -- when ConnectHS notified the user
  posted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  is_late         BOOLEAN NOT NULL DEFAULT FALSE,      -- TRUE if posted_at > prompt_time + 2h
  -- Lifecycle
  is_archived     BOOLEAN NOT NULL DEFAULT FALSE,      -- soft-archive (still visible in timeline)
  deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_posts_group_date  ON public.posts(group_id, prompt_date DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_posts_author      ON public.posts(author_id) WHERE deleted_at IS NULL;
-- Memory Engine "on this day" lookup
CREATE INDEX idx_posts_anniversary ON public.posts(group_id, EXTRACT(MONTH FROM prompt_date), EXTRACT(DAY FROM prompt_date)) WHERE deleted_at IS NULL;

-- One post per user per group per day (the BeReal-style daily cadence)
CREATE UNIQUE INDEX idx_posts_one_per_day_per_group
  ON public.posts(group_id, author_id, prompt_date)
  WHERE deleted_at IS NULL;

-- ============================================================
-- REACTIONS — emoji on a post
-- ============================================================
CREATE TABLE public.reactions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id         UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reaction        reaction_type NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (post_id, user_id, reaction)                  -- one of each emoji per user per post
);

CREATE INDEX idx_reactions_post ON public.reactions(post_id);

-- ============================================================
-- POST VIEWS — for "X people saw this" indicator
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
-- DEVICE TOKENS — for APNs
-- ============================================================
CREATE TABLE public.device_tokens (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  apns_token      TEXT NOT NULL,
  device_id       TEXT NOT NULL,                       -- vendor-id / ASIdentifierManager equiv
  app_version     TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, device_id)
);

CREATE INDEX idx_device_tokens_user ON public.device_tokens(user_id);

-- ============================================================
-- NOTIFICATION SETTINGS — per-user prefs
-- ============================================================
CREATE TABLE public.notification_settings (
  user_id              UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  daily_prompt_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  daily_prompt_window_start TIME NOT NULL DEFAULT '10:00',  -- earliest send
  daily_prompt_window_end   TIME NOT NULL DEFAULT '22:00',  -- latest send
  new_post_enabled     BOOLEAN NOT NULL DEFAULT TRUE,
  memory_enabled       BOOLEAN NOT NULL DEFAULT TRUE,
  reaction_enabled     BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- DAILY PROMPTS — server-issued randomized prompt time per group per day
-- ============================================================
CREATE TABLE public.daily_prompts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  prompt_date     DATE NOT NULL,
  prompt_time     TIMESTAMPTZ NOT NULL,                -- the moment we notified
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (group_id, prompt_date)
);

CREATE INDEX idx_daily_prompts_date ON public.daily_prompts(prompt_date);

-- ============================================================
-- ABUSE REPORTS — minimal v1 reporting surface
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
```

### 4.3 Row-Level Security (RLS) policies

**Every table has RLS enabled.** This is non-negotiable — closed-graph privacy is enforced at the DB layer.

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

-- Helper: is the auth user a current member of this group?
CREATE OR REPLACE FUNCTION public.is_group_member(gid UUID)
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.group_memberships
    WHERE group_id = gid AND user_id = auth.uid() AND left_at IS NULL
  );
$$;

-- USERS: can see self always; can see other users only if shared group
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

-- GROUPS: members only
CREATE POLICY groups_member_select ON public.groups FOR SELECT
  USING (public.is_group_member(id));

CREATE POLICY groups_creator_insert ON public.groups FOR INSERT
  WITH CHECK (created_by = auth.uid());

CREATE POLICY groups_admin_update ON public.groups FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM public.group_memberships
    WHERE group_id = public.groups.id AND user_id = auth.uid() AND role = 'admin' AND left_at IS NULL
  ));

-- GROUP_MEMBERSHIPS: members can see their group's roster
CREATE POLICY memberships_group_select ON public.group_memberships FOR SELECT
  USING (public.is_group_member(group_id));

-- POSTS: only group members can read; only members can insert their own posts
CREATE POLICY posts_member_select ON public.posts FOR SELECT
  USING (public.is_group_member(group_id) AND deleted_at IS NULL);

CREATE POLICY posts_self_insert ON public.posts FOR INSERT
  WITH CHECK (author_id = auth.uid() AND public.is_group_member(group_id));

CREATE POLICY posts_self_update ON public.posts FOR UPDATE
  USING (author_id = auth.uid());

-- REACTIONS: members of the post's group only
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

-- POST_VIEWS: write-only by self; readable by post author
CREATE POLICY views_self_insert ON public.post_views FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY views_author_select ON public.post_views FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.posts p WHERE p.id = post_id AND p.author_id = auth.uid()
  ));

-- DEVICE_TOKENS, NOTIFICATION_SETTINGS: self only
CREATE POLICY device_tokens_self ON public.device_tokens FOR ALL
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY notification_settings_self ON public.notification_settings FOR ALL
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
```

### 4.4 Storage bucket structure

```
posts/                      # private bucket; RLS-controlled signed URL access
  {post_id}/
    front.webp              # 1080x1080, ~70-100 KB
    back.webp               # 1080x1080, ~70-100 KB
    front_thumb.webp        # 256x256, for widget + archive grid (~15 KB)
    back_thumb.webp         # 256x256

avatars/                    # public bucket
  {user_id}.webp            # 256x256
```

Storage RLS:
- `posts/*` — signed URLs only; signing is gated by an Edge Function that checks group membership.
- `avatars/*` — public read; write only by self.

### 4.5 Image format & sizing

- Capture at full sensor resolution (whatever the device gives).
- Compress to **WebP** at quality 80, max edge 1080px.
- Generate 256x256 thumbnail server-side (Edge Function on upload trigger).
- Front camera image rendered at ~30% size, overlaid top-right of back camera image (BeReal layout) — but stored as **two separate images** so users can swap which is primary.

---

## 5. API contracts

ConnectHS uses **Supabase's auto-generated PostgREST API + custom RPC functions + Edge Functions for jobs**. The Swift SDK wraps PostgREST so most reads are typed table queries.

### 5.1 RPC functions (defined in SQL, called from client)

```sql
-- Create a new group and add the creator as admin in one transaction
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
  -- Caller must be member
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
RETURNS UUID                                            -- returns group_id
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

  -- Already a member? Just return.
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
) RETURNS BOOLEAN                                       -- TRUE if added, FALSE if removed
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

-- Get today's feed for a group (with reactions + view counts joined)
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
  reaction_summary JSONB                                -- { "heart": 3, "fire": 1, ... }
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
```

### 5.2 Edge Functions (TypeScript / Deno)

#### 5.2.1 `dispatch-daily-prompt`
- **Trigger:** `pg_cron` every 15 minutes, between 10:00 and 22:00 in each user's timezone window.
- **Logic:**
  1. For each active group, decide whether today's prompt has been sent (`daily_prompts` row exists for `prompt_date = today` & `group_id`).
  2. If not, pick a random time in the group's typical-active window (default 14:00-21:00 in the most common member timezone), insert into `daily_prompts`.
  3. Fan out APNs push to every member's `device_tokens`: title `"⏰ time to ConnectHS"`, body `"2 hours to share today's moment"`.
- **Idempotency:** UNIQUE(group_id, prompt_date) prevents double-dispatch.

#### 5.2.2 `memory-engine`
- **Trigger:** `pg_cron` daily at 09:00 user-local (per-timezone batch).
- **Logic:**
  1. For each user, for each of their groups, call `get_memories(group_id, today)`.
  2. If the result is non-empty, send a push: title `"📸 memory from {years_ago}yr ago"`, body sanitized caption / "you and {name}".
  3. Deep link into `connecths://memory/{post_id}`.

#### 5.2.3 `send-push`
- Generic APNs dispatcher (used by other functions).
- Reads `device_tokens` for target user, signs APNs JWT (using stored team key + key ID), POSTs to `api.push.apple.com`.
- On 410 Gone, deletes the token.

#### 5.2.4 `process-upload`
- **Trigger:** Supabase Storage `object_inserted` event on `posts/` bucket.
- **Logic:** Generate 256x256 thumbnails for `front.webp` / `back.webp` if not yet present.

#### 5.2.5 `widget-payload`
- **Trigger:** HTTP, called by the iOS widget timeline provider.
- **Logic:** Returns the latest `prompt_date` post per group the user is in, with a short-lived signed URL for the back image and a 256px thumbnail front-image inline as base64 (so widget can render without a second network hop).

---

## 6. Auth flow (F1)

### 6.1 Phone OTP flow

```
[Welcome screen]
  └─ "continue" → [enter phone]
                    └─ "send code" → Supabase auth.signInWithOtp({ phone })
                                       └─ [enter 6-digit code]
                                            └─ verify → [welcome to ConnectHS / profile setup]
```

- Country code defaults to +1 (U.S.); offer picker.
- After 5 failed attempts, lock for 15 min (Supabase default).
- Resend code button enabled after 30s.

### 6.2 Sign in with Apple flow

- Use Apple's native button (`SignInWithAppleButton` SwiftUI).
- Request `.fullName, .email` scopes.
- On success, call `auth.signInWithIdToken({ provider: 'apple', token, nonce })`.
- If first-time, populate `display_name` from Apple's `fullName.givenName`. User can rename in profile setup.
- Apple's "hide email" relay is fine — we don't email users in v1.

### 6.3 First-time profile setup

After auth, if `users.display_name` is null, push to setup:
- Display name (required, 1-40 chars; default to first name)
- Avatar (optional; tap to choose from photos or take a selfie)
- High school (optional, free text autocomplete via a static list — we ship a JSON of US high schools, ~24K entries, ~3MB; lazily loaded)
- Grad year (optional, picker 2020-2035)
- Birthday (optional but recommended; used for age gate — must be 13+)
- Age attestation: required checkbox "I am 13 or older"

### 6.4 Auth states (client)

- `unauthenticated` — show welcome
- `authenticating` — OTP/Apple in progress
- `profileIncomplete` — auth'd but no display_name
- `noGroup` — auth'd, profile complete, no group memberships → onboarding to create or join
- `active` — has at least one group membership → main app

---

## 7. Screen-by-screen UX spec

This section walks every v1 screen. Each screen has: purpose, inputs, outputs, key states, and acceptance criteria.

### 7.1 Welcome / sign-up

**Purpose:** Convert a new download to an authenticated user in <30 seconds.

**Layout:**
- Full-bleed soft-gradient background (warm cream → soft peach, lower-case typography, anti-corporate per Locket aesthetic guidance).
- Logo + word-mark `connecths` (lowercase) centered.
- Tagline: `"the place your high school friends actually still live"`
- Two buttons stacked:
  - `Continue with Apple` (Apple Sign-In black/white per HIG)
  - `Continue with phone` (secondary outline button)
- Footer micro-copy: small `"by continuing you agree to our [terms] and [privacy]"`. Tap-targets open in-app SafariView.

**Acceptance:**
- [ ] Apple button uses HIG-compliant `SignInWithAppleButton`.
- [ ] Phone button leads to phone entry, country code defaulting to user locale.
- [ ] No way to enter the app without auth.

### 7.2 Onboarding — no group state

**Purpose:** Get the user into a group within 60 seconds.

**Two paths:**
1. **"join a group"** — paste invite code or open via universal link (`https://connecths.app/i/{code}`)
2. **"start a new group"** — create flow

**Create flow:**
- Step 1: Group name (e.g. `"the boys"`), 1-60 chars
- Step 2: Optional emoji picker
- Step 3: Generated invite link with native share sheet pre-loaded with copy:
  > "starting a connecths so we don't all become strangers. join: https://connecths.app/i/{code}"
- "skip for now" available — user lands in empty-state app.

**Acceptance:**
- [ ] Universal link `https://connecths.app/i/{code}` opens app and triggers redeem on auth.
- [ ] If the user redeems while unauthenticated, redirect through auth, then redeem on completion.
- [ ] Group full (25 members) shows an error and doesn't redeem.

### 7.3 Home / today's feed

**Purpose:** The primary screen. Shows today's moments from the active group.

**Layout (top-to-bottom):**
- Top bar: Group selector (tap → bottom sheet listing groups; v1 = single group, but the picker exists). Right side: profile/settings icon.
- **Memory ribbon** (if any): horizontally scrolling card of past-year moments for today (`"1 year ago today"`). Tap → memory detail.
- **Today's grid:** posts from members for `today's prompt_date`. Each post is a tappable square showing the back image with a small front-image overlay. Author avatar + first name beneath.
- **CTA tile:** if the current user hasn't posted today, a prominent `"share today's moment"` tile that taps into camera. If they have, the tile shows their post.

**States:**
- `loading` — skeleton grid
- `empty` (no friends posted yet today) — copy: `"no moments yet today. be first."`
- `hasPosts`
- `error` — retry button

**Acceptance:**
- [ ] Pull-to-refresh re-fetches `get_feed`.
- [ ] Realtime: when a new post is inserted, it animates in without manual refresh.
- [ ] Tapping a post opens detail view.
- [ ] If user hasn't posted today, the camera CTA is visually dominant (no scrolling required).

### 7.4 Camera / capture

**Purpose:** Capture and post a dual-camera moment in <10 seconds.

**Layout:**
- Full-bleed back-camera live preview.
- Front-camera live preview as a small (~120pt) draggable inset, default top-right (BeReal convention). User can long-press and drag to reposition.
- Center-bottom: large round shutter button.
- Top-left: close (X). Top-right: flip primary camera (swap which is "main").

**Capture flow:**
1. User taps shutter.
2. AVFoundation `AVCaptureMultiCamSession` snaps both cameras simultaneously (within <100ms of each other; iOS guarantees synchronized capture).
3. Brief preview: both images shown stacked. Caption field (optional, 140 chars). Two buttons: "post" / "retake".
4. On "post":
   - Upload both images to Supabase Storage at `posts/{tempId}/front.webp` and `back.webp`.
   - Insert posts row.
   - Show success toast `"posted 🎉"` and return to feed.
5. If post fails (network), keep image in local cache and show retry button on feed.

**Acceptance:**
- [ ] Dual-camera capture works on iPhone XS / iPhone XR or newer (devices supporting `AVCaptureMultiCamSession`). Older devices: graceful fallback to sequential capture (back, then front, ≤500ms).
- [ ] Camera permission denied → friendly screen with "open settings" deep link.
- [ ] Upload uses background URLSession so backgrounding the app doesn't kill the upload.
- [ ] Front-camera inset position is persisted across the session.

### 7.5 Post detail

**Purpose:** Full-screen view of one moment, with reactions + viewers.

**Layout:**
- Full-screen back image.
- Front image inset top-right (or wherever poster placed it).
- Bottom sheet with: author name + avatar + posted time, caption, reaction bar (6 emojis: ❤️ 🔥 😂 😮 😢 👍), tap to toggle.
- Below reactions: `"viewed by 7 of 12"` (only visible to author). On tap: list of viewers.
- Swipe up: next post in today's feed. Swipe down: dismiss.
- On open, call `mark_viewed` RPC.

**Acceptance:**
- [ ] Reaction taps are optimistic (instant UI update, server sync on background).
- [ ] Long-press an emoji in the bar to see who reacted with it.
- [ ] Caption is selectable (long-press copy).
- [ ] Swipe gestures don't conflict with horizontal pan (use SwiftUI's `gesture(.simultaneously)`).

### 7.6 Archive — permanent timeline

**Purpose:** Browse every moment ever posted in the group.

**Layout:**
- Top: month / year picker (large vertical scroll, like Apple Photos "Years" view).
- Body: chronological grid of posts grouped by month. Square thumbnails (back image), tap → post detail.
- Filter chip: `"only my posts"` toggle.

**States:**
- `loading` (paginated, 30-day chunks)
- `hasContent`
- `empty` (new group, <1 week old) — copy: `"your archive will fill up. promise."`

**Acceptance:**
- [ ] Infinite scroll with 30-day windows.
- [ ] Scroll-to-date is performant on 1000+ posts (use `LazyVGrid`).
- [ ] Year/month headers stick on scroll.
- [ ] Posts deleted by author show as a `"removed"` placeholder rather than vanishing (preserves timeline integrity).

### 7.7 Memory detail

**Purpose:** Show "on this day, X years ago" content in a beautiful, share-able layout.

**Layout:**
- Hero: full-screen image carousel of past moments for today's date.
- Title: `"X year(s) ago today"`
- Subtitle: `"{author_name} in {group_name}"`
- Bottom: native share sheet button → exports a 1080x1920 image with branded watermark for IG Stories.

**Acceptance:**
- [ ] Carousel snap-scrolls between memories, oldest → most recent.
- [ ] Share sheet pre-loads with a generated image (caption-overlaid).
- [ ] If the user shares to IG Stories, the deep-link is `https://connecths.app` (no invite code, just brand drive).

### 7.8 Group settings

**Purpose:** Manage members, leave, change group name/emoji.

**Sections:**
- Group name + emoji (admin-editable)
- Members list (tap on member → kebab menu: remove (admin only), report)
- Invite link: button to generate / copy / share
- Danger zone: leave group (with confirmation)

**Acceptance:**
- [ ] Leaving group sets `left_at = NOW()` rather than deleting the row (preserves post authorship).
- [ ] Removed user receives a silent push: `"you were removed from {group}"` and is locally signed out of that group's data.
- [ ] Last-admin protection: can't leave if you're the only admin and there are other members; must promote first.

### 7.9 Profile / settings

**Purpose:** Account-level settings.

**Sections:**
- Avatar + display name (editable)
- High school + grad year (editable)
- Notification preferences:
  - Daily prompt: on/off + window picker (10:00-22:00 default)
  - New posts from friends: on/off
  - Memory engine: on/off
  - Reactions: on/off
- Privacy: blocked users, request data export, delete account
- About: terms, privacy policy, app version, "made with care by Alexander"
- Sign out

**Acceptance:**
- [ ] Delete account triggers a confirmation flow with 24-hour grace period (soft delete).
- [ ] Data export emails a JSON dump (GDPR/CCPA-friendly, even though not strictly required for U.S.).
- [ ] All settings persist in `notification_settings` and sync to Edge Functions for push targeting.

### 7.10 Empty / error states (universal)

| State | Copy | CTA |
|---|---|---|
| No internet | `"no signal. we'll wait."` | retry |
| Server error (500) | `"something broke. it's our fault."` | retry |
| Group full | `"this group is full (25 max). ask the admin."` | back |
| Invite expired | `"this invite expired. ask for a new one."` | back |
| Camera denied | `"connecths needs the camera to do its thing"` | open settings |
| Notifications denied | `"turn on notifications so you don't miss the daily moment"` | open settings (offered once at onboarding, never nagged again) |

---

## 8. Widget spec (F6)

### 8.1 Widget sizes

- **Small (155x155)** — single most recent post (back image) with a tiny front-image inset.
- **Medium (329x155)** — same content but room for author name + posted time.

(Large widget deferred to v1.5 — gallery of last 4 posts.)

### 8.2 Provider behavior

- `IntentTimelineProvider` with a refresh policy of every 30 minutes.
- Real-time updates via `WidgetCenter.shared.reloadAllTimelines()` triggered by:
  - App receiving a Supabase Realtime event for new post in any of the user's groups
  - Background fetch (system-decided)
- App Group container shares: latest post `id`, author name, base64 thumb of back image (fits in widget memory budget), front image thumb, posted time.

### 8.3 Widget UI

- Background: blurred low-resolution version of back image
- Foreground: full back image, 8pt corner radius, with front-image inset
- Bottom overlay (medium only): author first name + relative time (`"alex · 2h"`)
- Tap behavior: deep link to `connecths://post/{post_id}` → opens app to post detail.

### 8.4 Acceptance

- [ ] Widget renders within 1.5s of being added to home screen.
- [ ] Updates within ~5 minutes of a new post (system-policy permitting).
- [ ] No images >50KB in widget memory (use 256px thumbnail, not full image).
- [ ] Lock-screen widget (small): same single-post layout.
- [ ] StandBy mode: full-screen latest post (iOS 17+ feature).

---

## 9. Push notification spec

### 9.1 Notification types

| Kind | Title | Body | Deep link |
|---|---|---|---|
| daily_prompt | `⏰ time to connecths` | `2 hours to share today's moment` | `connecths://camera` |
| new_post | `{author} just posted` | optional caption preview | `connecths://post/{post_id}` |
| memory_resurface | `📸 memory from {n}yr ago` | `you and {name} on this day` | `connecths://memory/{post_id}` |
| reaction_received | `{name} reacted {emoji} to your moment` | (none) | `connecths://post/{post_id}` |
| group_invite_accepted | `{name} joined {group}` | (none) | `connecths://group/{group_id}` |

### 9.2 Delivery rules

- Bundle: notifications for the same group within 5 min collapse via `thread-id`.
- Quiet hours: respect user's `notification_settings.daily_prompt_window_*`. New post / reaction respects 22:00-08:00 quiet hours by default unless user opts in.
- Critical: never spam. Maximum 5 push notifications per user per day across all groups.

### 9.3 Acceptance

- [ ] APNs token is registered on app foreground and on `didRegisterForRemoteNotifications`.
- [ ] Token rotation handled (token can change; always upsert to `device_tokens`).
- [ ] Tapping a push opens the correct deep-link target, even from cold start.

---

## 10. Onboarding & cold-start mechanics

### 10.1 First-run experience

```
Download
  → Welcome screen
  → Auth (phone or Apple)
  → Profile setup (name, optional avatar)
  → Group choice:
      ├── "join a group" (invite code or pasted link)
      └── "start a new group" → name → emoji → share invite link
  → Empty home feed with prominent "share your first moment" CTA
  → Permission prompts (camera, then notifications) — at point of first use, not upfront
```

### 10.2 Group invite UX

- Universal Links via `apple-app-site-association` on `connecths.app/.well-known/`.
- Invite URL: `https://connecths.app/i/{code}`
- Web fallback page: minimal landing with App Store badge + "open in app" deep link.
- After auth, `redeem_invite(code)` is called automatically; user lands directly in the joined group.

### 10.3 Single-user fallback (cold-start)

If a user signs up and their friends haven't yet joined:
- Empty feed shows: large `"share a moment anyway — your friends will see it when they join"` card.
- After posting, the post is visible only to the poster + future joiners (no special mechanic; default behavior).
- After 48h with no other members, push: `"still alone in your group. tap to invite."`

---

## 11. Build order & milestones

Aligned with Alexander's June 16, 2026 birthday + Apple Developer enrollment, working backward from a public launch in the June-August 2026 graduation window.

### 11.1 Phases

| Phase | Window | Deliverable |
|---|---|---|
| **P0 — Foundation** | Now → Feb 28, 2026 | Repo set up; Supabase project; auth flows working end-to-end; core data model; CI green |
| **P1 — Capture & Feed** | Mar 1 → Apr 15, 2026 | Dual-camera capture; today's feed; reactions; archive; basic widget |
| **P2 — Memory & Polish** | Apr 16 → May 31, 2026 | Memory Engine; push notifications; full settings; design polish; dogfood with own friend group |
| **P3 — Apple enrollment + TestFlight** | June 16-30, 2026 | Apple Developer enrollment day-of birthday; TestFlight beta with 5-10 HS friend groups (~50 users) |
| **P4 — Public launch** | July 1-31, 2026 | App Store release; TikTok-native launch; senior-class IG seeding; ride graduation window |
| **P5 — Iterate** | Aug 1, 2026 onward | Use real retention data to drive next feature priorities (voice notes, multiple groups, etc.) |

### 11.2 Two-week sprint plan (P0)

**Sprint 1 (Dec 9 - Dec 22, 2025):**
- Repo scaffolding (Xcode workspace, SwiftUI app, widget extension target)
- Supabase project; run all migrations; verify RLS with test users
- Phone OTP flow end-to-end on a TestFlight-equivalent (free dev provisioning)
- Sign in with Apple flow

**Sprint 2 (Dec 23, 2025 - Jan 5, 2026):**
- User profile setup screen
- App routing / state machine
- HS list autocomplete data (download U.S. NCES list)
- Settings screen scaffold

**Sprint 3 (Jan 6 - Jan 19, 2026):**
- Group creation, invite codes, redeem flow
- Universal Links setup
- Group settings screen

**Sprint 4 (Jan 20 - Feb 2, 2026):**
- Today's feed (read path) with realtime subscription
- Group switcher
- Empty / loading / error states

**Sprint 5 (Feb 3 - Feb 16, 2026):**
- Camera capture (dual-camera pipeline)
- Compression, upload, storage
- Post creation + insertion

**Sprint 6 (Feb 17 - Feb 28, 2026):**
- Reactions, post views, post detail screen
- Archive screen
- Bug bash + dogfood internally

### 11.3 Out-of-scope sprints (P1+)

P1-P3 sprint plans get written when P0 lands.

---

## 12. Quality bar

### 12.1 Performance targets

- Cold launch to first paint: <1.5s on iPhone 12 or newer
- Feed initial load: <500ms (with cache); <2s (cold)
- Widget render: <1.5s
- Camera shutter to capture confirmation: <300ms
- Photo upload: <3s on LTE for 1080p compressed pair

### 12.2 Reliability

- Crash-free sessions: ≥99.5%
- Sentry alerts wired to Discord/email for any new crash group
- All network requests retried with exponential backoff (3 attempts)
- All Supabase calls have a 10s timeout

### 12.3 Accessibility

- VoiceOver labels on every interactive element
- Dynamic type supported up to xxxLarge
- Min tap target: 44x44pt (HIG)
- Color contrast: WCAG AA (4.5:1 for body, 3:1 for large text)
- Camera flow: VoiceOver describes the front/back preview state

### 12.4 Code quality

- SwiftLint with strict rules; CI fails on violations
- All public APIs documented (DocC)
- No force unwraps in production code (lint-enforced)
- Test coverage: ≥60% on Models + Services layers
- UI tests for the 5 critical flows: auth, group create, group join, post, react

---

## 13. Privacy, safety, legal

### 13.1 Age gate

- Minimum age: 13 (COPPA compliance).
- Self-attestation via checkbox at profile setup.
- If birthday is provided, server validates `birthday <= today - 13 years`.
- Apple Sign-In does not provide age; rely on self-attestation.

### 13.2 Reporting & blocking

- Long-press on a post → "report"
- Long-press on a member → "block" / "report"
- Blocked users: cannot see each other's posts in any shared group; do not get push for each other's posts.
- Reports route to `reports` table; moderation queue is a Supabase Studio view (manual review by Alexander in v1).

### 13.3 Data retention

- Soft delete: 30-day grace period; user can restore via support.
- Hard delete: 30 days after soft-delete, removes all rows + storage objects.
- Data export: JSON ZIP via Edge Function; emailed to verified address.

### 13.4 ToS / Privacy

- ToS includes: closed-graph design, no public sharing, photo ownership stays with user (license to display only within group).
- Privacy policy: data flows, third parties (Supabase, Apple, Twilio, Sentry, PostHog), retention, user rights.
- **Important:** explicitly state we do not sell data, do not show ads, and do not train AI on user content.

### 13.5 Apple App Store readiness checklist

- [ ] App privacy nutrition labels accurate (Photos, Contacts NOT used, Phone Number, Notifications)
- [ ] In-app account deletion (Apple Guideline 5.1.1(v) — required since 2022)
- [ ] Sign in with Apple offered alongside any third-party SSO (we offer phone, so Apple is required)
- [ ] No private API usage
- [ ] Adult-content rating: 12+ (infrequent/mild user-generated content; closed graph mitigates)
- [ ] App Tracking Transparency: not needed (no third-party tracking)

---

## 14. Open questions / decisions deferred

These need answers before P1 ends but don't block P0:

1. **Domain** — register `connecths.app` (~$15/yr Cloudflare). Confirm trademark conflict-free.
2. **Branding** — final logo, color palette, typography. Recommend hiring a designer or using Figma Community templates with custom polish; budget ~$500-2000 if hiring.
3. **Demo data for App Store screenshots** — manufactured friend group "the cdot crew" with 5 fake users; build a script to seed.
4. **Launch geography** — U.S. only at launch, or worldwide English? Recommend U.S. only for v1 to control Twilio costs and regulatory surface.
5. **App Store Connect entity** — sole proprietor under Alexander's name post-18, or LLC? Discuss with a lawyer/CPA before App Store submission. Filing a Delaware C-Corp early is fundraise-friendly (recommended if any seed conversations are happening).

---

## 15. Appendices

### Appendix A — Reaction emoji set (locked for v1)

```
❤️  heart       — "I love this"
🔥  fire        — "this is fire"
😂  laugh       — "lol"
😮  wow         — "omg"
😢  sad         — "miss u"
👍  thumbs_up   — generic ack
```

### Appendix B — Color palette (suggested; final TBD)

- `cream`         #FBF7F0 — primary background
- `peach`         #F5C8A8 — accent gradient
- `ink`           #1A1A1A — primary text
- `ink-soft`      #4A4A4A — secondary text
- `tether`        #E5734D — brand accent (warm coral)
- `success`       #6DA77F
- `warning`       #E0A33D
- `error`         #C45656

### Appendix C — Typography (suggested; iOS native)

- Body: SF Pro (iOS default), regular 17pt
- Headlines: SF Pro Rounded, semibold (anti-corporate, friendly)
- Display / brand: a wordmark in a rounded geometric (commission or use Inter / Manrope free for word-mark)

### Appendix D — Naming pattern for files & types

- Models: `User`, `Group`, `Post`, `Reaction`, `Memory`
- Views: `{Screen}View.swift` (e.g. `FeedView.swift`, `CameraView.swift`)
- View models: `{Screen}ViewModel.swift`
- Services: `{Concern}Service.swift` (`AuthService`, `PostService`, `WidgetService`)
- Edge Functions: `kebab-case` directories under `supabase/functions/`

### Appendix E — Universal Link config (`apple-app-site-association`)

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["TEAMID.com.connecths.app"],
        "components": [
          { "/": "/i/*", "comment": "Group invite" },
          { "/": "/p/*", "comment": "Public memory share (deferred)" }
        ]
      }
    ]
  }
}
```

### Appendix F — Push notification payload examples

New post:
```json
{
  "aps": {
    "alert": { "title": "alex just posted", "body": "morning at the diner" },
    "thread-id": "group-{group_id}",
    "sound": "default"
  },
  "deep_link": "connecths://post/{post_id}"
}
```

Memory resurface:
```json
{
  "aps": {
    "alert": { "title": "📸 memory from 1yr ago", "body": "you and sarah on this day" },
    "thread-id": "memory-{group_id}",
    "sound": "default"
  },
  "deep_link": "connecths://memory/{post_id}"
}
```

---

## 16. Definition of Done (v1)

ConnectHS v1 ships when **all** of the following are true:

- [ ] Both auth methods work end-to-end on a fresh device install
- [ ] A user can create a group, share an invite, and have a friend redeem it (universal link path)
- [ ] Both users can post a dual-camera moment, and each sees the other's
- [ ] Reactions work bidirectionally, with optimistic UI
- [ ] Archive shows posts from at least 30 days ago in correct chronological order
- [ ] Widget appears, shows the latest moment, and updates within 5 min of a new post
- [ ] At least one memory has been generated and pushed (test by manually inserting a post with a `prompt_date` of one year ago)
- [ ] Push notifications work for: daily_prompt, new_post, memory_resurface, reaction_received
- [ ] All RLS policies tested with two-user scenarios; no cross-group leakage
- [ ] Crash-free rate ≥99.5% over 7 days of TestFlight
- [ ] App Store reviewer sandbox account works and has demo content

---

**End of PRD v1.0.**

Build it.
