# ConnectHS Pre-Launch Checklist

Concrete punch-list of everything that must happen between **Apple Developer Program enrollment (2026-06-16)** and **App Store submission (target: July 2026)**.

This document derives from `decisions.md` (build log) and `docs/spec-drift-2026-05-11.md` (spec gaps). Every item below is either an external blocker that's been deferred or a final-mile task — none requires writing new feature code.

---

## 0 — Enrollment day (2026-06-16)

Day-zero tasks that unblock everything downstream. Don't proceed past §1 until these complete.

- [ ] **Pay $99 Apple Developer Program fee** at developer.apple.com.
- [ ] Confirm Alexander's account is the team's primary holder (single-developer team).
- [ ] In `App Store Connect → Users and Access`, create:
  - An admin role for yourself
  - A separate sandbox-tester Apple ID for TestFlight dogfooding
- [ ] Generate `AuthKey_<KEYID>.p8` for APNs: `Certificates, Identifiers & Profiles → Keys → +` with **Apple Push Notifications service (APNs)** enabled. Download and store securely — Apple lets you download it exactly once.

---

## 1 — Restore stripped capabilities

The code has these entitlements ready but commented out / removed because Personal Team can't provision them. Re-add after enrollment.

- [ ] **Sign in with Apple**: In `ConnectHS/ConnectHS/ConnectHS.entitlements`, restore `com.apple.developer.applesignin = [Default]`. Verify with `codesign --display --entitlements - ConnectHS.app | plutil -p -` after a build.
- [ ] **App Groups**: In both `ConnectHS/ConnectHS/ConnectHS.entitlements` and `ConnectHSWidget/ConnectHSWidget.entitlements`, restore `com.apple.security.application-groups = [group.com.alexander.connecths.shared]`.
- [ ] In Apple Developer portal, register App Group `group.com.alexander.connecths.shared` and assign to both app + widget identifiers.
- [ ] **Push notifications**: Add `aps-environment = development` to `ConnectHS.entitlements` for TestFlight; switch to `production` for App Store.
- [ ] **Associated Domains** (optional for v1, but enables universal links `https://connecths.app/i/{code}`): Add `webcredentials:connecths.app` and `applinks:connecths.app` to entitlements + host `apple-app-site-association` at `https://connecths.app/.well-known/apple-app-site-association`.

---

## 2 — Configure Supabase Auth

Phone OTP is currently broken in production (`phone_provider_disabled`); SIWA exchange is wired but the dashboard provider isn't enabled.

### Twilio (phone OTP)

- [ ] Sign up at twilio.com, buy a US toll-free or 10DLC number.
- [ ] In Supabase Dashboard → Authentication → Providers → Phone:
  - Toggle **Phone provider** on
  - Select Twilio
  - Paste **Account SID**, **Auth Token**, **Messaging Service SID**
- [ ] Verify by sending a test OTP from `WelcomeView → continue with phone`.
- [ ] (Optional cost optimization) Set rate limit `sms_sent = 30/hr` in `supabase/config.toml` (already there).

### Sign in with Apple

- [ ] In Apple Developer portal: `Certificates, Identifiers & Profiles → Identifiers → Services IDs → +`. Create one with reverse-DNS like `com.connecths.ConnectHS.web`.
- [ ] Enable **Sign in with Apple** on it; configure the Return URL = `https://<project-ref>.supabase.co/auth/v1/callback`.
- [ ] Create a SIWA **Secret Key**: `Keys → + → Sign in with Apple → Configure → Primary App ID = com.connecths.ConnectHS`. Download `.p8`.
- [ ] In Supabase Dashboard → Authentication → Providers → Apple:
  - Toggle on
  - Set **Client ID** = `com.connecths.ConnectHS` (the iOS app's bundle ID, NOT the Services ID)
  - Set **Secret Key** = paste `.p8` contents
- [ ] Test by tapping `WelcomeView → continue with Apple` on a real device (SIWA doesn't work in simulator).

---

## 3 — Deploy edge functions

All 6 functions live in `supabase/functions/` but are not deployed. Full runbook lives in `supabase/functions/README.md`; this checklist tracks completion.

- [ ] Set Supabase project secrets (`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`, `APNS_ENV=sandbox` for TestFlight, `production` for App Store).
- [ ] `supabase functions deploy send-push` (with `--no-verify-jwt`)
- [ ] `supabase functions deploy dispatch-new-post` (with `--no-verify-jwt`)
- [ ] `supabase functions deploy dispatch-reaction`
- [ ] `supabase functions deploy dispatch-daily-prompt`
- [ ] `supabase functions deploy memory-engine`
- [ ] `supabase functions deploy purge-deleted-accounts` (with `--no-verify-jwt`)
- [ ] Apply pg_net triggers from `supabase/functions/README.md` §4 (creates `trg_fanout_new_post` + `trg_fanout_new_reaction`).
- [ ] Set DB settings: `app.settings.functions_url` and `app.settings.service_role_key`.
- [ ] Schedule pg_cron jobs from `supabase/functions/README.md` §5:
  - `memory-engine` every hour
  - `dispatch-daily-prompt` every 15 minutes
  - `purge-deleted-accounts` daily at 03:30 UTC
- [ ] Smoke-test: insert a post via the iOS app → verify `new_post` push arrives on a real device within ~10s.
- [ ] Smoke-test: insert a reaction → verify `reaction_received` push arrives + that a re-react within 5 minutes is silently dropped (cooldown).

---

## 4 — App Store Connect submission

- [ ] **App Store metadata**: write app name (`connecths`), subtitle (≤ 30 chars), description (4000 chars), keywords, support URL, marketing URL, privacy policy URL.
- [ ] Add a privacy policy at `https://connecths.app/privacy` — the URL is referenced in `docs/app-store-privacy.md`. Cover: data collected per `PrivacyInfo.xcprivacy`, retention, deletion, no third-party sharing, no ads/tracking.
- [ ] Add a support URL — minimum a static page at `https://connecths.app/support` with an email contact.
- [ ] Submit `docs/app-store-privacy.md` answers verbatim into App Store Connect → App Privacy. All data types: Linked, App Functionality, not used for tracking.
- [ ] Confirm `PrivacyInfo.xcprivacy` ships in the bundle (`builtin-infoPlistUtility -scanforprivacyfile` is wired via PBXFileSystemSynchronizedRootGroup).
- [ ] **Screenshots**: 6.7" (iPhone 17 Pro Max sim) + 6.5" + 5.5" — minimum 3 screenshots per size. Capture Welcome, Feed, Camera, Memory Detail.
- [ ] **App icon**: confirm light/dark/tinted variants in `Assets.xcassets/AppIcon.appiconset` render correctly. Sanity-check on Home Screen + Settings + Spotlight.
- [ ] **Age rating**: 12+ (UGC with no moderation algorithms, no in-app purchases, no objectionable content). Filling the questionnaire honestly should land here.
- [ ] **Export compliance**: `ITSAppUsesNonExemptEncryption = false` in `ConnectHS-Info.plist` — already set. Confirms HTTPS-only TLS is exempt.

---

## 5 — TestFlight readiness

- [ ] Archive a Release build: `Product → Archive` in Xcode against a real iPhone (NOT simulator). The Personal-Team-stripped capabilities are now restored, so this should succeed.
- [ ] Upload via `Window → Organizer → Distribute App → App Store Connect`.
- [ ] Wait for processing (~5-15 min).
- [ ] Add TestFlight build to **Internal Testing** group with yourself + 1-2 close friends.
- [ ] Send TestFlight invite to ~10 high school friends (the dogfood cohort).
- [ ] Run through the **end-to-end smoke matrix**:
  - [ ] Cold launch → land on Welcome
  - [ ] Continue with Apple → profile setup → group create → invite share
  - [ ] Friend taps invite link → joins group → post appears in both feeds
  - [ ] Take a dual-camera moment → upload → appears in feed within 5s
  - [ ] React to friend's post → friend gets push within 10s
  - [ ] Long-press emoji → reactor list sheet shows correctly
  - [ ] Open Archive → infinite scroll works → tap → PostDetail
  - [ ] Background app → friend posts → push arrives → tap → deep-link opens that post
  - [ ] Add widget to Home Screen → shows latest moment → tap → opens that post
  - [ ] Delete account → confirm account is gone after 30 days

---

## 6 — App Store submission

- [ ] Submit for review with first TestFlight-vetted build.
- [ ] **Anticipated reviewer questions** (have answers ready):
  - "How do users register?" — phone OTP (Twilio); Sign in with Apple
  - "How does the closed-group model work without a public feed?" — Invite codes only; users can only see posts from groups they're a member of (enforced by RLS, not just UI)
  - "How is UGC moderated?" — Report (closed-set reasons) → server log; Block (one-way, hides everywhere); Delete account (soft-delete + 30-day purge); All UGC strings reviewable in `reports` table
  - "Is there a way for the user to delete their data?" — Yes, in Profile → Delete account (App Store guideline 5.1.1(v))
  - "Does the app collect any data about minors?" — Yes, phone number + display name + optional school/grad-year. 13+ attestation in Welcome's TOS line. Reviewer may push back; consider adding an explicit age toggle if rejected.
- [ ] Expect 24-72 hour review.

---

## 7 — Launch-day kit

When approved:

- [ ] Phased release: **5% → 20% → 50% → 100%** over 7 days. Apple's default.
- [ ] Monitor Supabase logs for the first 48 hours: especially `auth.users` signup rate, `posts` insert rate, edge function errors.
- [ ] Monitor APNs delivery success in `notification_sends` table.
- [ ] Set up cost alerts in Supabase: Storage > 5GB, Egress > 25GB/mo.
- [ ] Watch for crash reports in App Store Connect → Analytics.

---

## Known **deferred to v1.1**

Don't try to ship these for v1:

- Local SwiftData cache for offline (currently no offline mode; relies on Supabase)
- WebP encoding (libwebp not native, would be a third-party dep)
- Background photo upload (`supabase-swift` Storage doesn't compose with `URLSession.background`)
- Universal links via Associated Domains (only blocks share-link click-to-open for non-installers; the share text URL works once the user has the app installed)
- Country code picker UI (currently an editable digits-only text field; covers non-US testers but isn't a polished picker)
- Background sync (e.g., realtime channel keepalive)
- iPad / macCatalyst (iOS only for v1)

---

## Roll-back plan

If a critical bug ships:

1. App Store Connect → My Apps → ConnectHS → Pricing and Availability → **Remove from sale** (takes < 1 hour, prevents new installs).
2. If a server-side fix exists, push it to `main` and deploy via `supabase functions deploy` (no App Store review needed).
3. If a client-side fix is needed, archive + upload a hotfix build to TestFlight, then submit for expedited review (cite "critical user-facing bug" in the reviewer notes).
4. Once fixed, re-enable for sale.

---

*This checklist was generated from `decisions.md` entries 2026-05-05 through 2026-05-11 and `docs/spec-drift-2026-05-11.md`. Keep it updated as items complete or new blockers emerge.*
