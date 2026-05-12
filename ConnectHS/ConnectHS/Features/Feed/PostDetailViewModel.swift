import Foundation
import Observation
import os

@MainActor
@Observable
final class PostDetailViewModel {

    private(set) var reactionCounts: [ReactionType: Int] = [:]
    private(set) var myReactions: Set<ReactionType> = []
    private(set) var didMarkViewed = false

    private let postService: PostServicing
    private let logger = Logger(subsystem: "com.connecths.app", category: "PostDetailVM")

    /// See FeedViewModel.init — nil default avoids the
    /// MainActor-isolated-init warning under strict concurrency.
    init(postService: PostServicing? = nil) {
        self.postService = postService ?? PostService()
    }

    /// Reactions currently mid-flight. Rapid double-tap on the same reaction
    /// would otherwise race: both calls snapshot `wasOn` before either's
    /// optimistic flip lands, and the rollback paths over-correct. Skipping
    /// while a toggle is in flight is the simplest correct behavior — the
    /// user's second tap is dropped, but they can re-tap once the first
    /// settles. Per-reaction (not global) so heart + fire can fly together.
    private var inFlight: Set<ReactionType> = []

    func bootstrap(post: FeedPost, userId: UUID) async {
        seedReactionCounts(from: post)
        // Both calls are fire-and-forget — they assign to viewmodel state on
        // completion. Run concurrently and swallow individual failures.
        async let viewed: Void = markViewed(postId: post.postId)
        async let mine: Void  = loadMyReactions(postId: post.postId, userId: userId)
        _ = try? await viewed
        _ = try? await mine
    }

    func toggle(_ reaction: ReactionType, postId: UUID) async {
        guard !inFlight.contains(reaction) else { return }
        inFlight.insert(reaction)
        defer { inFlight.remove(reaction) }

        let wasOn = myReactions.contains(reaction)

        // Optimistic flip.
        if wasOn {
            myReactions.remove(reaction)
            reactionCounts[reaction] = max((reactionCounts[reaction] ?? 1) - 1, 0)
        } else {
            myReactions.insert(reaction)
            reactionCounts[reaction] = (reactionCounts[reaction] ?? 0) + 1
        }

        do {
            let serverIsOn = try await postService.toggleReaction(postId: postId, reaction: reaction)
            // If server disagrees with our optimism, reconcile.
            let clientIsOn = !wasOn
            if serverIsOn != clientIsOn {
                if serverIsOn {
                    myReactions.insert(reaction)
                    reactionCounts[reaction] = (reactionCounts[reaction] ?? 0) + 1
                } else {
                    myReactions.remove(reaction)
                    reactionCounts[reaction] = max((reactionCounts[reaction] ?? 1) - 1, 0)
                }
            }
        } catch {
            logger.error("Reaction toggle failed: \(error.localizedDescription)")
            // Roll back optimistic change.
            if wasOn {
                myReactions.insert(reaction)
                reactionCounts[reaction] = (reactionCounts[reaction] ?? 0) + 1
            } else {
                myReactions.remove(reaction)
                reactionCounts[reaction] = max((reactionCounts[reaction] ?? 1) - 1, 0)
            }
        }
    }

    // MARK: - Private

    private func seedReactionCounts(from post: FeedPost) {
        reactionCounts = [:]
        guard let summary = post.reactionSummary else { return }
        for (key, count) in summary {
            if let r = ReactionType(rawValue: key) {
                reactionCounts[r] = count
            }
        }
    }

    private func markViewed(postId: UUID) async throws {
        try await postService.markViewed(postId: postId)
        didMarkViewed = true
    }

    private func loadMyReactions(postId: UUID, userId: UUID) async throws {
        myReactions = try await postService.myReactions(postId: postId, userId: userId)
    }
}
