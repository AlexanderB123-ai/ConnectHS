# 07 — Home-Screen Widget (F6)

The ambient-presence feature. Shows the latest moment from the user's group on their home screen — no app-open required.

## Goals
- Widget renders within 1.5s of being added
- Updates within ~5 minutes of a new post (system-policy permitting)
- Tap → deep link directly to that post

## Sizes (v1)

| Size | Pixel approx | Content |
|------|--------------|---------|
| Small (`systemSmall`) | 155x155 | Latest post: back image + small front inset |
| Medium (`systemMedium`) | 329x155 | Same + author first name + relative time overlay |

Large size deferred to v1.5 (gallery of last 4 posts).

Lock-screen widget: small layout reused.
StandBy mode (iOS 17+): full-screen latest post.

## Widget extension target

Add new target in Xcode: **Widget Extension**, named `ConnectHSWidget`. Configure App Group: `group.com.alexander.connecths.shared`.

### App Group shared container

The app writes the latest post payload into the App Group container so the widget can render without needing network or auth:

```swift
// Shared/SharedDefaults.swift (used by both app and widget targets)
import Foundation

enum SharedKeys {
    static let appGroupID = "group.com.alexander.connecths.shared"
    static let latestPostKey = "latestPost"
}

struct LatestPostPayload: Codable {
    let postID: UUID
    let groupID: UUID
    let groupName: String
    let groupEmoji: String?
    let authorName: String
    let postedAt: Date
    let backImageThumbBase64: String  // 256x256 webp, base64
    let frontImageThumbBase64: String
}

extension LatestPostPayload {
    static func read() -> LatestPostPayload? {
        guard let defaults = UserDefaults(suiteName: SharedKeys.appGroupID),
              let data = defaults.data(forKey: SharedKeys.latestPostKey),
              let payload = try? JSONDecoder().decode(LatestPostPayload.self, from: data)
        else { return nil }
        return payload
    }

    func write() throws {
        guard let defaults = UserDefaults(suiteName: SharedKeys.appGroupID) else {
            throw NSError(domain: "AppGroup", code: -1)
        }
        let data = try JSONEncoder().encode(self)
        defaults.set(data, forKey: SharedKeys.latestPostKey)
    }
}
```

### Update flow

```
New post inserted (own post OR realtime event for group post)
  ↓
App writes LatestPostPayload to App Group
  ↓
WidgetCenter.shared.reloadAllTimelines()
  ↓
Widget reads payload, re-renders
```

## Widget code

```swift
// ConnectHSWidget/ConnectHSWidget.swift
import WidgetKit
import SwiftUI

struct ConnectHSWidget: Widget {
    let kind: String = "ConnectHSWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("connecths")
        .description("see the latest moment from your group")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        let payload = LatestPostPayload.read()
        completion(WidgetEntry(date: Date(), payload: payload))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let payload = LatestPostPayload.read()
        let entry = WidgetEntry(date: Date(), payload: payload)
        // Refresh every 30 min as fallback (app push triggers immediate refresh)
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let payload: LatestPostPayload?
}

struct WidgetView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let payload = entry.payload {
            ZStack {
                // Background: blurred back image
                if let img = decodeImage(payload.backImageThumbBase64) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 30)
                }

                // Foreground: full back image
                if let img = decodeImage(payload.backImageThumbBase64) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(8)
                }

                // Front image inset (top-right)
                VStack {
                    HStack {
                        Spacer()
                        if let img = decodeImage(payload.frontImageThumbBase64) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 1))
                                .padding(12)
                        }
                    }
                    Spacer()
                }

                // Medium-only: author + time overlay
                if family == .systemMedium {
                    VStack {
                        Spacer()
                        HStack {
                            Text("\(payload.authorName) · \(payload.postedAt.relative)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.5))
                                .clipShape(Capsule())
                                .padding(12)
                            Spacer()
                        }
                    }
                }
            }
            .widgetURL(URL(string: "connecths://post/\(payload.postID)"))
        } else {
            // Empty state
            ZStack {
                Color(red: 0.98, green: 0.97, blue: 0.94) // cream
                VStack(spacing: 8) {
                    Text("📷")
                    Text("no moments yet")
                        .font(.caption)
                }
            }
        }
    }

    private func decodeImage(_ base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }
}
```

## Widget refresh triggers

1. **App-side:** when a new post arrives (via realtime subscription) or user creates one, the app calls:
   ```swift
   WidgetCenter.shared.reloadAllTimelines()
   ```
2. **System-side:** the `Timeline.policy: .after(date)` gives a fallback refresh every 30 minutes

## Memory budget

- Widget process has a strict memory budget (~30 MB)
- Use 256x256 thumbnails ONLY (not full 1080px)
- Cache decoded UIImages in memory; free on `didReceiveMemoryWarning`

## Empty / unauthenticated state

If no payload exists in App Group (user hasn't signed in or has no group):

- Cream background
- Camera emoji + "no moments yet" text
- Tap → opens app to onboarding

## Acceptance criteria

- [ ] Widget extension target builds and runs
- [ ] App Group entitlement added to both app and widget targets
- [ ] Small widget renders latest post within 1.5s of add
- [ ] Medium widget shows author + time
- [ ] Tap on widget opens app to `connecths://post/{post_id}` and lands on correct PostDetailView
- [ ] Posting a moment in the app updates the widget within 5s (test with WidgetCenter reload)
- [ ] Realtime new-post event from another user updates widget within 5s
- [ ] Empty state shows when user has no group / no posts
- [ ] Widget renders correctly in light + dark mode
- [ ] Memory: widget never crashes due to OOM (use thumbnails, not full images)
- [ ] Lock-screen widget (small) reuses same layout
- [ ] StandBy mode shows full-screen latest post
