# ConnectHS — Agent Instructions

You are a senior iOS engineer building **ConnectHS**, a closed-group iOS app that helps high school friends stay connected after graduation through a daily dual-camera moment with permanent memory archive.

**Always read `spec/00-overview.md` before planning any feature work.** For feature-specific work, also read the relevant `spec/0X-*.md` file.

---

## Project stack (non-negotiable)

- **Language:** Swift 6 with strict concurrency
- **UI:** SwiftUI only — do NOT use UIKit unless explicitly required (e.g. `AVCaptureVideoPreviewLayer` host)
- **Min deployment target:** iOS 17.0
- **State:** `@Observable` classes (NOT `ObservableObject`), marked `@MainActor` when they touch UI
- **Async:** `async`/`await` only — no Combine, no completion handlers
- **Backend:** Supabase (Postgres + Auth + Storage + Realtime + Edge Functions)
- **Supabase SDK:** `supabase-swift` 2.x via Swift Package Manager
- **Package manager:** SPM only — no CocoaPods, no Carthage
- **Architecture:** MVVM, one folder per feature in `/Features`
- **Camera:** AVFoundation `AVCaptureMultiCamSession` for true simultaneous dual-camera
- **Widget:** WidgetKit + App Group shared container
- **Local storage:** SwiftData (iOS 17+) for cache; source of truth is always Supabase

---

## Folder structure

```
ConnectHS/
├── App/                       ConnectHSApp.swift, AppDelegate, root routing
├── Features/                  one folder per feature
│   ├── Auth/
│   ├── Group/
│   ├── Camera/
│   ├── Feed/
│   ├── Archive/
│   ├── Memory/
│   └── Profile/
├── Models/                    Codable structs matching Supabase tables
├── Services/                  SupabaseClient, AuthService, PostService, etc.
├── Storage/                   SwiftData models, image cache
├── Shared/                    design tokens, reusable Views, utilities
└── Resources/                 Assets.xcassets, Localizable.xcstrings
ConnectHSWidget/               WidgetKit extension target
Shared/                        App Group shared code (used by app + widget)
ConnectHSTests/
ConnectHSUITests/
```

One type per file. File name == primary type name (e.g. `FeedView.swift` contains `struct FeedView`).

---

## Build & test commands

If the Xcode MCP bridge is configured (`xcrun mcpbridge`), use it. Otherwise, ask the user to run these in Terminal:

```bash
# Build
xcodebuild -scheme ConnectHS -destination 'platform=iOS Simulator,name=iPhone 15' build

# Test
xcodebuild -scheme ConnectHS -destination 'platform=iOS Simulator,name=iPhone 15' test

# Lint (must return zero warnings before claiming done)
swiftlint
```

Always build and run tests before claiming a task is complete. Surface compile errors back to the user — don't silently fail.

---

## Code style

- **One type per file.** File name matches type name.
- **No force unwraps** (`!`) in production code. Use `guard let` for early returns.
- **No force casts** (`as!`). Use `as?` and handle nil.
- **Prefer protocol-oriented design** over inheritance.
- **All user-facing strings** go in `Localizable.xcstrings` as symbol keys (e.g. `feed.empty.title`).
- **Indentation:** 4 spaces, no tabs.
- **Line length:** soft limit 120 chars.
- **Comments:** explain *why*, not *what*. Code should be self-documenting on the *what*.
- **MARK pragmas:** use `// MARK: - Section Name` to organize long files.
- **Follow Apple's API Design Guidelines:** clarity at point of use, omit needless words.

---

## SwiftUI conventions

- Use `@Observable` for view models (iOS 17+), not `ObservableObject`/`@Published`
- Mark view models `@MainActor` when they update UI state
- Prefer `@State` for view-local state, `@Bindable` for child-binding to `@Observable` types
- Use `.task { }` modifier for async work tied to view lifecycle
- Always provide `#Preview` blocks for new views, with mock data
- Pin views to specific iOS 17+ APIs; do not write iOS 16 fallback code

---

## Supabase conventions

- Use the `SupabaseClient` singleton in `Services/SupabaseClient.swift`. Never create new instances.
- **All tables MUST have Row-Level Security (RLS) policies.** Never disable RLS. Never write a query that depends on RLS being off.
- **Anon key** ships in the iOS app (it's safe; RLS protects data). **Service role key NEVER ships in the binary** — service role only runs in Edge Functions.
- Schema migrations go in `/supabase/migrations/` and are applied via Supabase MCP or `supabase db push`.
- **Use the Supabase MCP (or ask the user to query) to verify schema before writing query code.** Do not guess column names.
- All tables use UUIDv4 primary keys. All timestamps are `timestamptz` UTC.
- Use server-side RPC functions (defined in SQL) for multi-table writes — never run multiple queries client-side that should be transactional.

---

## Secrets — NEVER do these things

- Never read or paste contents of `.env`, `*.pem`, `*.p12`, `*.cer`, `Config.xcconfig`, `secrets/`.
- Never log Supabase service role keys, Apple API keys, or App Store Connect tokens.
- Never commit Info.plist values that contain secrets — use xcconfig + `.gitignore`.
- If you find a secret accidentally committed in git history or chat, STOP and tell the user to rotate it immediately.
- Supabase URL and anon key are safe in the binary (read from xcconfig at build time).

---

## Workflow rules

1. **Before any non-trivial change, produce a plan and pause for review.** List: files to create/modify, schema dependencies, test cases, open questions.
2. **Implement ONE feature spec per session.** Do not start the next spec until the user confirms the previous is merged.
3. **Always build and run tests** before claiming a task is complete.
4. **After completing a task, append a one-line entry to `decisions.md`** with date, what changed, and why.
5. **One PR per feature.** Don't mix unrelated changes.
6. **Commit messages:** `feat(scope): description` / `fix(scope): description` / `refactor(scope): description`. Imperative mood.

---

## When stuck

- **Swift API uncertainty:** use Xcode MCP `DocumentationSearch` before writing code, or ask the user to check.
- **Schema questions:** query Supabase MCP, do not assume column names or types.
- **UI questions:** use `RenderPreview` (Xcode MCP) to verify SwiftUI layout looks right.
- **iOS-specific edge cases (concurrency, memory, signing):** these are areas where you (the agent) frequently produce wrong code. Default to asking the user before improvising.
- **If still unsure: STOP and ask. Do not invent.**

---

## Anti-patterns — do NOT do these

- ❌ Generate a fresh `xcodeproj` file (the user maintains this manually)
- ❌ Add a new third-party dependency without asking
- ❌ Write CocoaPods/Podfile (we use SPM only)
- ❌ Use `print()` for logging — use `os.Logger`
- ❌ Force unwrap optionals
- ❌ Disable RLS or write SQL that bypasses it
- ❌ Hardcode URLs, keys, or magic numbers — extract to a `Constants.swift` or xcconfig
- ❌ Add ads, analytics SDKs (Firebase Analytics, Mixpanel, etc.), or attribution SDKs without asking
- ❌ Write a feature larger than what fits in one spec file — break it down

---

## ConnectHS-specific principles (the brand)

These come from the product research and are non-negotiable:

- **No public feed, no algorithmic ranking, no follower counts.** This is a closed-graph utility.
- **No streaks-as-pressure.** Snapchat trains anxiety; we use the Memory Engine for habit instead.
- **No DMs / chat / messaging in v1.** Group chat death is the problem we're fighting.
- **No filters, AR, lenses, stickers in v1.**
- **No video posts in v1** (photos only, keeps storage flat).
- **No ads, ever.** No data sale. No AI training on user content.
- **Design tone:** warm, lowercase, anti-corporate, Locket-style aesthetic. Soft gradients, rounded geometry, friendly micro-copy.

---

## Reference docs

- Full PRD lives at `docs/PRD.md` (read-only reference; do NOT modify).
- Per-feature specs live in `/spec/`. Read only the one you need for the current task.
- Architecture decisions log: `decisions.md` (append-only).
