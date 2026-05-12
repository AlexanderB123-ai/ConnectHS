import Foundation

struct MemoryPost: Codable, Identifiable, Hashable, Sendable {
    let postId: UUID
    let promptDate: String
    let yearsAgo: Int
    let authorName: String
    let frontImagePath: String
    let backImagePath: String
    let caption: String?

    var id: UUID { postId }

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case promptDate = "prompt_date"
        case yearsAgo = "years_ago"
        case authorName = "author_name"
        case frontImagePath = "front_image_path"
        case backImagePath = "back_image_path"
        case caption
    }
}

/// Pushed onto the navigation stack when the user opens a memory. Carries the
/// full list of memories surfaced for today (one per prior year) plus the id
/// the user tapped, so `MemoryDetailView` can land on that page and let them
/// swipe horizontally between adjacent years.
struct MemoryCarousel: Hashable, Sendable {
    let memories: [MemoryPost]
    let initialId: UUID
}
