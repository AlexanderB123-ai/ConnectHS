import Foundation
import UIKit
import Supabase
import Storage

/// Per-user avatar upload + URL bookkeeping. Storage RLS pins each user
/// to their own folder (`avatars/{user_id}/avatar.jpg`); the `set_avatar_url`
/// RPC is the only way to flip `users.avatar_url` (clients don't have
/// direct UPDATE on the users table).
struct AvatarService: Sendable {

    nonisolated static let bucket = "avatars"

    /// Compress + upload the JPEG and persist its path on the user row.
    /// Returns the new path so the caller can preview without re-fetching.
    func upload(image: UIImage, userId: UUID) async throws -> String {
        guard let jpeg = await ImagePipeline.shared.encodeForUpload(image) else {
            throw AvatarError.encodeFailed
        }

        let path = "\(userId.uuidString)/avatar.jpg"

        try await supabase.storage
            .from(Self.bucket)
            .upload(
                path,
                data: jpeg,
                options: .init(contentType: "image/jpeg", upsert: true)
            )

        try await supabase
            .rpc("set_avatar_url", params: ["p_url": path])
            .execute()

        // No cache to invalidate here — `AvatarView` resolves URLs on
        // .task(id: avatarPath), so changing the path triggers a fresh
        // signed-URL fetch automatically. SignedURLCache.shared is keyed
        // for the posts bucket and wouldn't apply.
        return path
    }

    /// Mint a signed URL for an avatar path. Avatar URLs are stored as
    /// path strings (not full URLs) so the signed URL refreshes naturally
    /// before each render. Goes through `SignedURLCache.shared` keyed by
    /// `(bucket, path)` so a list of 25 group members doesn't trigger 25
    /// round-trips on every redraw.
    func signedURL(for path: String) async throws -> URL {
        try await SignedURLCache.shared.url(for: path, bucket: Self.bucket)
    }
}

enum AvatarError: LocalizedError, Sendable {
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .encodeFailed: return String(localized: "avatar.error.encodeFailed")
        }
    }
}
