# 05 — Camera, Feed, Archive, Reactions (F3, F4, F7)

The core daily loop: capture a dual-camera moment, see it (and friends') in today's feed, react, browse the permanent archive.

## Goals
- Camera shutter → posted in < 10 seconds
- Front + back capture synchronized within < 100ms
- Feed initial load < 500ms (cached) / < 2s (cold)
- Archive scrolls smoothly with 1000+ posts
- Posts NEVER expire (the anti-BeReal feature)

---

## Part 1: Dual-camera capture (F3)

### Tech: AVFoundation `AVCaptureMultiCamSession`

True simultaneous front + back capture. Required device: iPhone XS / XR or newer.

```swift
@MainActor
final class DualCameraSession {
    private let session = AVCaptureMultiCamSession()
    private let frontOutput = AVCapturePhotoOutput()
    private let backOutput = AVCapturePhotoOutput()

    func configure() throws {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            throw CameraError.multiCamUnsupported
        }
        session.beginConfiguration()
        // ... add both cameras as inputs, both outputs
        session.commitConfiguration()
    }

    func capture() async throws -> (front: UIImage, back: UIImage) {
        // Trigger both AVCapturePhotoOutput.capturePhoto() simultaneously
        // Return (front, back) tuple
    }
}
```

**Fallback for older devices:** sequential capture (back first, then front, ≤500ms gap). Show small `"sync capture not available on this device"` info icon.

### CameraView layout

```
┌─────────────────────────────────────┐
│ ✕                                ⟲ │  ← X to close, ⟲ to flip primary
│                                     │
│         [back camera preview]       │
│                                     │
│                            ┌──────┐ │
│                            │front │ │  ← draggable inset, default top-right
│                            │preview│
│                            └──────┘ │
│                                     │
│                                     │
│                                     │
│              ⏺  shutter             │  ← large circular shutter
│                                     │
└─────────────────────────────────────┘
```

- Back camera fills entire screen
- Front camera is ~120pt rounded rect, draggable (long-press → pan)
- Position persists across session

### Capture flow

```
User taps shutter
  ↓
AVCaptureMultiCamSession captures both
  ↓
[CapturePreviewView]
  - Show stacked preview with current layout
  - Caption text field (optional, 140 char limit)
  - "retake" / "post" buttons
  ↓ tap "post"
PostService.upload(front: UIImage, back: UIImage, caption: String?, groupID: UUID)
  1. Generate post UUID client-side
  2. Compress front + back to WebP, quality 80, max 1080px
  3. Upload to posts/{post_id}/front.webp and back.webp
  4. Insert posts row via supabase.from("posts").insert(...)
  ↓ success
Toast: "posted 🎉" → return to FeedView
```

### Permission handling

- First time: trigger `AVCaptureDevice.requestAccess(for: .video)`
- Denied: show friendly screen with "open settings" deep link to `UIApplication.openSettingsURLString`

### Background upload resilience

- Use `URLSession.background` configuration so upload survives app backgrounding
- If upload fails (network), keep image in local cache + show retry banner on feed

---

## Part 2: Today's Feed (F3 viewing)

### Layout

```
┌─────────────────────────────────────┐
│ [🌊 the boys ▼]                  👤 │  ← group selector + profile
├─────────────────────────────────────┤
│ ┌─────────────────────────────────┐ │
│ │ 📸 1 year ago today  >          │ │  ← Memory ribbon (if any)
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│                                     │
│  [📸 share today's moment]          │  ← if user hasn't posted, big CTA
│                                     │
├─────────────────────────────────────┤
│  ┌──────┐  ┌──────┐  ┌──────┐      │
│  │ post │  │ post │  │ post │      │  ← 3-col grid of today's posts
│  │ alex │  │sarah │  │ ben  │      │
│  └──────┘  └──────┘  └──────┘      │
│  ┌──────┐  ┌──────┐                 │
│  │ post │  │ post │                 │
│  └──────┘  └──────┘                 │
└─────────────────────────────────────┘
```

### Data fetch

```swift
// On view appear
Task {
    let feed = try await supabase.rpc("get_feed", params: [
        "p_group_id": activeGroupID,
        "p_date": today
    ]).execute()
}
```

### Realtime subscription

```swift
let channel = supabase.realtimeV2.channel("posts:\(groupID)")
let postsInsert = channel.postgresChange(InsertAction.self,
    schema: "public", table: "posts",
    filter: "group_id=eq.\(groupID)")

Task {
    for await change in postsInsert {
        // Append new post to feed model
        // Reload widget timeline
        WidgetCenter.shared.reloadAllTimelines()
    }
}
await channel.subscribe()
```

### States

- `loading` → skeleton grid
- `empty` (no friends posted today) → `"no moments yet today. be first."`
- `hasPosts` → grid
- `error` → retry button

### Pull-to-refresh

`.refreshable { await viewModel.reload() }`

---

## Part 3: Post detail view

Tapping a feed thumbnail opens full-screen post view.

```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│         [BACK IMAGE - full]         │
│                       ┌──────┐      │
│                       │front │      │
│                       └──────┘      │
│                                     │
│                                     │
├─────────────────────────────────────┤
│ 🟢 alex · 2h ago                    │
│ "morning at the diner"              │
│                                     │
│ [❤️ 3] [🔥 1] [😂] [😮] [😢] [👍]   │  ← reaction bar
│                                     │
│ viewed by 7 of 12 (only to author)  │
└─────────────────────────────────────┘
```

### Behavior

- On open: fire `mark_viewed(p_post_id: post.id)` RPC
- Reaction tap: optimistic UI update, then `toggle_reaction(p_post_id, p_reaction)` RPC
- Long-press emoji in bar → list of reactors
- Swipe up: next post; swipe down: dismiss
- Caption is selectable (long-press copy)

### Reaction set (locked for v1)

| Emoji | Code | Meaning |
|-------|------|---------|
| ❤️ | `heart` | "I love this" |
| 🔥 | `fire` | "this is fire" |
| 😂 | `laugh` | "lol" |
| 😮 | `wow` | "omg" |
| 😢 | `sad` | "miss u" |
| 👍 | `thumbs_up` | generic ack |

---

## Part 4: Archive (F4) — permanent timeline

The killer feature vs BeReal. Every moment ever, browsable.

### Layout

```
┌─────────────────────────────────────┐
│  [archive]            [☰ filter]    │
├─────────────────────────────────────┤
│  March 2026                         │  ← sticky month header
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌─────┐│
│  │ 🌊   │ │ 🌊   │ │ 🌊   │ │ ... ││
│  └──────┘ └──────┘ └──────┘ └─────┘│
│  February 2026                      │
│  ┌──────┐ ┌──────┐ ...              │
│  └──────┘ └──────┘                  │
│  January 2026                       │
│  ...                                │
└─────────────────────────────────────┘
```

### Implementation

- `LazyVGrid` with section headers
- Pagination: load 30 days at a time as user scrolls
- Filter chip: `"only my posts"` toggle (simple `WHERE author_id = me`)
- Tap a thumbnail → post detail

### Empty state (new group, < 1 week)

`"your archive will fill up. promise."`

### Deleted posts

Show as a `"removed"` placeholder rather than vanishing — preserves timeline integrity.

---

## Part 5: ViewModels

```swift
@MainActor @Observable
final class FeedViewModel {
    enum State { case loading, empty, hasPosts([Post]), error(Error) }
    private(set) var state: State = .loading
    private(set) var hasPostedToday = false
    private(set) var todaysMemories: [Memory] = []

    private let postService: PostService
    private let realtimeChannel: RealtimeChannelV2?

    func load(groupID: UUID) async { ... }
    func subscribeToRealtime(groupID: UUID) async { ... }
    func reload() async { ... }
}

@MainActor @Observable
final class CameraViewModel {
    enum CaptureState { case idle, capturing, previewing(front: UIImage, back: UIImage), uploading, success, failed(Error) }
    private(set) var captureState: CaptureState = .idle
    private(set) var caption: String = ""
    private(set) var frontInsetPosition: CGPoint = .topRight

    func capture() async { ... }
    func post(groupID: UUID) async { ... }
    func retake() { captureState = .idle }
}

@MainActor @Observable
final class ArchiveViewModel {
    private(set) var sections: [ArchiveSection] = []  // grouped by month
    private(set) var isLoadingMore = false
    private(set) var filterMineOnly = false

    func loadInitial(groupID: UUID) async { ... }
    func loadMore() async { ... }
}
```

## Acceptance criteria

### Camera
- [ ] Dual-camera capture works on iPhone XS+ via `AVCaptureMultiCamSession`
- [ ] Sequential fallback works on older devices
- [ ] Front camera inset is draggable, position persists
- [ ] Capture-to-confirm < 300ms
- [ ] Permission denied shows friendly screen with settings link
- [ ] Background upload survives app backgrounding (URLSession.background)
- [ ] Caption respects 140-char limit (UI prevents over)
- [ ] One post per user per group per day enforced (DB unique index)

### Feed
- [ ] `get_feed` RPC returns posts ordered newest-first
- [ ] Realtime subscription pushes new posts in within 5s
- [ ] Pull-to-refresh works
- [ ] Empty state copy displays correctly
- [ ] Group selector switches feeds (when v2 multi-group ships, scaffolding ready)
- [ ] Memory ribbon appears if today has past-year content

### Post detail
- [ ] `mark_viewed` fires on open (idempotent)
- [ ] Reaction tap updates UI optimistically before server confirms
- [ ] Long-press emoji shows reactor list
- [ ] Swipe-down dismisses
- [ ] Author can see view count; non-authors cannot

### Archive
- [ ] Loads first 30-day window in < 2s
- [ ] Infinite scroll loads next 30-day window seamlessly
- [ ] Month headers stick on scroll
- [ ] Smooth scrolling at 1000+ posts (use LazyVGrid)
- [ ] "Only my posts" filter works
- [ ] Deleted posts show as `removed` placeholder
