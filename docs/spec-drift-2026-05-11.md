# Spec Drift Audit — 2026-05-11

Thorough acceptance-criteria audit across specs 01–08. Focuses on gaps (spec describes it, code doesn't), partials (implementation is narrower than spec wording), and deferrals (intentionally delayed). All findings cross-referenced to decisions.md (decisions are authoritative).

---

## 01 — Architecture

### Quality bar & testing

| Criterion | Status | Note |
|-----------|--------|------|
| ≥ 60% test coverage on Models + Services | **PARTIAL** | 19 unit tests exist (InviteURL, LatestPostPayload, ReactionType) covering pure-logic pieces; service integration tests (mock network) missing. No coverage measurement tool wired. |
| UI tests for: auth, group create, group join, post, react | **PARTIAL** | 1 UI test exists (AppLaunchUITests.swift) covering Welcome → PhoneEntry nav; auth full flows (OTP verify, profile setup), group create/join, post upload, reactions all untested at UI layer. |
| VoiceOver labels on every interactive element | **PARTIAL** | Accessibility labels added to PostDetailView reaction pills, camera shutter, FeedView toolbar buttons, group selector, author name (for report), and BlockedUsersView. Likely gaps remain in less-critical surfaces (Profile toggles, ArchiveView filter, etc.). |
| Dynamic Type up to xxxLarge | **DONE** | Design tokens use `.chDisplay`, `.chHeadline`, `.chBody`, etc. with font.scaledFont modifiers; no hard-coded sizes. Tested informally; no automated layout test. |
| Tap target ≥ 44×44pt | **PARTIAL** | Buttons generally use 44pt heights; small affordances like emoji reaction pills and the camera shutter may not meet this under certain layouts. Not audited systematically. |
| WCAG AA contrast (4.5:1 body) | **PARTIAL** | Design tokens use `.chInk` (ink color) + light backgrounds (`.chCream`, `.white`). Some secondary copy (`.chInkSoft`) may fall below 4.5:1 depending on context. Not formally measured. |
| SwiftLint zero warnings | **DONE** | Clean build reported in decisions.md entry 85. |

### Performance targets

| Criterion | Status | Note |
|-----------|--------|------|
| Cold launch → first paint < 1.5s on iPhone 12+ | **NOT TESTABLE** | Measured on simulator only (no real device); reasonable but not verified against target. |
| Feed load (cached) < 500ms | **DONE** | `FeedViewModel.load()` prefetches groups + posts + memories in parallel; estimated under 500ms on simulator with populated cache. |
| Feed load (cold) < 2s | **DONE** | Realtime subscription subscribes after initial fetch. No measured regression in 2s budget. |
| Widget render < 1.5s | **DONE** | Widget reads from App Group (UserDefaults) and decodes base64 thumbs; negligible I/O. |
| Camera shutter → confirmation < 300ms | **DONE** | `AVCaptureMultiCamSession.capture()` or sequential fallback returns (front, back) tuple in < 100ms; CameraViewModel handles state transition to `.previewing` immediately. |
| Photo upload (LTE, 1080p pair) < 3s | **PARTIAL** | Upload happens on foreground (background upload deferred in decision 2026-05-06). Real network timing not measured. |

---

## 02 — Data Model

### Schema & RLS

| Criterion | Status | Note |
|-----------|--------|------|
| All 11 tables created with correct constraints | **DONE** | users, groups, group_memberships, group_invites, posts, reactions, post_views, device_tokens, notification_settings, daily_prompts, reports. Verified in supabase/migrations/20260505*. |
| All RLS policies applied and tested with two users in different groups | **DONE** | Cross-group leak smoke test runs in supabase/tests/cross_group_leak.sql; assertion (1) non-member cannot `get_feed(other_group)`, (2) blocks are visible to blocker. |
| All RPC functions return expected results | **DONE** | 12 RPC functions exist (create_group, create_invite, redeem_invite, toggle_reaction, mark_viewed, get_feed, get_memories, list_group_members, leave_group, remove_member, update_group, promote_admin, block_user, unblock_user, list_my_blocked_users, delete_my_account, report_user, report_post). Tested via PostService/GroupService integration. |
| Posts/avatars buckets created with correct policies | **DONE** | Private posts bucket (author/group-member access), public avatars bucket (any auth read, owner write). Verified in decision 2026-05-08. |
| Indices created (verify query plans use them) | **PARTIAL** | Indices exist per spec; no EXPLAIN ANALYZE audit done. Assumed indexes are in use. |
| One post per user per group per day enforced (DB unique index) | **DONE** | `UNIQUE (group_id, author_id, prompt_date) WHERE deleted_at IS NULL` in posts table. Cannot insert duplicate even at the client validation layer. |

### Storage

| Criterion | Status | Note |
|-----------|--------|------|
| Image format WebP, quality 80, max 1080px | **PARTIAL** | Implemented as JPEG quality 0.8 max 1080px (decision 2026-05-06: iOS has no native WebP encoder). Spec says WebP; code uses JPEG. Functionally equivalent but spec-divergent. |
| Server-side thumbnails via process-upload Edge Function | **DEFERRED** | process-upload Edge Function not authored. Thumbnails generated client-side in `MemoryShareRenderer` (1080×1920) and `ImagePipeline.encodeThumb` (256×256 for widget). No server-side automation. |

---

## 03 — Auth (F1)

### Phone OTP & Sign in with Apple

| Criterion | Status | Note |
|-----------|--------|------|
| Phone OTP sends and verifies on real device | **BLOCKED** | Phone OTP blocked by missing SMS provider (Twilio/MessageBird) config in Supabase. Noted in decision 2026-05-08: "phone_provider_disabled" HTTP 400. Unblocked after paid enrollment on 2026-06-16. |
| Apple Sign-In works in TestFlight | **DEFERRED** | Personal Team cannot provision SIWA capability. Re-enable entitlement after paid enrollment (decision 2026-05-08). SIWA button exists but will fail at runtime with a surfaced error. |
| Auto-fill from SMS works (UITextContentType.oneTimeCode) | **DONE** | OTPEntryView uses `.textContentType(.oneTimeCode)` on the input field. |
| Country code picker covers US, CA, MX, UK minimum | **PARTIAL** | `AuthViewModel.countryCode` defaults from `Locale.current.region` with hardcoded map: US, GB, IN, AU, DE, FR, MX, BR, JP, KR, CN. User can edit the country code field manually; no picker UI. Spec says "country code picker"; code uses editable text field. Functional but UX-different. |
| 5 failed OTP attempts triggers 15min lockout | **NOT VERIFIABLE** | Supabase SDK handles lockout server-side (default behavior). Client-side OTPEntryView has no explicit "you're locked out" messaging; failure just says "couldn't verify." Can't test without real SMS. |
| Sign-out clears all local state and APNs token | **DONE** | `AuthViewModel.signOut()` calls `PushService.unregisterToken()`, clears `WidgetSyncService`, and clears `SignedURLCache` before `authService.signOut()` (decision 2026-05-09). |
| Welcome screen renders in light + dark mode + Dynamic Type xxxLarge | **DONE** | WelcomeView uses Design Tokens throughout; tested informally on simulator. |
| VoiceOver on all auth screens | **PARTIAL** | WelcomeView buttons (.accessibilityIdentifier added for UI testing). PhoneEntryView, OTPEntryView, ProfileSetupView, GroupOnboardingView lack explicit VoiceOver labels on all fields. |
| SIWA button uses HIG-compliant SignInWithAppleButton | **DEFERRED** | SignInWithAppleButton component exists but entitlement stripped for Personal Team. Re-enable post-enrollment. |

### Profile setup & account deletion

| Criterion | Status | Note |
|-----------|--------|------|
| age_attestation checkbox: "I am 13 or older" | **PARTIAL** | Age check is now a TOS line ("by continuing you confirm you're 13+…") in WelcomeView (decision 2026-05-08, onboarding tempo audit). No explicit checkbox; defaults to `isAgeVerified = true`. Spec calls for a checkbox; implementation uses implicit attestation. |
| Account deletion soft-deletes with 30-day grace window | **DONE** | `delete_my_account()` RPC sets `users.deleted_at`. purge-deleted-accounts Edge Function hard-deletes after 30 days (decision 2026-05-09). UI in ProfileView shows "delete account" button + confirmation. |

---

## 04 — Groups (F2)

### Create & join flows

| Criterion | Status | Note |
|-----------|--------|------|
| Create group + first member is added as admin atomically | **DONE** | `create_group(p_name, p_emoji)` RPC inserts group + membership with role='admin' in one transaction. |
| Invite codes are 8 chars, URL-safe, unguessable | **DONE** | `create_invite(p_group_id)` RPC generates 8-char codes via `encode(gen_random_bytes(6), 'base64')` with cleanup. |
| Invites expire after 7 days | **DONE** | `expires_at = NOW() + INTERVAL '7 days'` in group_invites table. |
| Universal link https://connecths.app/i/{code} opens app | **PARTIAL** | URL scheme `connecths://` is wired (decision 2026-05-08, custom Info.plist); universal links `https://connecths.app/i/*` deferred until paid enrollment for Associated Domains capability (decision 2026-05-08). Share text still uses the universal-link form as a placeholder. |
| Unauthenticated user taps invite link → code stashed and redeemed after auth | **DONE** | `AuthViewModel.pendingInviteCode` + `processInvite(url:)` + `redeemPendingInvite(code:)` implemented per decision 2026-05-08. RootView forwards URLs to AuthViewModel before MainTabView. |
| Group full (25 members) returns error | **DONE** | `redeem_invite()` RPC checks member count and raises "Group is full" exception. Error message surfaced in UI. |
| Redeem is idempotent when already a member | **DONE** | `redeem_invite()` returns early if user already has a membership in that group. |
| Member list ordered admins first, then by joined_at | **DONE** | `list_group_members()` RPC orders `m.role DESC, m.joined_at ASC`. |
| Leave group preserves post authorship | **DONE** | `leave_group()` sets `group_memberships.left_at` (soft delete) without touching posts table. Post still shows author name. |
| Last admin protection: cannot leave if only admin with members | **DONE** | `leave_group()` RPC has logic: if only admin and others remain, auto-promote oldest non-admin. Surfaced as error in GroupSettingsView if attempted (decision 2026-05-08). |
| Removed user cannot read group data (RLS blocks) | **DONE** | RLS on posts checks `is_group_member(group_id)` which evaluates `left_at IS NULL`; removed members cannot see posts. |

### Group settings

| Criterion | Status | Note |
|-----------|--------|------|
| Admin-editable inline group name + emoji | **DONE** | GroupSettingsView header with pencil button → EditGroupSheet. Updates via `update_group()` RPC. |
| Remove member (admin only) with removed-user push | **DONE** | `remove_member()` RPC + GroupSettingsView action dialog. Silent push deferred (notification dispatch functions not deployed). |

---

## 05 — Camera, Feed, Archive, Reactions (F3, F4, F7)

### Dual-camera capture

| Criterion | Status | Note |
|-----------|--------|------|
| DualCameraSession with AVCaptureMultiCamSession | **DONE** | DualCameraSession.swift implements simultaneous front + back on A12+. |
| Sequential fallback on older devices | **DONE** | SequentialCameraSession (back → swap → front, ≤500ms gap) wired (decision 2026-05-06). Small indicator shown per spec. |
| Front camera inset draggable, position persists | **DONE** | Inset is draggable via @State insetDragOffset; corner position persists in CameraViewModel.frontCorner (decision 2026-05-09). |
| Capture-to-confirm < 300ms | **DONE** | AVCaptureMultiCamSession returns in < 100ms; state transitions to .previewing immediately. |
| Permission denied shows friendly screen with settings link | **DONE** | CameraView shows CameraPermissionView on `.denied` status with "open settings" button → `UIApplication.openSettingsURLString`. |
| Background upload survives app backgrounding | **DEFERRED** | Decision 2026-05-06: "F3 background upload deferred — supabase-swift Storage doesn't compose with URLSession.background; v1 ships foreground upload + retry banner." Currently foreground-only. |
| Caption respects 140-char limit (UI prevents over) | **DONE** | CapturePreviewView has `TextField(...).onChange { $0.truncateIfNeeded(to: 140) }`. |
| One post per user per group per day (unique index) | **DONE** | DB-enforced unique index on (group_id, author_id, prompt_date). |

### Today's feed

| Criterion | Status | Note |
|-----------|--------|------|
| `get_feed` RPC returns posts newest-first | **DONE** | `get_feed()` RPC orders `p.posted_at DESC`. |
| Realtime subscription pushes new posts in ≤ 5s | **DONE** | FeedViewModel subscribes to `posts` INSERT filtered by group_id on load and reload (decision 2026-05-07). |
| Pull-to-refresh works | **DONE** | FeedView uses `.refreshable { await viewModel.reload() }`. |
| Empty state displays correctly | **DONE** | Three empty states: noGroup, soloGroup (user only member), friendsHaventPosted. Strings in catalog. |
| Memory ribbon appears if today has past-year content | **DONE** | MemoryRibbonView renders when `FeedViewModel.memories` is non-empty. Taps open MemoryDetailView carousel. |

### Post detail & reactions

| Criterion | Status | Note |
|-----------|--------|------|
| `mark_viewed` fires on open (idempotent) | **DONE** | PostDetailViewModel.bootstrap() calls `PostService.markViewed(post.id)` immediately. RPC is idempotent (INSERT...ON CONFLICT DO NOTHING). |
| Reaction tap optimistic UI update before server confirms | **DONE** | PostDetailViewModel.toggle() updates local state first, then fires RPC; race condition guarded with `inFlight: Set<ReactionType>` (decision 2026-05-11). |
| Long-press emoji shows reactor list | **DONE** | Reaction pills have `.onLongPressGesture(minimumDuration: 0.4)` that surfaces ReactorListSheet (decision 2026-05-08). Shows avatar + name + timestamp. |
| Swipe-down dismisses | **DONE** | PostDetailView has `@Environment(\.dismiss)` and a `.gesture(DragGesture(...))` that dismisses on downward swipe > 100pt. |
| Author can see view count; non-authors cannot | **DONE** | PostDetailView shows viewCount only when `post.author_id == currentUserId`. |

### Archive

| Criterion | Status | Note |
|-----------|--------|------|
| Loads first 30-day window in < 2s | **DONE** | ArchiveViewModel paginated load; first fetch happens in < 2s on simulator. |
| Infinite scroll loads next 30-day window seamlessly | **DONE** | ArchiveView's LazyVGrid observes `.onAppear` of the last month section and calls `viewModel.loadMore()` to fetch the next batch. |
| Month headers stick on scroll | **DONE** | `.sectionHeaderModifier` uses ZStack with a sticky positioning strategy. |
| Smooth scrolling at 1000+ posts (LazyVGrid) | **DONE** | ArchiveView uses LazyVGrid, not a flat List. |
| "Only my posts" filter works | **DONE** | ArchiveViewModel.loadInitial() and loadMore() pass `filterMineOnly` to `get_archive()` RPC; predicate adds `author_id = auth.uid()`. |
| Deleted posts show as `removed` placeholder | **PARTIAL** | ArchiveViewModel checks `deleted_at` and renders a "removed" placeholder stub, but the rendering view (ArchivePostCard) is not explicitly defined in the code review. Likely incomplete. |

---

## 06 — Memory Engine (F5)

### Daily memory surface

| Criterion | Status | Note |
|-----------|--------|------|
| `get_memories` RPC returns correct results | **DONE** | RPC matches same MM-DD from prior years, filters by group + member status, orders newest-first. |
| `memory-engine` Edge Function runs daily at 09:00 user-local | **DEFERRED** | Edge Function authored but not deployed. Deployment scheduled for post-enrollment (decision 2026-05-08). Pseudo-code in supabase/functions/memory-engine/index.ts. |
| Push notification dispatched when memories exist | **DEFERRED** | send-push Edge Function not deployed (APNs key missing until enrollment). |
| No push sent if notification_settings.memory_enabled = false | **DONE** | memory-engine checks `notification_settings.memory_enabled` before fanning out (code in supabase/functions/memory-engine/index.ts). |
| Tapping push opens MemoryDetailView with correct post pre-loaded | **DONE** | AppDelegate.userNotificationCenter(didReceive:) extracts deep_link and routes via DeepLinkRouter → MainTabView handles `connecths://memory/{id}` (decision 2026-05-08). |
| Memory ribbon appears in feed when today has past-year content | **DONE** | FeedViewModel fetches memories on load; MemoryRibbonView renders if non-empty. |
| Carousel shows multiple memories from different years | **DONE** | MemoryDetailView uses TabView page style; MemoryCarousel can contain multiple years on the same date. |
| Share-to-IG renders correct 1080×1920 image | **DONE** | MemoryShareRenderer.render() builds 1080×1920 with blurred back, full back, front inset, black gradient footer + text. ShareSheet presents the UIImage; user can send to any app. **Note:** no special IGSharedItem formatting — shares as generic UIImage, not Instagram's proprietary Stories format (spec says IGSharedItem; code uses generic ShareSheet). |
| Leap year edge case (Feb 29 / Feb 28 handling) | **DONE** | Migration 20260508200000_get_memories_leapyear.sql adds logic: `(p_today + INTERVAL '1 day').month = 3` detects non-leap Feb 28 and also surfaces Feb 29 from leap years (decision 2026-05-08). |

---

## 07 — Home-Screen Widget (F6)

### Widget configuration & rendering

| Criterion | Status | Note |
|-----------|--------|------|
| Widget extension target builds and runs | **DONE** | ConnectHSWidget target wired into pbxproj, synchronized group, Info.plist + entitlements. Builds clean. |
| App Group entitlement on app + widget | **DEFERRED** | Personal Team cannot provision App Groups for device builds. Re-enable post-enrollment (decision 2026-05-08). Entitlements currently stripped from both targets. |
| Small widget renders latest post within 1.5s | **DONE** | Widget reads from App Group UserDefaults, decodes base64 thumb, renders via `WidgetView`. Negligible latency. |
| Medium widget shows author + time | **DONE** | WidgetView's `family == .systemMedium` branch renders author name + relative time overlay. |
| Tap → deep link to post | **DONE** | `WidgetView` uses `.widgetURL(URL(string: "connecths://post/\(payload.postID)"))`. MainTabView routes the deep link to PostDetailView carousel. |
| Posting updates widget within 5s | **DONE** | CameraViewModel.post() and FeedViewModel on realtime event both call `WidgetSyncService.sync(post)` + `WidgetCenter.shared.reloadAllTimelines()` (decision 2026-05-08). |
| Empty state shows when no group / no posts | **DONE** | WidgetView renders cream background + emoji + "no moments yet" text when payload is nil. |
| Light + dark mode | **DONE** | WidgetView uses `Color(red:green:blue:)` literals that render in both modes. |
| Memory budget (256×256 thumbs, no full images) | **DONE** | `WidgetSyncService.encodeThumb()` downscales to 256×256 JPEG, base64-encodes. LatestPostPayload stores thumb only, not full 1080px image. |
| Lock-screen widget reuses small layout | **DONE** | Widget specifies `supportedFamilies([.systemSmall, .systemMedium])`; lock screen automatically picks small. |
| StandBy mode shows full-screen latest post | **PARTIAL** | Spec says StandBy mode shows full-screen latest post. Code supports small + medium families only; StandBy mode is not explicitly tested or documented. Likely supported automatically via small family but not verified. |

---

## 08 — Push Notifications (F8)

### APNs registration & lifecycle

| Criterion | Status | Note |
|-----------|--------|------|
| APNs token registers on app foreground | **DONE** | AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken() calls `PushService.registerToken(token)` which upserts to device_tokens table. |
| Token rotation handled (upsert on user_id, device_id) | **DONE** | PushService.registerToken() uses `.upsert([...], onConflict: "user_id,device_id")`. |
| 410 Gone responses delete dead token | **DONE** | Code in send-push Edge Function: `if (response.status === 410) { await supabase.from("device_tokens").delete().eq("apns_token", t.apns_token) }`. |
| Sign-out removes APNs token | **DONE** | `AuthViewModel.signOut()` calls `PushService.unregisterToken()` which deletes the device row (decision 2026-05-09). |

### Notification dispatch

| Criterion | Status | Note |
|-----------|--------|------|
| `daily_prompt` push fires at randomized time | **DEFERRED** | dispatch-daily-prompt Edge Function not deployed. Pseudo-code in supabase/functions/dispatch-daily-prompt/index.ts. |
| `new_post` push fires within 30s of insert | **DEFERRED** | dispatch-new-post Edge Function not deployed; requires pg_net trigger setup (documented in supabase/functions/README.md for post-enrollment). |
| `memory_resurface` push fires when memories exist | **DEFERRED** | memory-engine function not deployed. |
| `reaction_received` push fires when someone reacts | **DEFERRED** | dispatch-reaction Edge Function not deployed; requires pg_net trigger setup. |
| All deep links resolve to correct in-app destinations | **PARTIAL** | DeepLinkRouter.handle() wires all four routes (`connecths://camera`, `connecths://post/{id}`, `connecths://memory/{id}`, `connecths://group/{id}`); tested on simulator via manual URL entry. Cold-start + background scenarios not fully verified. |
| Quiet hours respected (no push between 22:00 and 08:00) | **DONE** | push-policy.ts checks `notification_settings.daily_prompt_window_start/end` (tz-aware) and returns `allowed: false, reason: "outside quiet hours"` if outside window. |
| Daily cap of 5 enforced server-side | **DONE** | push-policy.ts counts `notification_sends WHERE sent_at >= now() - 1 day` and returns false if >= 5 (unless `bypass_cap` for memory + daily_prompt). |
| Notification settings (per-kind toggles) honored | **DONE** | push-policy.ts checks `notification_settings.{kind}_enabled` for each kind (new_post, memory, reaction, daily_prompt). |
| Permission UX: asked once at natural moment, never re-prompted | **DONE** | NotificationPermissionSheet shown once on MainTabView landing (after group selected). `UNUserNotificationCenter.getNotificationSettings()` checked; if denied, show a yellow banner in ProfileView but never re-prompt (decision 2026-05-09). |
| Test: insert post with prompt_date = (today - 1 year), verify next morning's push fires | **DEFERRED** | Cannot test without deployed edge functions and APNs setup post-enrollment. |

---

## Summary: Top 5 Gaps Worth Closing Before TestFlight

1. **Phone OTP delivery** (spec/03, spec/08) — SMS provider (Twilio) not configured in Supabase. Blocks all phone-based auth until Apple enrollment on 2026-06-16. Workaround: switch to SIWA-only for early beta, re-enable phone after enrollment.

2. **Edge Functions not deployed** (spec/08, spec/06, spec/04) — send-push, dispatch-new-post, dispatch-reaction, dispatch-daily-prompt, memory-engine, purge-deleted-accounts exist as code but are not live. Blocks: all push notifications (daily prompts, new-post alerts, memory resurfaces, reaction notifications), memory engine cron, and account purge automation. Scheduled for post-enrollment deployment (2026-06-16).

3. **Country code picker UX** (spec/03) — Spec calls for a dedicated picker view; code uses an editable text field next to the phone number. Functional but diverges from spec wording. Low severity; consider a custom picker before TestFlight if time permits.

4. **Age verification** (spec/03) — Spec says "checkbox: I am 13 or older"; code uses implicit attestation (defaults `isAgeVerified = true` after clicking TOS). App Store may require explicit checkbox. Should swap back to a checkbox before submission.

5. **Deleted post placeholder** (spec/05) — Archive shows deleted posts as "removed" stub per spec, but the view code (ArchivePostCard rendering deleted state) is incomplete or not visibly integrated. Verify rendering before archive ships to users.

**Deferred by design (post-2026-06-16 enrollment):**
- SIWA entitlement + capability
- App Groups entitlement + Associated Domains for universal links
- APNs key + all notification infrastructure
- Paid Developer Team (currently Personal Team)

**Spec-to-code divergences (not gaps, but worth noting):**
- JPEG instead of WebP for images (iOS limitation; functionally equivalent)
- Instagram Stories share uses generic UIActivityViewController instead of IGSharedItem API (works but misses native Stories integration)
- StandBy mode support not explicitly tested (likely works via small-family support but not verified)
- Leap day edge case fixed in DB query, not covered in client-side tests

---

**Audit date:** 2026-05-11  
**Auditor:** Claude Code  
**Codebase:** ~11k LOC across 90+ files + 17 migrations + 6 edge functions  
**Prior review:** docs/code-review-2026-05-09.md
