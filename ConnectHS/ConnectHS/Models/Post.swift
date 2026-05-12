import Foundation

enum MomentKind: String, Codable, Sendable {
    case dualPhoto = "dual_photo"
}

struct Post: Codable, Identifiable, Sendable {
    let id: UUID
    let groupId: UUID
    let authorId: UUID
    let kind: MomentKind
    let frontImagePath: String
    let backImagePath: String
    var caption: String?
    let promptDate: String
    let promptTime: Date
    let postedAt: Date
    var isLate: Bool
    var isArchived: Bool
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case authorId = "author_id"
        case kind
        case frontImagePath = "front_image_path"
        case backImagePath = "back_image_path"
        case caption
        case promptDate = "prompt_date"
        case promptTime = "prompt_time"
        case postedAt = "posted_at"
        case isLate = "is_late"
        case isArchived = "is_archived"
        case deletedAt = "deleted_at"
    }
}

struct FeedPost: Codable, Identifiable, Hashable, Sendable {
    let postId: UUID
    let authorId: UUID
    let authorName: String
    let authorAvatar: String?
    let frontImagePath: String
    let backImagePath: String
    let caption: String?
    let postedAt: Date
    let isLate: Bool
    let viewCount: Int
    let reactionSummary: [String: Int]?

    var id: UUID { postId }

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case authorId = "author_id"
        case authorName = "author_name"
        case authorAvatar = "author_avatar"
        case frontImagePath = "front_image_path"
        case backImagePath = "back_image_path"
        case caption
        case postedAt = "posted_at"
        case isLate = "is_late"
        case viewCount = "view_count"
        case reactionSummary = "reaction_summary"
    }
}

/// Same shape as `FeedPost` plus `promptDate` for grouping the archive grid by month.
struct ArchivePost: Codable, Identifiable, Hashable, Sendable {
    let postId: UUID
    let authorId: UUID
    let authorName: String
    let authorAvatar: String?
    let frontImagePath: String
    let backImagePath: String
    let caption: String?
    let promptDate: String
    let postedAt: Date
    let isLate: Bool
    let viewCount: Int
    let reactionSummary: [String: Int]?

    var id: UUID { postId }

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case authorId = "author_id"
        case authorName = "author_name"
        case authorAvatar = "author_avatar"
        case frontImagePath = "front_image_path"
        case backImagePath = "back_image_path"
        case caption
        case promptDate = "prompt_date"
        case postedAt = "posted_at"
        case isLate = "is_late"
        case viewCount = "view_count"
        case reactionSummary = "reaction_summary"
    }

    var asFeedPost: FeedPost {
        FeedPost(
            postId: postId,
            authorId: authorId,
            authorName: authorName,
            authorAvatar: authorAvatar,
            frontImagePath: frontImagePath,
            backImagePath: backImagePath,
            caption: caption,
            postedAt: postedAt,
            isLate: isLate,
            viewCount: viewCount,
            reactionSummary: reactionSummary
        )
    }
}

/// Pushed onto the navigation stack when the user opens a post. Carries the
/// surrounding feed (or archive section) and the id the user tapped, so
/// PostDetailView can land on that page and let them swipe horizontally
/// between siblings — spec/05's "swipe up next" affordance.
struct PostCarousel: Hashable, Sendable {
    let posts: [FeedPost]
    let initialId: UUID
}

/// A single post resolved via `get_post(p_post_id)` for deep-link hydration.
/// Carries enough metadata (group + promptDate) to switch group context when
/// the deep-linked post lives in a group other than the one currently shown
/// in the feed.
struct DeepLinkedPost: Codable, Sendable {
    let postId: UUID
    let authorId: UUID
    let authorName: String
    let authorAvatar: String?
    let frontImagePath: String
    let backImagePath: String
    let caption: String?
    let postedAt: Date
    let isLate: Bool
    let viewCount: Int
    let reactionSummary: [String: Int]?
    let groupId: UUID
    let promptDate: String

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case authorId = "author_id"
        case authorName = "author_name"
        case authorAvatar = "author_avatar"
        case frontImagePath = "front_image_path"
        case backImagePath = "back_image_path"
        case caption
        case postedAt = "posted_at"
        case isLate = "is_late"
        case viewCount = "view_count"
        case reactionSummary = "reaction_summary"
        case groupId = "group_id"
        case promptDate = "prompt_date"
    }

    var asFeedPost: FeedPost {
        FeedPost(
            postId: postId,
            authorId: authorId,
            authorName: authorName,
            authorAvatar: authorAvatar,
            frontImagePath: frontImagePath,
            backImagePath: backImagePath,
            caption: caption,
            postedAt: postedAt,
            isLate: isLate,
            viewCount: viewCount,
            reactionSummary: reactionSummary
        )
    }
}
