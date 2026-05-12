import Foundation
import Supabase
import Storage

/// Caches Supabase Storage signed URLs by `(bucket, path)` so we don't re-mint
/// a URL for every image render. Server TTL is 6h; entries expire 30s early to
/// avoid racing the boundary. Cleared on sign-out (see `AuthViewModel.signOut`)
/// so a re-login (or different user) never serves a previous session's URL.
actor SignedURLCache {

    static let shared = SignedURLCache()

    private struct Key: Hashable {
        let bucket: String
        let path: String
    }

    private struct Entry {
        let url: URL
        let expiresAt: Date
    }

    private let ttl: TimeInterval
    private var cache: [Key: Entry] = [:]

    init(ttl: TimeInterval = 6 * 3600 - 30) {
        self.ttl = ttl
    }

    func url(for path: String, bucket: String = PostService.postsBucket) async throws -> URL {
        let key = Key(bucket: bucket, path: path)
        if let entry = cache[key], entry.expiresAt > Date() {
            return entry.url
        }
        let url = try await supabase.storage
            .from(bucket)
            .createSignedURL(path: path, expiresIn: Int(ttl))
        cache[key] = Entry(url: url, expiresAt: Date().addingTimeInterval(ttl))
        return url
    }

    func invalidate(path: String, bucket: String = PostService.postsBucket) {
        cache.removeValue(forKey: Key(bucket: bucket, path: path))
    }

    /// Drop every entry. Called on sign-out so a re-login or new account
    /// doesn't inherit the previous session's still-valid signed URLs.
    func clear() {
        cache.removeAll()
    }
}
