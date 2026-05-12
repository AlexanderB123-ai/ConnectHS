import Foundation

/// Mirror of `public.notification_settings`. Wraps two bits of state — the
/// per-kind toggles and the user-local quiet-hours window — that the F8
/// dispatchers (`send-push.decide`) read before fanning anything out.
///
/// Times are stored as `HH:mm:ss` strings in user-local time; we hold them
/// as `String` here for round-trip parity with the column type.
struct NotificationSettings: Codable, Sendable, Equatable {
    let userId: UUID
    var dailyPromptEnabled: Bool
    var dailyPromptWindowStart: String   // "HH:mm:ss"
    var dailyPromptWindowEnd: String     // "HH:mm:ss"
    var newPostEnabled: Bool
    var memoryEnabled: Bool
    var reactionEnabled: Bool
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dailyPromptEnabled = "daily_prompt_enabled"
        case dailyPromptWindowStart = "daily_prompt_window_start"
        case dailyPromptWindowEnd = "daily_prompt_window_end"
        case newPostEnabled = "new_post_enabled"
        case memoryEnabled = "memory_enabled"
        case reactionEnabled = "reaction_enabled"
        case updatedAt = "updated_at"
    }

    static func defaults(for userId: UUID) -> NotificationSettings {
        NotificationSettings(
            userId: userId,
            dailyPromptEnabled: true,
            dailyPromptWindowStart: "10:00:00",
            dailyPromptWindowEnd: "22:00:00",
            newPostEnabled: true,
            memoryEnabled: true,
            reactionEnabled: true,
            updatedAt: Date()
        )
    }
}
