import Foundation

struct FriendGroup: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var emoji: String?
    let createdBy: UUID
    var memberLimit: Int
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, emoji
        case createdBy = "created_by"
        case memberLimit = "member_limit"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

enum GroupMemberRole: String, Codable, Sendable {
    case admin
    case member
}

struct GroupMembership: Codable, Identifiable, Sendable {
    let id: UUID
    let groupId: UUID
    let userId: UUID
    var role: GroupMemberRole
    let joinedAt: Date
    var leftAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case userId = "user_id"
        case role
        case joinedAt = "joined_at"
        case leftAt = "left_at"
    }
}

/// Flat row returned by `list_group_members` — joins membership with user
/// profile so the settings list can render avatars + display names without
/// a follow-up fetch per member.
struct GroupMember: Codable, Identifiable, Hashable, Sendable {
    let userId: UUID
    let displayName: String
    let avatarUrl: String?
    let role: GroupMemberRole
    let joinedAt: Date

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case role
        case joinedAt = "joined_at"
    }
}

enum InviteStatus: String, Codable, Sendable {
    case pending
    case accepted
    case expired
    case revoked
}

struct GroupInvite: Codable, Identifiable, Sendable {
    let id: UUID
    let groupId: UUID
    let inviteCode: String
    let createdBy: UUID
    var maxUses: Int?
    var usesCount: Int
    let expiresAt: Date
    var status: InviteStatus
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case inviteCode = "invite_code"
        case createdBy = "created_by"
        case maxUses = "max_uses"
        case usesCount = "uses_count"
        case expiresAt = "expires_at"
        case status
        case createdAt = "created_at"
    }
}
