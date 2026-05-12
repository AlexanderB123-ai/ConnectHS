import Foundation

enum AuthMethod: String, Codable, Sendable {
    case phone
    case apple
}

struct AppUser: Codable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    var phoneNumber: String?
    var appleUserId: String?
    var authMethod: AuthMethod
    var avatarUrl: String?
    var highSchool: String?
    var gradYear: Int?
    var birthday: String?
    var timezone: String
    var isAgeVerified: Bool
    var isBlocked: Bool
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case phoneNumber = "phone_number"
        case appleUserId = "apple_user_id"
        case authMethod = "auth_method"
        case avatarUrl = "avatar_url"
        case highSchool = "high_school"
        case gradYear = "grad_year"
        case birthday
        case timezone
        case isAgeVerified = "is_age_verified"
        case isBlocked = "is_blocked"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}
