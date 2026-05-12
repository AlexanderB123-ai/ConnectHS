# ConnectHS — iOS app

A closed-group iOS app that helps high school friends stay connected after graduation.

## Quickstart for Claude Code

```bash
# 1. Open this folder in Terminal
cd ~/Developer/connecths-ios

# 2. Launch Claude Code
claude

# 3. First mission
> Read CLAUDE.md and spec/00-overview.md, then spec/01-architecture.md.
> Confirm you understand the project.
> List the 8 v1 features and recommend which to build first.
```

## Repo layout

```
connecths-ios/
├── CLAUDE.md           ← agent rules (READ FIRST every session)
├── README.md           ← this file
├── decisions.md        ← architecture decision log (append-only)
├── .aiexclude          ← blocks .env, secrets/ from agent context
├── docs/
│   └── PRD.md          ← full product reference (read-only)
├── spec/               ← per-feature briefs (one feature = one file)
│   ├── 00-overview.md
│   ├── 01-architecture.md
│   ├── 02-data-model.md
│   ├── 03-auth.md
│   ├── 04-groups.md
│   ├── 05-camera-feed.md
│   ├── 06-memory-engine.md
│   ├── 07-widget.md
│   └── 08-notifications.md
├── ConnectHS/          ← iOS app (Xcode-managed)
├── ConnectHSWidget/    ← widget extension
├── Shared/             ← App Group shared code
├── ConnectHSTests/
├── ConnectHSUITests/
└── supabase/
    ├── migrations/     ← versioned SQL
    └── functions/      ← Edge Functions
```

## Sprint workflow

1. Pick ONE feature spec (e.g. `spec/03-auth.md`)
2. Tell Claude Code: `Read CLAUDE.md and spec/03-auth.md. Produce an implementation plan. Don't write code yet.`
3. Review the plan, comment, approve
4. `Implement the plan. Build and run tests after each major change.`
5. When done, append a one-line entry to `decisions.md`
6. Commit, move to next spec

## Build commands

```bash
# Build
xcodebuild -scheme ConnectHS -destination 'platform=iOS Simulator,name=iPhone 15' build

# Test
xcodebuild -scheme ConnectHS -destination 'platform=iOS Simulator,name=iPhone 15' test

# Lint
swiftlint
```

## Tech stack

- **iOS:** Swift 6, SwiftUI, iOS 17+, AVFoundation, WidgetKit
- **Backend:** Supabase (Postgres + Auth + Storage + Realtime + Edge Functions)
- **Auth:** Phone OTP (Twilio) + Sign in with Apple
- **Camera:** `AVCaptureMultiCamSession` for true dual-camera
- **Push:** APNs via Supabase Edge Functions

## Key milestones

| Date | Milestone |
|------|-----------|
| Now → Feb 28, 2026 | Foundation: auth + data model + repo |
| Mar 1 → Apr 15, 2026 | Capture + feed + reactions + archive + widget |
| Apr 16 → May 31, 2026 | Memory Engine + push + dogfood |
| Jun 16, 2026 | Apple Developer enrollment (Alexander's 18th birthday) |
| Jun 17–30, 2026 | TestFlight beta with 5–10 HS friend groups |
| Jul 2026 | Public App Store launch |
