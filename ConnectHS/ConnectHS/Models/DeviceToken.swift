import Foundation

struct DeviceToken: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    let apnsToken: String
    let deviceId: String
    var appVersion: String?
    let createdAt: Date
    var lastSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case apnsToken = "apns_token"
        case deviceId = "device_id"
        case appVersion = "app_version"
        case createdAt = "created_at"
        case lastSeenAt = "last_seen_at"
    }
}
