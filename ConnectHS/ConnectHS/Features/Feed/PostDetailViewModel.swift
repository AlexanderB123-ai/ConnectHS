import Foundation
import Observation
import os

@MainActor
@Observable
final class PostDetailViewModel {

    private(set) var reactionCounts: [ReactionType: Int] = [:]
    private(set) var myReactions: Set<ReactionType> = []
    private(set) var didMarkViewed = false

    private let postService = PostService()
    private let logger = Logger(subsystem: "com.connecths.app", category: "PostDetailVM")

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
