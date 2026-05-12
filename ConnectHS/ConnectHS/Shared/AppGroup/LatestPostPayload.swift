import Foundation

/// Cross-process payload the app writes into the App Group container so the
/// widget can render the latest moment without network or auth.
///
/// Thumb encoding is JPEG (not WebP, per the 2026-05-06 decision — iOS has no
/// native WebP encoder). Both thumbs are downscaled to 256×256 long-edge to
/// stay under the widget process' ~30 MB memory budget.
nonisolated struct LatestPostPayload: Codable, Sendable, Equatable {
    let postID: UUID
    let groupID: UUID
    let groupName: String
    let groupEmoji: String?
    let authorName: String
    let postedAt: Date
    let backImageThumbBase64: String
    let frontImageThumbBase64: String
}

extension LatestPostPayload {

    /// Read the most recently written payload from the App Group container.
    /// Returns `nil` when no payload has been written yet, when the App Group
    /// entitlement isn't configured, or when the stored data fails to decode
    /// (e.g. an older shape from a previous app version).
    nonisolated static func read() -> LatestPostPayload? {
        guard let defaults = UserDefaults(suiteName: SharedKeys.appGroupID),
              let data = defaults.data(forKey: SharedKeys.latestPostKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LatestPostPayload.self, from: data)
    }

    /// Persist this payload into the App Group container. Throws if the App
    /// Group entitlement is missing on the calling target so the caller can
    /// surface a configuration error instead of silently dropping writes.
    nonisolated func write() throws {
        guard let defaults = UserDefaults(suiteName: SharedKeys.appGroupID) else {
            throw NSError(
                domain: "AppGroup",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "App Group not available"]
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        defaults.set(data, forKey: SharedKeys.latestPostKey)
    }

    /// Remove any stored payload — used on sign-out so a previous account's
    /// moment doesn't linger on the home screen for the next user.
    nonisolated static func clear() {
        guard let defaults = UserDefaults(suiteName: SharedKeys.appGroupID) else { return }
        defaults.removeObject(forKey: SharedKeys.latestPostKey)
    }
}
