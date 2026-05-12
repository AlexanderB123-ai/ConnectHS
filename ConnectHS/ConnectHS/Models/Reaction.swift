import Foundation

enum ReactionType: String, Codable, Sendable, CaseIterable {
    case heart
    case fire
    case laugh
    case wow
    case sad
    case thumbsUp = "thumbs_up"

    var emoji: String {
        switch self {
        case .heart: return "\u{2764}\u{FE0F}"
        case .fire: return "\u{1F525}"
        case .laugh: return "\u{1F602}"
        case .wow: return "\u{1F62E}"
        case .sad: return "\u{1F622}"
        case .thumbsUp: return "\u{1F44D}"
        }
    }

    /// VoiceOver label for the reaction (translatable). Maps to catalog
    /// keys `reaction.label.{rawValue}`.
    var accessibilityLabelKey: String {
        "reaction.label.\(rawValue)"
    }
}

struct Reaction: Codable, Identifiable, Sendable {
    let id: UUID
    let postId: UUID
    let userId: UUID
    let reaction: ReactionType
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case reaction
        case createdAt = "created_at"
    }
}

/// Row returned by `list_post_reactors(post_id, reaction)` — reactor profile
/// flattened with the reaction timestamp so the long-press sheet renders
/// without a follow-up users fetch.
struct PostReactor: Codable, Identifiable, Hashable, Sendable {
    let userId: UUID
    let displayName: String
    let avatarUrl: String?
    let reactedAt: Date

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case reactedAt = "reacted_at"
    }
}
