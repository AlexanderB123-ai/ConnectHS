# 03 — Auth (F1)

Two auth methods: phone OTP (primary, Locket-style) and Sign in with Apple (required by App Store guidelines when offering any third-party SSO).

## Goals
- Sign-up to first post: < 60 seconds
- No email + password ever (App Store guideline 5.1.1(v) friendly, no password reset flows to build)
- Apple Sign-In is mandatory (Apple guideline 4.8) since we offer phone

## Phone OTP flow

```
[WelcomeView]
  ↓ tap "continue with phone"
[PhoneEntryView]
  - Country code picker (default +1 from Locale.current.region)
  - Phone input (formats as user types, E.164 on submit)
  - Validates length per country
  ↓ tap "send code"
  → AuthService.sendOTP(phoneE164)
  → Supabase: auth.signInWithOTP(phone:)
  ↓
[OTPEntryView]
  - 6-digit code input (auto-fill from SMS via UITextContentType.oneTimeCode)
  - 30s resend cooldown
  - 5 fail → 15min lockout (Supabase default)
  ↓ verify
  → AuthService.verifyOTP(phone, code)
  → Supabase: auth.verifyOTP(phone:, token:, type: .sms)
  ↓ on success
[ProfileSetupView] (if users.display_name is null) OR [GroupOnboardingView]
```

## Sign in with Apple flow

```
[WelcomeView]
  ↓ tap "continue with Apple" (SignInWithAppleButton)
  - Request scopes: .fullName, .email
  ↓ ASAuthorizationAppleIDCredential returned
  → AuthService.signInWithApple(idToken, nonce)
  → Supabase: auth.signInWithIdToken(provider: .apple, idToken:, nonce:)
  ↓ on success, if first time, populate display_name from credential.fullName?.givenName
[ProfileSetupView] OR [GroupOnboardingView]
```

Apple's "hide my email" relay is fine — we don't email users in v1.

## Profile setup (first-time only)

After auth, if `users.display_name` is null, navigate to `ProfileSetupView`.

Fields:
| Field | Required? | Default |
|-------|-----------|---------|
| display_name | Yes | Pre-filled from Apple `givenName` if present |
| avatar | No | None |
| high_school | No | Free text autocomplete from US NCES list (~24K entries, lazy-loaded) |
| grad_year | No | Picker 2020–2035 |
| birthday | No (but recommended) | None — used for age gate |
| age_attestation | Yes | Checkbox: "I am 13 or older" |

On submit → upsert `public.users` row → navigate to group onboarding.

## Auth states (single source of truth at app root)

```swift
@MainActor
@Observable
final class AuthViewModel {
    enum State {
        case loading                  // Reading session from keychain
        case unauthenticated          // Show WelcomeView
        case authenticating           // Show progress
        case profileIncomplete(User)  // Show ProfileSetupView
        case noGroup(User)            // Show GroupOnboardingView
        case active(User)             // Show main app
    }

    private(set) var state: State = .loading
    let supabase: SupabaseClient

    func bootstrap() async { /* load session, fetch user, check memberships */ }
    func sendOTP(phone: String) async throws { ... }
    func verifyOTP(phone: String, code: String) async throws { ... }
    func signInWithApple(idToken: String, nonce: String) async throws { ... }
    func signOut() async throws { ... }
}
```

## Welcome screen

```
[Full-bleed warm gradient: cream → peach]

         connecths
   the place your high school
   friends actually still live

  [  continue with Apple  ]   ← black/white, Apple HIG button
  [  continue with phone  ]   ← outline button, ink color

  by continuing you agree to
  our [terms] and [privacy]
```

Typography: lowercase, soft-serif display for wordmark, SF Pro for body.

## Session persistence

- Supabase SDK persists session in Keychain by default — leave it enabled.
- On cold launch, `AuthViewModel.bootstrap()` reads session, fetches `users` row, decides initial state.
- Token refresh happens automatically via SDK background timer.

## Sign-out

- Clears Supabase session
- Clears local SwiftData cache
- Removes APNs device token (delete row in `device_tokens`)
- Returns to `[WelcomeView]`

## Account deletion (App Store requirement 5.1.1(v))

- Settings → "Delete account" → confirmation alert
- Calls Edge Function `delete-account` which:
  1. Soft-deletes user (sets `users.deleted_at`)
  2. 30-day grace period (user can email support to restore)
  3. After 30 days, hard delete: cascade removes group memberships, posts, reactions, storage objects
- Apple SSO: also call `auth.unlink()` on Apple credential

## Acceptance criteria

- [ ] Phone OTP sends and verifies on a real device with a real number
- [ ] Apple Sign-In works in TestFlight (note: Sign in with Apple requires Apple Developer Program; for free Personal Team, skip this and use phone only during dev)
- [ ] Auto-fill from SMS works on iOS 17+ (`UITextContentType.oneTimeCode`)
- [ ] Country code picker covers at minimum: US, CA, MX, UK
- [ ] 5 failed OTP attempts triggers 15min lockout
- [ ] Sign-out clears all local state and APNs token
- [ ] Welcome screen renders correctly in light + dark mode + Dynamic Type xxxLarge
- [ ] VoiceOver navigation works on all auth screens
- [ ] Apple Sign-In button uses HIG-compliant `SignInWithAppleButton`
- [ ] App reviewer sandbox account works (provide test credentials in App Store Connect)
