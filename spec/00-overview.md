# 00 — ConnectHS Overview

**Read this first** before any feature work.

## What ConnectHS is

A closed iOS app where a high school friend group (5–25 people, phone-verified) shares a daily dual-camera "moment" — and keeps every moment forever, surfacing them as shared memories — so the friendships survive college.

## One-line pitch
*"The place your high school friends actually still live — after."*

## Target user

- **Primary:** High school seniors (Class of 2026), ages 17–18, U.S., heading to college fall 2026
- **Secondary:** College freshmen/sophomores still maintaining HS friendships (18–20)
- **Critical adoption window:** June 1 – August 31, 2026

## Core problem

After high school, friend groups scatter geographically. Group chats die within ~3 months. No existing app (Snapchat, Instagram, BeReal, Locket, Marco Polo) is purpose-built for the small, durable, graduating-class-cohort use case.

## Product wedge — what makes ConnectHS different

A BeReal-style daily dual-camera prompt for a closed friend group, but with:
1. **Permanent archive** (BeReal deletes after 24h — we keep forever)
2. **Memory Engine** that resurfaces shared past moments ("1 year ago today")
3. **Closed graphs only** — no public feed, no discovery, no follower counts
4. **No streaks-as-pressure** — habit comes from the memory layer, not anxiety

## v1 (MVP) feature scope — exactly 8 features

| # | Feature | Spec file |
|---|---------|-----------|
| F1 | Auth (phone OTP + Sign in with Apple) | `02-auth.md` |
| F2 | Closed friend group (5–25 people, phone-verified, invite-by-link) | `04-groups.md` |
| F3 | Daily dual-camera moment (front + back simultaneous) | `05-camera-feed.md` |
| F4 | Permanent archive (browsable timeline of every moment) | `05-camera-feed.md` |
| F5 | Memory Engine (daily resurfacing of "X year ago today") | `06-memory-engine.md` |
| F6 | Home-screen widget (latest moment, tap-to-open) | `07-widget.md` |
| F7 | Async reactions (emoji-only) | `05-camera-feed.md` |
| F8 | Push notifications | `08-notifications.md` |

## Out-of-scope (explicit anti-features for v1)

- Voice notes, text status, multiple groups per user → v1.5+
- Async voice/video replies, calendar features → v2
- Premium subscription, location sharing → v2+
- Android version → only after iOS PMF
- Filters, AR, stickers, sounds → never v1
- Public feed, follower counts, discovery → never (anti-brand)
- DMs / chat → never v1 (group chat death is the problem we're fighting)

## Success metrics (the bar)

| Metric | Target |
|--------|--------|
| W1 retention | ≥ 50% |
| W4 retention | ≥ 30% |
| DAU/MAU by month 6 | ≥ 0.3 |
| Sign-up → first post | < 60 seconds |
| Avg group size at activation | 8–12 |
| Crash-free sessions | ≥ 99.5% |

## Brand & design tone

- Warm, lowercase, anti-corporate (Locket-aesthetic)
- Soft gradients (cream → peach), rounded geometry
- Friendly micro-copy: `"no signal. we'll wait."` not `"Network Error"`
- No corporate UI patterns (no sidebar nav, no card shadows, no Material Design)

## Color palette

- `cream` `#FBF7F0` — primary background
- `peach` `#F5C8A8` — accent gradient
- `ink` `#1A1A1A` — primary text
- `ink-soft` `#4A4A4A` — secondary text
- `tether` `#E5734D` — brand accent (warm coral)
- `success` `#6DA77F`
- `warning` `#E0A33D`
- `error` `#C45656`

## Build timeline (high-level)

| Phase | Window | Deliverable |
|-------|--------|-------------|
| P0 — Foundation | now → Feb 28, 2026 | Auth + data model + repo set up |
| P1 — Capture & Feed | Mar 1 – Apr 15, 2026 | Dual-camera + feed + reactions + archive + widget |
| P2 — Memory & Polish | Apr 16 – May 31, 2026 | Memory Engine + push + dogfood |
| P3 — Apple enrollment + TestFlight | Jun 16–30, 2026 | Apple Developer Program enrolls on Alexander's 18th birthday; TestFlight beta |
| P4 — Public launch | Jul 1–31, 2026 | App Store release; ride graduation window |

The launch is timed to the U.S. high school graduation window (June–August). Missing it = losing 12 months of momentum.
