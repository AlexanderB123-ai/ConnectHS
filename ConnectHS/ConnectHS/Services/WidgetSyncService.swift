import Foundation
import WidgetKit
import os

/// Bridges the in-app post stream to the home-screen widget via the App Group
/// container. Writes a `LatestPostPayload` (256×256 JPEG thumbs) and asks
/// WidgetKit to reload timelines on every change. Idempotent: a refresh that
/// resolves to the same `postID` short-circuits the download/encode work.
actor WidgetSyncService {

    static let shared: WidgetSyncService = WidgetSyncService()

    private let logger = Logger(subsystem: "com.connecths.app", category: "WidgetSync")
    private let session: URLSession = .shared

    /// Long edge of the widget thumbnails. Spec calls for 256×256; encoding at
    /// JPEG q0.7 keeps each thumb well under 50 KB to stay within the widget
    /// process memory budget.
    private let thumbLongEdge: CGFloat = 256
    private let thumbQuality: CGFloat = 0.7

    private init() {}

    // MARK: - Public API

    /// Refresh the widget from a post we already have raw bytes for (the
    /// just-captured moment). Skips the network round-trip entirely.
    func refresh(
        ownPost feedPost: FeedPost,
        group: FriendGroup,
        frontJpeg: Data,
        backJpeg: Data
    ) async {
        let frontThumb = await encodeThumb(from: frontJpeg)
        let backThumb = await encodeThumb(from: backJpeg)
        guard let frontThumb, let backThumb else {
            logger.error("Own-post widget refresh: thumb encode failed")
            return
        }
        await write(
            postID: feedPost.postId,
            groupID: group.id,
            groupName: group.name,
            groupEmoji: group.emoji,
            authorName: feedPost.authorName,
            postedAt: feedPost.postedAt,
            frontThumbBase64: frontThumb,
            backThumbBase64: backThumb
        )
    }

    /// Refresh from whatever the latest post is for the currently-selected
    /// group. Called from feed load/reload/realtime — runs once per distinct
    /// `postID` to avoid redundant network downloads.
    func refresh(latest feedPost: FeedPost?, group: FriendGroup) async {
        guard let feedPost else {
            // No posts in this group yet — clear so the widget shows the
            // empty state instead of a stale moment from another group.
            await clear()
            return
        }
        if let existing = LatestPostPayload.read(),
           existing.postID == feedPost.postId,
           existing.groupID == group.id {
            return
        }

        do {
            async let frontData = downloadImage(at: feedPost.frontImagePath)
            async let backData = downloadImage(at: feedPost.backImagePath)
            let (front, back) = try await (frontData, backData)
            guard let frontThumb = await encodeThumb(from: front),
                  let backThumb = await encodeThumb(from: back) else {
                logger.error("Latest-post widget refresh: thumb encode failed")
                return
            }
            await write(
                postID: feedPost.postId,
                groupID: group.id,
                groupName: group.name,
                groupEmoji: group.emoji,
                authorName: feedPost.authorName,
                postedAt: feedPost.postedAt,
                frontThumbBase64: frontThumb,
                backThumbBase64: backThumb
            )
        } catch {
            logger.error("Latest-post widget refresh failed: \(error.localizedDescription)")
        }
    }

    /// Drop the cached payload and reload timelines. Used on sign-out so the
    /// previous user's moment doesn't linger on the home screen.
    func clear() async {
        LatestPostPayload.clear()
        await reloadTimelines()
    }

    // MARK: - Internals

    private func write(
        postID: UUID,
        groupID: UUID,
        groupName: String,
        groupEmoji: String?,
        authorName: String,
        postedAt: Date,
        frontThumbBase64: String,
        backThumbBase64: String
    ) async {
        let payload = LatestPostPayload(
            postID: postID,
            groupID: groupID,
            groupName: groupName,
            groupEmoji: groupEmoji,
            authorName: authorName,
            postedAt: postedAt,
            backImageThumbBase64: backThumbBase64,
            frontImageThumbBase64: frontThumbBase64
        )
        do {
            try payload.write()
            await reloadTimelines()
        } catch {
            logger.error("Widget payload write failed: \(error.localizedDescription)")
        }
    }

    private func reloadTimelines() async {
        await MainActor.run {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func downloadImage(at path: String) async throws -> Data {
        let url = try await SignedURLCache.shared.url(for: path)
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(
                domain: "WidgetSync",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Image fetch HTTP \(http.statusCode)"]
            )
        }
        return data
    }

    private func encodeThumb(from data: Data) async -> String? {
        guard let jpeg = await ImagePipeline.shared.encodeThumb(
            from: data,
            maxLongEdge: thumbLongEdge,
            quality: thumbQuality
        ) else { return nil }
        return jpeg.base64EncodedString()
    }
}
