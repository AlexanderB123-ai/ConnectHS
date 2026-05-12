# 01 — Architecture

## Stack summary

### iOS client
| Layer | Choice |
|-------|--------|
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI (UIKit only for AVFoundation hosts) |
| Min iOS | 17.0 |
| Camera | `AVCaptureMultiCamSession` |
| Widget | WidgetKit (small + medium) + App Group |
| Local storage | SwiftData (cache only) |
| Networking | `supabase-swift` SDK 2.x |
| Async | Swift Concurrency (`async`/`await`, `Actor`) |
| Push | APNs via `UNUserNotificationCenter` |
| Analytics | PostHog (privacy-friendly) |
| Crash reporting | Sentry |

### Backend
| Layer | Choice |
|-------|--------|
| Platform | Supabase (Pro plan) |
| Database | Postgres 15 with Row-Level Security |
| Auth | Supabase Auth (Phone OTP via Twilio + Sign in with Apple OIDC) |
| Storage | Supabase Storage (S3-compatible, signed URLs) |
| Realtime | Supabase Realtime (Postgres LISTEN/NOTIFY) |
| Background jobs | Edge Functions (Deno) + `pg_cron` |
| CDN | Supabase Storage CDN (Cloudflare) |

## Architecture pattern: MVVM

```
View (SwiftUI)
   │ binds to
   ▼
ViewModel (@Observable, @MainActor)
   │ calls
   ▼
Service (e.g. PostService, AuthService)
   │ uses
   ▼
SupabaseClient (singleton)
```

- **View:** dumb, declarative SwiftUI. Reads VM state, fires VM intents.
- **ViewModel:** `@Observable` class, `@MainActor` if it touches UI. Holds state, exposes intent methods.
- **Service:** stateless functions or actors that call Supabase. Returns Codable models.
- **Models:** plain structs, `Codable`, snake_case `CodingKeys` matching Postgres columns.

## Data flow example (posting a moment)

```
CameraView
   ↓ user taps shutter
CameraViewModel.captureAndPost()
   ↓
   1. AVFoundation captures (front, back) UIImages
   2. Compress to WebP (quality 80, max 1080px)
   3. PostService.upload(front, back, caption, groupID)
   4. PostService:
       a. Get a UUID for the new post
       b. Upload front.webp + back.webp to Supabase Storage at posts/{id}/
       c. Insert row in `posts` table
   5. ViewModel updates state, navigates back to feed
   6. Realtime subscription fires on other group members' devices
```

## Networking & caching

- **Source of truth:** always Supabase. Local cache (SwiftData) is for offline-friendly UX only.
- **Image cache:** disk + memory cache via `ImagePipeline` actor. Keyed by storage path. Signed URLs cached 6 hours.
- **Realtime:** subscribe to `posts` INSERT events filtered by user's group IDs. On event, append to local feed model + reload widget timeline.
- **Retries:** 3 attempts with exponential backoff (1s, 2s, 4s). All Supabase calls have 10s timeout.

## App Group (shared between app + widget)

Bundle ID: `group.com.alexander.connecths.shared`

Shared via `UserDefaults(suiteName:)` and `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`:

- Latest post per group (id, author_name, posted_at, image thumbnail base64)
- User's auth token (refresh in background to keep widget alive)
- Notification settings

## Routing & deep links

URL scheme: `connecths://`

| Path | Destination |
|------|-------------|
| `connecths://camera` | Camera capture screen |
| `connecths://post/{id}` | Post detail |
| `connecths://memory/{id}` | Memory detail |
| `connecths://group/{id}` | Group settings |

Universal link domain: `connecths.app`
- `https://connecths.app/i/{code}` → group invite redemption

`apple-app-site-association` JSON config lives at `connecths.app/.well-known/apple-app-site-association`.

## State machine — auth states

```swift
enum AuthState {
    case unauthenticated     // Show welcome
    case authenticating      // OTP/Apple in progress
    case profileIncomplete   // Auth'd, no display_name
    case noGroup            // Profile complete, no memberships → onboarding
    case active             // ≥ 1 group → main app
}
```

All routing decisions flow from this single state, owned by `AuthViewModel` at the app root.

## Performance targets

| Metric | Target |
|--------|--------|
| Cold launch → first paint | < 1.5s on iPhone 12+ |
| Feed load (cached) | < 500ms |
| Feed load (cold) | < 2s |
| Widget render | < 1.5s |
| Camera shutter → confirmation | < 300ms |
| Photo upload (LTE, 1080p pair) | < 3s |

## Quality bar

- Crash-free sessions ≥ 99.5%
- VoiceOver labels on every interactive element
- Dynamic Type up to xxxLarge
- Min tap target 44x44pt
- WCAG AA contrast (4.5:1 body)
- SwiftLint zero warnings
- ≥ 60% test coverage on Models + Services
- UI tests for: auth, group create, group join, post, react

## Folder structure (canonical)

```
ConnectHS/
├── App/
│   ├── ConnectHSApp.swift       app entry, root routing
│   ├── AppDelegate.swift        push registration
│   └── RootView.swift           switches on AuthState
├── Features/
│   ├── Auth/                    welcome, OTP, Apple SSO, profile setup
│   ├── Group/                   create, join, settings, members
│   ├── Camera/                  dual-camera capture
│   ├── Feed/                    today's feed view
│   ├── Archive/                 permanent timeline browser
│   ├── Memory/                  on-this-day resurface
│   └── Profile/                 settings, account
├── Models/
│   ├── User.swift
│   ├── Group.swift
│   ├── Post.swift
│   ├── Reaction.swift
│   └── Memory.swift
├── Services/
│   ├── SupabaseClient.swift     singleton
│   ├── AuthService.swift
│   ├── PostService.swift
│   ├── GroupService.swift
│   ├── ReactionService.swift
│   ├── MemoryService.swift
│   ├── PushService.swift
│   └── ImagePipeline.swift      compress, cache, upload
├── Storage/
│   └── SwiftDataModels.swift    cache models
├── Shared/
│   ├── Components/              reusable SwiftUI views
│   ├── DesignTokens.swift       colors, typography, spacing
│   └── Extensions/
└── Resources/
    ├── Assets.xcassets
    └── Localizable.xcstrings

ConnectHSWidget/                 widget extension target
├── ConnectHSWidget.swift
├── Provider.swift
└── WidgetViews.swift

Shared/                          shared code (app + widget)
├── SharedDefaults.swift
├── SharedImageCache.swift
└── KeychainHelper.swift

ConnectHSTests/
ConnectHSUITests/

supabase/
├── migrations/                  versioned SQL
├── functions/                   Edge Functions (Deno/TS)
│   ├── memory-engine/
│   ├── send-push/
│   ├── invite-redeem/
│   ├── process-upload/
│   └── widget-payload/
└── seed.sql

docs/
└── PRD.md                       full reference (read-only)

spec/                            per-feature briefs (this folder)
decisions.md                     append-only ADR log
CLAUDE.md                        agent rules
.aiexclude                       blocks .env, secrets/
```
