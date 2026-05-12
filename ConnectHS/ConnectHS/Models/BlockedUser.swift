import Foundation

/// Row returned by `list_my_blocked_users()`. Each row is a user the caller
/// has blocked, plus when they blocked them, for the manage-blocks UI in
/// ProfileView.
struct BlockedUser: Codable, Identifiable, Hashable, Sendable {
    let userId: UUID
    let displayName: String
    let avatarUrl: String?
    let blockedAt: Date

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case blockedAt = "blocked_at"
    }
}
