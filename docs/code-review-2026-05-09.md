# ConnectHS — Senior Dev Code Review (2026-05-09)

Reviewer: senior iOS engineer, read-only inspection. No code modified. Project state as of commit-on-disk on 2026-05-09 morning, mirroring the latest entries in `decisions.md`.

---

## 1. What's working well

- All 8 v1 features (F1–F8) are implemented end-to-end on both client and server. This is not a scaffold — it's a feature-complete v1.
- 14 SQL migrations applied; client-side `Models/` mirror every column with snake_case `CodingKeys`. No drift between schema and Swift.
- 6 Deno edge functions authored (`send-push`, `dispatch-new-post`, `dispatch-reaction`, `memory-engine`, `dispatch-daily-prompt`, `purge-deleted-accounts`) plus `_shared/apns.ts` with ES256 JWT signing.
- Swift 6 strict-concurrency hygiene is exemplary: zero `try!`, zero `as!`, zero `print()`, exactly one force-unwrap (a compile-time URL literal in `SupabaseClient.swift`), no `// TODO` / `// FIXME` markers anywhere in `ConnectHS/`.
- Every view model is `@MainActor @Observable` per CLAUDE.md. Every view I sampled has a `#Preview` (one exception: `CapturePreviewView`).
- Localization catalog (`Localizable.xcstrings`) is fully wired — all UGC strings flow through `String(localized:)` or SwiftUI's auto-resolved `Text("key")`. Plural variant for member counts.
- App Store paperwork is done before submit: `PrivacyInfo.xcprivacy` manifest, `docs/app-store-privacy.md` answer sheet, full UGC safety triangle (report + block + delete-account).
- Realtime + foreground reload + scenePhase observer means the feed self-heals after a network blip or backgrounded socket.
- Camera has both `AVCaptureMultiCamSession` (A12+) and `SequentialCameraSession` fallback with proper `nonisolated` `PhotoCaptureDelegate`.
- Widget is genuinely wired into pbxproj with a synchronized group, App Group entitlements, custom Info.plist, and a child-of-host bundle id (`com.connecths.ConnectHS.widget`).
- Cross-group RLS leak test (`supabase/tests/cross_group_leak.sql`) exists and passes — the closed-graph guarantee is verified, not assumed.
- Dispatchers are block-aware (filter `user_blocks` before fan-out) and reaction-storm cooldown (5min per recipient/post) is in place.
- Avatar pipeline end-to-end: bucket + RLS + RPC + service + reusable `AvatarView` component, with cache-bust via `avatarRefreshToken`.

---

## 2. Current implementation map

| Feature | Status | Primary files | Notes |
|---|---|---|---|
| F1 Auth — phone OTP | 🔴 blocked | `AuthService.swift`, `Features/Auth/*` | Code complete; Supabase project lacks Twilio config — every `/otp` returns `phone_provider_disabled`. |
| F1 Auth — Sign in with Apple | 🔴 blocked | `WelcomeView.swift` | Code + nonce/SHA256 plumbing complete; SIWA entitlement stripped because Personal Team can't provision it. Re-add post-2026-06-16. |
| F2 Groups | ✅ done | `GroupService.swift`, `Features/Group/*` | Create/join/invite/list-members/leave/remove/promote/update all wired. Settings UI complete with last-admin protection. |
| F2 Invites by link | ✅ done | `InviteURL.swift`, `redeem_invite` RPC | Custom-scheme + universal-link parser, clipboard auto-detect, share sheet on create. |
| F3 Camera | ✅ done | `Features/Camera/*`, 8 files | Multicam + sequential fallback, drag-to-snap inset, retry-without-recapture, accessibility labels. |
| F3 Upload | ✅ done | `PostService.uploadMoment`, `create_post` RPC | JPEG q0.8, max 1080px, atomic via RPC. Background upload deferred per F3 decision. |
| F4 Feed | ✅ done | `FeedView.swift`, `FeedViewModel.swift` | Realtime subscription, scenePhase reload, three-variant empty state, refreshable, group selector dropdown. |
| F4 Archive | ✅ done | `ArchiveView.swift`, `get_archive` RPC | Sticky-header monthly grid, infinite scroll, only-mine filter. |
| F5 Memory Engine | ✅ done | `Features/Memory/*`, `get_memories` RPC | Ribbon at top of feed, swipeable carousel, share renderer (1080×1920 with footer), leap-year fix migration applied. |
| F6 Widget | ✅ wired (entitlement-blocked) | `ConnectHSWidget/*`, `WidgetSyncService.swift` | systemSmall + systemMedium, deep-link to post or camera, payload + thumb pipeline. App Groups entitlement stripped on Personal Team — widget will read empty payload until enrollment. |
| F7 Reactions | ✅ done | `PostDetailViewModel.swift`, `toggle_reaction` RPC | Optimistic + reconcile, long-press reactor list sheet, accessibility labels. |
| F8 Push notifications | ✅ done | `PushService.swift`, `AppDelegate.swift`, `supabase/functions/*` | All dispatchers authored. Edge functions not deployed (waiting on enrollment for APNs key + aps-environment cap). |
| UGC safety — report | ✅ done | `ReportSheet.swift`, `report_user`/`report_post` RPCs | Closed-set reasons, free-form details. |
| UGC safety — block | ✅ done | `BlockService.swift`, `BlockedUsersView.swift` | One-directional, filters feed/archive/memories at RPC layer + push dispatch. |
| UGC safety — delete account | ✅ done | `delete_my_account` RPC + `purge-deleted-accounts` edge function | 30-day grace + nightly purge. |
| Localization | ✅ done | `Localizable.xcstrings` | Every UGC string resolves through the catalog. |
| App icon + launch | ✅ done | `AppIcon.appiconset`, `LaunchBackground.colorset`, `LaunchLogo.imageset` | Branded launch instead of default blank. |
| Tests | 🔴 written-not-runnable | `ConnectHSTests/*` | 3 suites authored, target NOT yet added in Xcode (see README). |
| `ConnectHSUITests/` | ❌ not started | empty | No UI test target. |

---

## 3. Issues — by priority

### 🔴 Blockers

**B1. Auth is unreachable on Personal Team.** Code is correct on both providers, but the supabase project has no SMS provider configured (decisions.md 2026-05-08) and SIWA + App Groups entitlements were stripped because Personal Team can't provision them. The dev sign-in backdoor was deliberately wiped (decisions.md 2026-05-08). Net: a real user lands on `WelcomeView`, taps either button, and cannot proceed. Every downstream surface (group, camera, feed, archive, memory, widget) is technically reachable in the simulator only via the bootstrapped session. Blocked by external dependency (Apple Developer Program enrollment 2026-06-16). Document mitigations elsewhere; nothing the codebase can fix.

**B2. Test target is not wired in Xcode.** `ConnectHSTests/` contains three suites (`InviteURLTests`, `LatestPostPayloadTests`, `ReactionTypeTests`) but no Unit Testing Bundle exists in the pbxproj. CLAUDE.md says "Always build and run tests before claiming a task is complete" — currently zero tests run. The README in that folder describes the one-time manual steps. Until done, the agent's quality bar is impossible to meet.

### 🟡 Should fix

**S1. Supabase URL + anon key hardcoded in source.**
```swift
// Services/SupabaseClient.swift
enum AppConfig {
    static let supabaseURL = URL(string: "https://geykbxyhzfdmjvrrrlld.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_HuzJQUU_5Gm77FRp3jGCwQ_VSNcaUjP"
}
```
CLAUDE.md anti-pattern explicitly forbids this: "Hardcode URLs, keys, or magic numbers — extract to a `Constants.swift` or xcconfig". The anon key is technically safe to ship (RLS protects data), but you'll want this in xcconfig the moment you have a staging environment, and the force-unwrap on the URL violates the same doc's "No force unwraps" rule.

**S2. `ConnectHSApp.swift` and `ContentView.swift` live at the bundle root, not in `App/`.**
- `ConnectHS/ConnectHS/ConnectHSApp.swift` — should be in `App/` per CLAUDE.md folder structure ("App/ → ConnectHSApp.swift, AppDelegate, root routing"). Xcode's @main template puts it at the root by default.
- `ConnectHS/ConnectHS/ContentView.swift` — Xcode template stub, **dead code**. The actual root view is `App/RootView.swift`. Safe to delete.

**S3. Dead helper in `PostDetailView`.**
```swift
private func initialsFor(_ name: String) -> String { … }
```
Replaced by `AvatarView` everywhere. Unused. Remove.

**S4. Two silent-fail paths.**
- `FeedView.performBlock` swallows block failures with a `// silently fail` comment.
- `BlockedUsersView.unblock` does the same.
Both are flagged "polish later" in the source. v1 is fine, but flag for the polish pass.

**S5. `DualCameraSession.PhotoCaptureDelegate` retains its `pendingDelegates` array on the session queue.** The cleanup in `dropDelegates` works, but if `cont.resume` throws after the `Task` block exits and a delegate is never resumed, the array leaks (one capture's worth — small). Defensive: add a `defer { dropDelegates(...) }` outside the Task body or convert to a strict pair-then-drop pattern.

**S6. `ConnectHSUITests/` is empty.** spec/01 architecture says "UI tests for: auth, group create, group join, post, react." Zero exist.

### 🟢 Nits

- `Picker` uses `Int(0)` as a "no selection" tag instead of `Optional<Int>`. Works, but the binding has to translate `0 ↔ nil` in two places (ProfileSetupView + ProfileEditView).
- `Button { … }.disabled({ … }())` self-executing closures in `CameraView.shutter` for state-disable logic — a computed `var canCapture: Bool` would read better.
- `formatPhoneE164` only handles US numbers (assumes `+1`). Spec says "country code picker (default +1 from Locale.current.region)" — the picker UI doesn't exist yet either, but the formatter will silently produce wrong-prefix numbers if a non-US user reaches it.
- `PhoneEntryView.isAuthenticating` and `GroupSettingsView.invitePayloadBinding` use empty-setter `Binding`s — works, but a `@State` mirror of the VM state would be more conventional.
- `PostDetailView.timeAgo` and `MemoryDetailView.formatDate` and `GroupSettingsView.formatDate` and `BlockedUsersView.formatDate` and `ArchiveViewModel.monthKeyAndTitle` each instantiate their own `DateFormatter` per call. Promote to static cached formatters (cheap, but `DateFormatter` allocation isn't free).
- `WidgetSyncService.downscale` and `ImagePipeline.downscale` are duplicate code. Extract.
- `AvatarRefreshToken: UUID` cache-bust trick in `ProfileView` is clever but slightly hacky — long-term cleaner to give `AvatarView` an explicit `version` parameter.

---

## 4. End-to-end flow status

| Stage | Status | Where it breaks |
|---|---|---|
| App launch → `RootView` | ✅ working | — |
| `RootView` → `AuthState` resolution | ✅ working | `AuthViewModel.bootstrap()` parallelizes user + memberships fetch correctly |
| `WelcomeView` → tap "continue with Apple" | 🔴 broken | SIWA entitlement stripped on Personal Team; surfaces `siwaErrorMessage` in red on the Welcome screen |
| `WelcomeView` → tap "continue with phone" | 🔴 broken | OTP send succeeds at the `signInWithOTP` call but Supabase returns `phone_provider_disabled` because no Twilio is configured. Error surfaces as "couldn't send code. try again." |
| Hypothetical post-auth: `ProfileSetupView` → `GroupOnboardingView` | ✅ implemented | Cannot reach without auth |
| `GroupOnboardingView` → create or join | ✅ implemented (untested in real auth) | RPCs exist; share sheet wired |
| `MainTabView` (active state) | ✅ implemented | Three-tab layout with deep-link routing |
| `FeedView` → today's posts | ✅ implemented | Realtime + scenePhase reload + 3-variant empty state |
| `FeedView` → camera button | ✅ implemented | `fullScreenCover(CameraView)` |
| `CameraView` → shutter → `previewing` | ✅ implemented | Multicam + sequential fallback both wired |
| `CapturePreviewView` → "post" → upload | ✅ implemented | JPEG encode + atomic RPC |
| Upload → post in feed | ✅ implemented | Realtime INSERT subscription + own-post widget refresh |

**Where the user journey actually breaks today:** at `WelcomeView` — every other surface is built but unreachable to a real user on a real device. In the iOS simulator with a pre-bootstrapped session you can verify the rest end-to-end (decisions.md confirms this was done on 2026-05-08).

---

## 5. Recommended next sprint

**Wire the Xcode test target and add `FeedViewModel` + `PostDetailViewModel` state-transition tests.**

Why this and not auth fixes:
- Auth is blocked by an external date (Apple enrollment 2026-06-16). Sitting on it doesn't help.
- Between today and enrollment day, every change you make to the codebase has zero automated regression coverage. CLAUDE.md says "Always build and run tests before claiming a task is complete" and right now that's structurally impossible.
- The `ConnectHSTests/` README already documents the manual one-click pbxproj wiring; it's a 5-minute Xcode session.
- Once wired, you have a green/red signal you can extend, and the three existing suites guarantee a non-zero baseline on day one.
- After the target exists, adding `FeedViewModelTests` (load → reload → group switch → realtime-event → reload triggered) and `PostDetailViewModelTests` (optimistic toggle + reconcile + rollback on error) is straightforward — both view models are pure-Swift and `@Observable`, so no Supabase mocking is needed if you inject the service.

Scoped small enough for one Claude Code session: add the target, wire the three existing suites, get them green on `xcodebuild test`, write two new VM tests with stubbed services, get those green. Stop.

Alternative sprint if you'd rather ship code than infra: **extract `Services/SupabaseClient.swift` config into xcconfig + `Constants.swift`** so the dev/staging/prod split exists before TestFlight. Smaller scope, immediate architectural win, but doesn't unlock anything new.

---

## 6. Concrete prompt for Claude Code

Paste this into Claude Code in Terminal at the project root:

```
Read CLAUDE.md and ConnectHS/ConnectHSTests/README.md.

Goal: stand up a runnable Xcode test target so `xcodebuild -scheme ConnectHS test`
returns green and the three existing test suites execute.

Acceptance criteria:
1. `ConnectHSTests` is a Unit Testing Bundle target in the .xcodeproj, with the
   ConnectHS app as its host application (TEST_HOST set automatically).
2. `InviteURLTests.swift`, `LatestPostPayloadTests.swift`, and
   `ReactionTypeTests.swift` are members of the new target.
3. `@testable import ConnectHS` resolves cleanly (the app target's
   ENABLE_TESTABILITY is YES for Debug).
4. `xcodebuild -scheme ConnectHS -destination 'platform=iOS Simulator,name=iPhone 15' test`
   exits 0 with all 22 test methods passing.
5. Append a one-line entry to decisions.md: "2026-05-XX — Test target wired
   into pbxproj — InviteURLTests/LatestPostPayloadTests/ReactionTypeTests
   green via xcodebuild test."

Then add two new XCTestCase files in the same folder:

  ConnectHSTests/FeedViewModelTests.swift
    - Inject a stub PostService + GroupService (define minimal protocols if
      needed; the existing services are structs but you can refactor to a
      protocol they conform to).
    - Cover: load() with empty groups → .empty state; load() with one group
      and 3 posts → .posts state with sorted feed; selectGroup() switches
      and reloads; reload() recovers when initial subscribe failed
      (subscribedGroupId starts nil, second call should subscribe).

  ConnectHSTests/PostDetailViewModelTests.swift
    - Inject a stub PostService.
    - Cover: bootstrap() seeds reactionCounts from FeedPost.reactionSummary;
      toggle() optimistic add then server reconcile; toggle() rollback on
      thrown error.

Acceptance: both new files compile, all assertions pass under
`xcodebuild test`. Update the new tests' file count in the
ConnectHSTests/README.md.

Do NOT touch any production source file other than:
- `ConnectHS.xcodeproj/project.pbxproj` (the test target wiring)
- `Services/PostService.swift` and `Services/GroupService.swift` IF a
  protocol extraction is needed for injection — keep the change small,
  protocol + existing struct conforming, no behavior change.

If pbxproj surgery is too risky to do programmatically, STOP and document
the manual Xcode steps in decisions.md instead.
```

---

## Appendix — files inspected

App/: `ConnectHSApp.swift`, `RootView.swift`, `AppDelegate.swift`, `MainTabView.swift`, `RootCoordinator.swift`, `ContentView.swift` (dead).
Models/: `User.swift`, `Group.swift`, `Post.swift`, `Reaction.swift`, `Memory.swift`, `NotificationSettings.swift`, `DeviceToken.swift`, `Report.swift`, `BlockedUser.swift`.
Services/: `SupabaseClient.swift`, `AuthService.swift`, `GroupService.swift`, `PostService.swift`, `ImagePipeline.swift`, `PushService.swift`, `AvatarService.swift`, `BlockService.swift`, `ReportService.swift`, `SignedURLCache.swift`, `WidgetSyncService.swift`.
Features/Auth/: `AuthViewModel.swift`, `WelcomeView.swift`, `PhoneEntryView.swift`, `OTPEntryView.swift`, `ProfileSetupView.swift`.
Features/Group/: `GroupOnboardingView.swift`, `GroupSettingsViewModel.swift`, `GroupSettingsView.swift`, `InviteURL.swift`, `ReportSheet.swift`.
Features/Camera/: `CameraViewModel.swift`, `CameraView.swift`, `DualCameraSession.swift`, `SequentialCameraSession.swift`, `CameraPreviewView.swift`, `CameraError.swift`, `CameraPermissionView.swift`, `CapturePreviewView.swift`.
Features/Feed/: `FeedViewModel.swift`, `FeedView.swift`, `PostDetailViewModel.swift`, `PostDetailView.swift`, `ReactorListSheet.swift`.
Features/Archive/: `ArchiveViewModel.swift`, `ArchiveView.swift`.
Features/Memory/: `MemoryRibbonView.swift`, `MemoryDetailView.swift`, `MemoryShareRenderer.swift`.
Features/Profile/: `ProfileView.swift`, `ProfileEditView.swift`, `NotificationSettingsViewModel.swift`, `BlockedUsersView.swift`.
Features/Notifications/: `NotificationPermissionSheet.swift`.
Shared/: `DesignTokens.swift`, `DeepLinkRouter.swift`, `Components/RemoteImage.swift`, `Components/AvatarView.swift`, `Components/ShareSheet.swift`, `AppGroup/SharedKeys.swift`, `AppGroup/LatestPostPayload.swift`.
ConnectHSWidget/: `ConnectHSWidget.swift`, `WidgetView.swift`, `ConnectHSWidget.entitlements`.
ConnectHSTests/: `InviteURLTests.swift`, `ReactionTypeTests.swift`, `LatestPostPayloadTests.swift`, `README.md`.
supabase/migrations/: 14 files spanning initial schema → 2026-05-09 lockdown comments. Cross-referenced against spec/02 — schema matches.
supabase/functions/: 6 functions + `_shared/` helpers + `README.md` runbook.
spec/: 00-overview, 01-architecture, 02-data-model, 03-auth read in full or in part.
docs/: PRD.md (read-only ref), FOLDER_BRIEFING.md (project state), app-store-privacy.md (submission paperwork).
decisions.md: full 80-line build log read.
CLAUDE.md: full 175-line agent rule set read.
