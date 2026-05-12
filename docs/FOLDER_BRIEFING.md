# ConnectHS — Folder Briefing (post-cleanup)

Generated: 2026-05-06. Paste this back to Claude chat for a fresh session to pick up where we left off.

---

## Where the project lives on this Mac

`~/Downloads/Folders/Code/ConnectHSFolder/`

The README's quickstart assumes the project lives at `~/Developer/connecths-ios/`. The current location works fine, but if you want to match the README exactly:

```bash
mkdir -p ~/Developer
mv ~/Downloads/Folders/Code/ConnectHSFolder ~/Developer/connecths-ios
```

Git remote is already set to `git@github.com:AlexanderB123-ai/ConnectHS.git`.

---

## Final folder structure

```
ConnectHSFolder/                       (or connecths-ios/ if you rename)
├── .aiexclude                         agent secret-blocking rules (584 B)
├── .gitignore                         NEW — Swift/Xcode + secrets ignore (1065 B)
├── .git/                              git repo, remote = AlexanderB123-ai/ConnectHS
├── CLAUDE.md                          agent instructions (8196 B) — READ FIRST every session
├── README.md                          project README (2917 B) — was a stub, now correct
├── decisions.md                       architecture decision log, append-only (2677 B)
├── docs/
│   └── PRD.md                         full product reference, read-only (59071 B)
├── spec/                              per-feature briefs
│   ├── 00-overview.md
│   ├── 01-architecture.md
│   ├── 02-data-model.md
│   ├── 03-auth.md
│   ├── 04-groups.md
│   ├── 05-camera-feed.md
│   ├── 06-memory-engine.md
│   ├── 07-widget.md
│   └── 08-notifications.md
├── ConnectHS/                         iOS app (Xcode-managed)
│   ├── ConnectHS.xcodeproj/
│   │   ├── project.pbxproj
│   │   └── project.xcworkspace/
│   ├── ConnectHS/                     SOURCE — canonical, target of Xcode project
│   │   ├── ConnectHSApp.swift         @main App struct
│   │   ├── ContentView.swift          (Xcode template stub — likely dead code)
│   │   ├── Assets.xcassets/
│   │   ├── App/
│   │   │   ├── MainTabView.swift
│   │   │   └── RootView.swift
│   │   ├── Features/
│   │   │   ├── Archive/
│   │   │   ├── Auth/
│   │   │   ├── Camera/                (newest, includes DualCameraSession + Sequential fallback)
│   │   │   ├── Feed/
│   │   │   ├── Group/
│   │   │   ├── Memory/
│   │   │   └── Profile/
│   │   ├── Models/                    Codable structs matching Supabase tables
│   │   ├── Services/                  SupabaseClient, AuthService, GroupService, PostService, ImagePipeline
│   │   └── Shared/                    design tokens, reusable views
│   ├── ConnectHSTests/                NEW location (was at root, empty)
│   └── ConnectHSUITests/              NEW location (was at root, empty)
├── ConnectHSWidget/                   widget extension target (currently empty — not yet implemented)
├── Shared/                            App Group shared code (currently empty — not yet implemented)
├── supabase/
│   ├── config.toml
│   ├── .gitignore
│   ├── functions/                     Edge Functions (empty)
│   ├── migrations/
│   │   ├── 20260505000000_initial_schema.sql
│   │   └── 20260506000000_posts_storage_and_rpc.sql
│   └── .temp/                         CLI cache, ignored by git
└── _archived/                         CLEANUP HOLDING — review and rm -rf when ready
    ├── ConnectHSBuild/                old orphan source tree (mirrored into ConnectHS/ConnectHS/ on May 6)
    ├── ConnectHSTests-old-empty/      empty stub from wrong location
    ├── ConnectHSUITests-old-empty/    empty stub from wrong location
    ├── connecths-spec-bundle-root/    original unzip — duplicate of root files
    ├── connecths-spec-bundle-nested-in-spec/  duplicate that ended up nested in spec/
    └── connecths-spec.zip             original archive
```

---

## What was changed

1. **Replaced `README.md`** — was a 12-byte stub (`# ConnectHS`), now the proper 2917-byte README from the spec bundle.
2. **Moved `ConnectHSTests/` and `ConnectHSUITests/`** from root → inside `ConnectHS/` (they were empty stubs in the wrong place).
3. **Archived `ConnectHSBuild/`** — older orphan source tree. Confirmed `ConnectHS/ConnectHS/` has the canonical newer versions: `FeedView.swift` uses real `CameraView` w/ `fullScreenCover` (vs old `CameraPlaceholderView`); `PostService.swift` is 91 lines with `uploadMoment` + `signedURL` (vs old 45-line stub).
4. **Archived spec-bundle leftovers**: `connecths-spec-bundle/` (root), `spec/connecths-spec-bundle/` (nested duplicate), `connecths-spec.zip`.
5. **Created `.gitignore`** — Swift/Xcode standard + secrets + `_archived/`. None previously existed.

Nothing was permanently deleted. Everything questionable lives in `_archived/`. Review then:

```bash
cd ~/Downloads/Folders/Code/ConnectHSFolder    # or wherever you moved it
rm -rf _archived
```

---

## Still to do

- **`rm -rf _archived/`** once you've verified nothing important is in there.
- **`ConnectHSWidget/` and `Shared/`** are empty — they exist as placeholders for the widget extension target and App Group shared code. Spec `07-widget.md` covers what goes here.
- **`.CLAUDE.md.swp`** — orphan vim swap file at root. Safe to delete (`rm .CLAUDE.md.swp`).
- **`.DS_Store`** is currently tracked by git (`AM .DS_Store` in status). After the new `.gitignore`, run `git rm --cached .DS_Store` to untrack it.
- **`ContentView.swift`** at `ConnectHS/ConnectHS/ContentView.swift` is a 391-byte Xcode template stub. If `RootView` is doing the routing, this is dead code — confirm and delete.
- **`ConnectHSApp.swift` location** — currently at `ConnectHS/ConnectHS/ConnectHSApp.swift` (top level). Your CLAUDE.md says it should live in `App/`. Cosmetic; up to you.
- **Xcode target membership** — per `decisions.md`, the source folders under `ConnectHS/ConnectHS/` need to be manually added to the Xcode target. Verify in Xcode that all `Features/`, `Models/`, `Services/`, `Shared/`, and `App/` files are members of the `ConnectHS` target.

---

## Project state at a glance (from decisions.md)

- 2026-05-05 — Initial Supabase schema deployed (11 tables, enums, RLS, RPCs)
- 2026-05-05 — iOS project scaffolded (folder structure, models, services, auth views, group onboarding, feed/archive/profile placeholders, root auth router)
- 2026-05-06 — Mirrored `ConnectHSBuild` source into `ConnectHS/ConnectHS/`
- 2026-05-06 — Image format chosen: JPEG q0.8 max-1080px (no WebP — iOS lacks native encoder)
- 2026-05-06 — F3 background upload deferred (supabase-swift Storage + URLSession.background incompatible)
- 2026-05-06 — F3 storage migration applied: `posts` bucket + RLS + `create_post` RPC
- 2026-05-06 — Multi-cam fallback: A12+ uses `AVCaptureMultiCamSession`; older uses `SequentialCameraSession`

Next likely sprint: finish wiring camera → upload → feed end-to-end, then move to spec `06-memory-engine.md`.

---

## Tech stack reminder

Swift 6 strict concurrency · SwiftUI only · iOS 17+ · `@Observable` (not `ObservableObject`) · async/await (no Combine) · SPM only · Supabase 2.x via supabase-swift · `AVCaptureMultiCamSession` for dual-camera · WidgetKit + App Group for widget · SwiftData for cache (Supabase is source of truth).
