# 04 — Groups (F2)

The closed friend group: 5–25 phone-verified members, invite-by-link only, no public discovery.

## Goals
- A user can create a group, share an invite, and have a friend redeem it in < 2 minutes total
- Group full-formation (≥3 members accepted) rate ≥ 60% of inviters
- Zero cross-group data leakage (RLS enforced)

## Onboarding paths (after auth, no group membership)

`GroupOnboardingView` shows two large choices:

1. **"join a group"** → `JoinGroupView` (paste code or open invite link)
2. **"start a new group"** → `CreateGroupView`

`"skip for now"` link below allows entering app with no group (empty state).

## Create group flow

```
[CreateGroupView]
  Step 1: name (1-60 chars, e.g. "the boys")
  Step 2: optional emoji picker
  Step 3: confirm
    → GroupService.createGroup(name, emoji)
    → calls SQL RPC create_group(p_name, p_emoji)
    → returns new group_id, creator added as admin
  Step 4: invite share sheet
    → GroupService.createInvite(group_id)
    → calls SQL RPC create_invite(p_group_id)
    → returns invite_code
    → present UIActivityViewController with pre-loaded text:
      "starting a connecths so we don't all become strangers.
       join: https://connecths.app/i/{code}"
  ↓ skip share or after share
[FeedView] (empty state)
```

## Join group flow (invite code path)

```
[JoinGroupView]
  - Text field for code (case-insensitive, 8 chars)
  - Or "paste link" button to extract code from clipboard
  ↓ submit
  → GroupService.redeemInvite(code)
  → calls SQL RPC redeem_invite(p_code)
  → returns group_id (or throws "group full" / "expired")
  ↓ success
[FeedView] (with group active)
```

## Join group flow (universal link path)

User taps `https://connecths.app/i/{code}` from elsewhere (iMessage, IG, Snapchat).

iOS routing:
1. `apple-app-site-association` config maps `/i/*` to ConnectHS app
2. App is installed → opens directly via `SceneDelegate.scene(_:continue:)`
3. App is NOT installed → web fallback page at `connecths.app/i/{code}` shows App Store link with code in clipboard, then deep-links via universal link after install

In-app handling:
```swift
func handleUniversalLink(_ url: URL) {
    guard url.host == "connecths.app", url.pathComponents.contains("i") else { return }
    guard let code = url.pathComponents.last else { return }

    switch authViewModel.state {
    case .unauthenticated, .loading:
        // Stash code, prompt auth, redeem after auth completes
        pendingInviteCode = code
    case .active(_), .noGroup(_), .profileIncomplete(_):
        Task { await groupService.redeemInvite(code: code) }
    }
}
```

## Group settings

`GroupSettingsView` accessible from feed top bar.

Sections:
- **Header:** group name + emoji (admin-editable inline)
- **Members:** list with avatars + names; tap → kebab menu (admin: remove; everyone: report)
- **Invite:** button "create new invite link" → share sheet
- **Danger zone:** "leave group" with confirmation
  - If user is the only admin and there are other members, force-promote a new admin first

## Member list

```sql
SELECT u.id, u.display_name, u.avatar_url, m.role, m.joined_at
FROM group_memberships m
JOIN users u ON u.id = m.user_id
WHERE m.group_id = $1 AND m.left_at IS NULL
ORDER BY m.role DESC, m.joined_at ASC;
```

## Leave group behavior

- Sets `group_memberships.left_at = NOW()` (does NOT delete the row — preserves post authorship history)
- User loses access to that group's data immediately (RLS evaluates `left_at IS NULL`)
- Other members are NOT notified by default

## Remove member (admin only)

- Same as leave but admin sets the `left_at` for someone else
- Removed user receives a silent push: `"you were removed from {group_name}"`
- Cannot remove the last admin

## Group full state

If 25 members already, `redeem_invite` raises `"Group is full"`. UI shows: `"this group is full (25 max). ask the admin."`

## Empty / cold-start states

User is in a group but no one else has joined yet:
- Feed shows empty state: large `"share a moment anyway — your friends will see it when they join"` card
- After 48h with no other members joining, send push: `"still alone in your group. tap to invite."`

## ViewModels

```swift
@MainActor @Observable
final class GroupViewModel {
    private let service: GroupService
    private(set) var groups: [Group] = []
    private(set) var activeGroupID: UUID?
    private(set) var members: [GroupMember] = []

    func loadMyGroups() async { ... }
    func setActive(_ id: UUID) { ... }
    func createGroup(name: String, emoji: String?) async throws -> UUID { ... }
    func createInvite(groupID: UUID) async throws -> String { ... }
    func redeemInvite(code: String) async throws -> UUID { ... }
    func leaveGroup(_ id: UUID) async throws { ... }
    func removeMember(userID: UUID, groupID: UUID) async throws { ... }
}
```

## Universal Link config

`apple-app-site-association` (host on `connecths.app/.well-known/`):

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["TEAMID.com.alexander.connecths"],
        "components": [
          { "/": "/i/*", "comment": "Group invite redemption" }
        ]
      }
    ]
  }
}
```

Add Associated Domains capability in Xcode: `applinks:connecths.app`.

## Acceptance criteria

- [ ] Create group + first member is added as admin atomically
- [ ] Invite codes are 8 chars, URL-safe, unguessable (high entropy)
- [ ] Invites expire after 7 days
- [ ] Universal link `https://connecths.app/i/{code}` opens app and triggers redeem
- [ ] If user is unauthenticated when tapping invite link, code is stashed and redeemed after auth
- [ ] Group full (25 members) returns clear error — does NOT redeem
- [ ] Already-a-member redeem is idempotent (no-op, returns group_id)
- [ ] Member list ordered admins first, then by joined_at
- [ ] Leave group preserves post authorship (post still shows author name)
- [ ] Last admin protection: cannot leave if only admin with members
- [ ] Removed user cannot read group data (RLS blocks)
- [ ] Two test users in different groups cannot read each other's posts (cross-group leak test)
