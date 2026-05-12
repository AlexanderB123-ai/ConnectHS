# App Store privacy questionnaire — ConnectHS

This document is the canonical answer set for App Store Connect's "App Privacy"
section. Copy/paste verbatim when filling out the questionnaire; if a question
or category changes upstream, update this file *first* and then App Store
Connect — never the other way around.

Last reviewed: 2026-05-09 against the v1.0 schema (initial 0505 migration +
all migrations through 20260509060000_lockdown_table_comments).

## Tracking

**Question:** Does this app collect data in order to track the user?

**Answer:** **No.**

Per spec/00-overview.md "no ads, ever; no data sale; no AI training on user
content" — and the codebase carries zero ad SDKs, zero analytics SDKs, zero
attribution SDKs, zero MMP integrations. The `ATTrackingTransparency` prompt
is **not** required because nothing in the binary tracks across apps or
websites owned by other companies.

If a future contributor adds Firebase Analytics, Mixpanel, AppsFlyer, etc.,
this answer flips to **Yes** and the entire questionnaire below changes.
Block such additions in code review.

## Data types collected

| Apple category | Specific data | Collected? | Linked to identity? | Used to track? | Why we need it |
|---|---|---|---|---|---|
| Contact Info | Name | Yes | Yes | No | Display name shown to other group members |
| Contact Info | Phone number | Yes | Yes | No | Auth method (SMS OTP) — required to sign in |
| Contact Info | Email | Yes (only for SIWA users) | Yes | No | Auth method (Sign in with Apple relay address) |
| Contact Info | Physical address | No | — | — | — |
| Health & Fitness | — | No | — | — | — |
| Financial Info | — | No | — | — | — |
| Location | — | No | — | — | — |
| Sensitive Info | — | No | — | — | — |
| Contacts | — | No | — | — | — |
| User Content | Photos or videos | Yes | Yes | No | The "moment" — front + back camera capture posted to the user's group |
| User Content | Other user content | Yes | Yes | No | Optional caption + emoji reactions |
| Browsing History | — | No | — | — | — |
| Search History | — | No | — | — | — |
| Identifiers | User ID | Yes | Yes | No | UUID primary key on `public.users` — used to authorize requests via Supabase RLS |
| Identifiers | Device ID | No | — | — | We store an APNs push token (see Diagnostics), not the IDFA or IDFV |
| Purchases | — | No | — | — | App is free; no IAP in v1 |
| Usage Data | Product Interaction | Yes | Yes | No | `post_views` table records who viewed which post — surfaced as the "viewed by N" counter to the post author |
| Usage Data | Advertising data | No | — | — | — |
| Usage Data | Other Usage Data | No | — | — | — |
| Diagnostics | Crash data | No | — | — | We do NOT bundle Crashlytics or Sentry. Apple's own crash reporter (opt-in by the user via Settings → Privacy → Analytics) is out of scope of this questionnaire |
| Diagnostics | Performance data | No | — | — | — |
| Diagnostics | Other Diagnostic Data | Yes (APNs token) | Yes | No | `device_tokens` row stores the APNs push token bound to the user_id, used solely to deliver the four push kinds in spec/08 |
| Other Data | High school name | Yes (optional) | Yes | No | Used to suggest groups during onboarding; user can leave blank |
| Other Data | Graduation year | Yes (optional) | Yes | No | Same as above |

## Data uses (Apple "purposes")

For every "Yes" data type above, the **only** purpose declared is:

- **App Functionality** — The data is used to provide and maintain the
  service (auth, post storage, push, viewer counts, group membership).

We do **not** declare any of: Analytics, Product Personalization,
Developer's Advertising or Marketing, Third-Party Advertising, Other
Purposes. If the team ever needs to add one, it is a privacy-policy
material change — schedule a review with whoever owns App Store Connect
access first.

## Linked to identity vs. not linked

Every data type we collect is **linked to the user** because every row is
keyed on `user_id` (UUID FK to `auth.users`). There is no "anonymous
telemetry" path in v1.

## Data sharing

Apple asks: do you share user data with third parties?

**Answer:** **No.**

The only third party that touches user data is Supabase, which is a
sub-processor (not a separate "company" in Apple's sense — it's our
backend, contractually bound under their DPA). Storage is in Supabase's
US region; we do not export, sell, or share to anyone else.

If the team adds a CDN, an analytics vendor, a moderation vendor, etc.,
this answer flips to **Yes** and a sub-processor list goes into the
privacy policy.

## Required URLs (App Store Connect text fields)

- **Privacy policy URL:** TODO — needs to be live before submission. Should
  enumerate exactly the categories above plus retention (currently
  indefinite for the moments archive; 30-day grace before purge after
  account deletion — see `purge-deleted-accounts` edge function).
- **Support URL:** TODO — at minimum a static page with an email address
  reachable by users. App Review will reject without one.

## Data retention summary

This isn't on the questionnaire but reviewers ask about it in writing:

- **Posts (the moments):** retained indefinitely while the account is
  active. Soft-deleted (`posts.deleted_at`) when the user calls
  `delete_my_account`. Hard-deleted along with the user via the
  `purge-deleted-accounts` cron 30 days later.
- **Avatars:** same lifecycle as the user record.
- **Device tokens:** deleted immediately on sign-out
  (`PushService.unregisterCurrentDevice`) or on a 410 Gone response from
  APNs (`send-push` cleans up dead tokens).
- **Reports:** retained server-side (moderation queue) — never exposed to
  the reported user or the reporter, and never deleted automatically.
- **Notification sends ledger:** retained for daily-cap math; no scheduled
  purge. Could be aged out at 90 days if it grows unwieldy.

## Things to double-check before each App Store submission

1. No new SDK was added without a privacy-policy review.
2. `Info.plist` `NSCameraUsageDescription` and `NSPhotoLibraryAddUsageDescription`
   strings still match the on-screen copy in `CameraPermissionView` and
   the `PhotosPicker` flow respectively.
3. `ITSAppUsesNonExemptEncryption=false` is still correct (we only do
   standard HTTPS via Supabase / APNs — no custom crypto, no DRM).
4. The Privacy Manifest (`PrivacyInfo.xcprivacy`) declares the same
   data categories listed above. Apple started enforcing this for new
   submissions in 2024; if we don't have one yet it's a launch blocker.
