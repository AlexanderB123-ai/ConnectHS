# 08 — Push Notifications (F8)

APNs-based push for: daily prompts, new posts, memory resurfaces, reactions.

## Goals
- Tapping any push opens the correct deep-link target, even from cold start
- No spam — max 5 pushes per user per day across all groups
- Quiet hours respected (default 22:00 – 08:00 user-local)

## Notification types

| Kind | Title | Body | Deep link | Throttle |
|------|-------|------|-----------|----------|
| `daily_prompt` | `⏰ time to connecths` | `2 hours to share today's moment` | `connecths://camera` | 1/day |
| `new_post` | `{author} just posted` | optional caption preview | `connecths://post/{post_id}` | bundled, max 3/day |
| `memory_resurface` | `📸 memory from {n}yr ago` | `you and {name} on this day` | `connecths://memory/{post_id}` | 1/day |
| `reaction_received` | `{name} reacted {emoji} to your moment` | (none) | `connecths://post/{post_id}` | bundled, max 5/day |
| `group_invite_accepted` | `{name} joined {group}` | (none) | `connecths://group/{group_id}` | per event |

## Delivery rules

1. **Bundle** — same group + same kind within 5 min collapse via `thread-id: "group-{group_id}"`
2. **Quiet hours** — `notification_settings.daily_prompt_window_start/end` enforced server-side
3. **Daily cap** — max 5 pushes per user per day, prioritized: memory > daily_prompt > reaction > new_post
4. **Respect settings** — check `notification_settings.{kind}_enabled` before sending

## Edge Function: `send-push`

Generic APNs dispatcher used by all other functions.

```typescript
// supabase/functions/send-push/index.ts
import { serve } from "https://deno.land/std/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { JWT } from "https://deno.land/x/djwt/mod.ts"

interface PushRequest {
  user_id: string
  title: string
  body: string
  deep_link: string
  thread_id?: string
}

serve(async (req) => {
  const { user_id, title, body, deep_link, thread_id } = await req.json() as PushRequest

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  )

  // Get device tokens for user
  const { data: tokens } = await supabase
    .from("device_tokens")
    .select("apns_token")
    .eq("user_id", user_id)

  if (!tokens || tokens.length === 0) return new Response("no devices")

  // Build APNs JWT (cached for ~1 hour)
  const apnsToken = await buildAPNsJWT()

  const payload = {
    aps: {
      alert: { title, body },
      sound: "default",
      "thread-id": thread_id,
    },
    deep_link,
  }

  const isProduction = Deno.env.get("APNS_ENV") === "production"
  const host = isProduction ? "api.push.apple.com" : "api.sandbox.push.apple.com"

  for (const t of tokens) {
    const response = await fetch(`https://${host}/3/device/${t.apns_token}`, {
      method: "POST",
      headers: {
        "authorization": `bearer ${apnsToken}`,
        "apns-topic": Deno.env.get("APNS_BUNDLE_ID")!,
        "apns-push-type": "alert",
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    })

    // Handle 410 Gone → token is dead, delete it
    if (response.status === 410) {
      await supabase.from("device_tokens").delete().eq("apns_token", t.apns_token)
    }
  }

  return new Response("ok")
})

async function buildAPNsJWT(): Promise<string> {
  const teamID = Deno.env.get("APNS_TEAM_ID")!
  const keyID = Deno.env.get("APNS_KEY_ID")!
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY")!  // .p8 contents

  // Build ES256 JWT, valid for 1 hour
  const jwt = await JWT.create(
    { alg: "ES256", kid: keyID },
    { iss: teamID, iat: Math.floor(Date.now() / 1000) },
    privateKey
  )
  return jwt
}
```

## Edge Function: `dispatch-daily-prompt`

Cron schedule: every 15 minutes, between 10:00 and 22:00 in each user's timezone.

```typescript
// Logic:
// For each active group:
//   - Check if today's prompt has been sent (daily_prompts row exists)
//   - If not, pick a randomized time in the group's typical window
//   - Insert into daily_prompts (UNIQUE constraint on group_id + prompt_date prevents dupes)
//   - Fan out send-push to every member
```

Title: `"⏰ time to connecths"` — Body: `"2 hours to share today's moment"` — Deep link: `connecths://camera`

## Edge Function: `dispatch-new-post`

Trigger: Postgres `pg_net` webhook on `posts` INSERT.

```typescript
// For each member of the group (except the author):
//   - Check notification_settings.new_post_enabled
//   - Send push: "{author_name} just posted"
//   - Body: caption?.slice(0, 60) ?? ""
//   - Deep link: connecths://post/{post_id}
```

## iOS client: APNs registration

```swift
// AppDelegate.swift
import UIKit
import UserNotifications

@main
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { await requestNotificationAuthorization() }
        return true
    }

    func requestNotificationAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        } catch {
            print("Notification auth failed:", error)
        }
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            try await PushService.shared.registerToken(token)
        }
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Silent push handler (e.g. for widget refresh)
        completionHandler(.newData)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Tap handler
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        if let deepLink = userInfo["deep_link"] as? String,
           let url = URL(string: deepLink) {
            await DeepLinkRouter.shared.handle(url)
        }
    }

    // Foreground display
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}
```

## PushService

```swift
@MainActor
final class PushService {
    static let shared = PushService()
    private let supabase: SupabaseClient

    func registerToken(_ token: String) async throws {
        guard let userID = supabase.auth.currentUser?.id else { return }
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        try await supabase.from("device_tokens")
            .upsert([
                "user_id": userID,
                "apns_token": token,
                "device_id": deviceID,
                "app_version": appVersion,
                "last_seen_at": ISO8601DateFormatter().string(from: Date()),
            ], onConflict: "user_id,device_id")
            .execute()
    }

    func unregisterToken() async throws {
        guard let userID = supabase.auth.currentUser?.id else { return }
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? ""
        try await supabase.from("device_tokens")
            .delete()
            .eq("user_id", userID)
            .eq("device_id", deviceID)
            .execute()
    }
}
```

## Permission UX

Don't ask for notifications upfront. Ask at the **first natural moment**:

- After the user joins or creates a group (`GroupOnboardingView` completion)
- Sheet: `"turn on notifications so you don't miss the daily moment"` with `[allow]` / `[not now]` buttons
- If denied, never re-prompt. Show in-app banner once: `"enable notifications in settings to get daily moments"` with deep link to settings.

## Apple Push Notification service setup (post-Apple Developer enrollment)

Steps to wire up APNs (do these on June 16, 2026 after enrolling):

1. Apple Developer portal → Keys → Create APNs Key (`.p8` file)
2. Download `.p8`, save Key ID + Team ID
3. Store as Supabase secrets:
   - `APNS_TEAM_ID`
   - `APNS_KEY_ID`
   - `APNS_PRIVATE_KEY` (paste contents of `.p8`)
   - `APNS_BUNDLE_ID` (e.g. `com.alexander.connecths`)
   - `APNS_ENV` (`sandbox` or `production`)
4. Enable Push Notifications capability in Xcode
5. Test from Xcode: `Window → Devices and Simulators → Send Test Notification`

## Acceptance criteria

- [ ] APNs token registers on app foreground after notification permission granted
- [ ] Token rotation handled (upsert on `(user_id, device_id)`)
- [ ] 410 Gone responses delete the dead token
- [ ] `daily_prompt` notification fires at the scheduled randomized time
- [ ] `new_post` push fires within 30s of post insert (test via Postgres webhook)
- [ ] `memory_resurface` push fires when memories exist on a date
- [ ] `reaction_received` push fires when someone reacts to user's post
- [ ] All deep links resolve to correct in-app destinations (test cold-start case)
- [ ] Quiet hours respected — no push between 22:00 and 08:00 unless user opts in
- [ ] Daily cap of 5 enforced server-side
- [ ] Notification settings (per-kind toggles) honored
- [ ] Permission UX: asked once at natural moment, never re-prompted
- [ ] Sign-out removes APNs token from `device_tokens`
