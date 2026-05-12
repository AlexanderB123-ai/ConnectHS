import XCTest
@testable import ConnectHS

/// Covers the reaction toggle flow: optimistic update, server reconcile,
/// rollback on error, and the new `inFlight` guard against rapid double-tap.
@MainActor
final class PostDetailViewModelTests: XCTestCase {

    // MARK: - bootstrap

    func test_bootstrap_seedsReactionCountsFromPost() async {
        let post = StubData.feedPost(reactionSummary: ["heart": 3, "fire": 1])
        let vm = PostDetailViewModel(postService: StubPostService())
        await vm.bootstrap(post: post, userId: UUID())

        XCTAssertEqual(vm.reactionCounts[.heart], 3)
        XCTAssertEqual(vm.reactionCounts[.fire], 1)
        XCTAssertNil(vm.reactionCounts[.laugh])
    }

    func test_bootstrap_marksViewed() async {
        let stub = StubPostService()
        let vm = PostDetailViewModel(postService: stub)
        await vm.bootstrap(post: StubData.feedPost(), userId: UUID())

        XCTAssertTrue(vm.didMarkViewed)
        XCTAssertEqual(stub.markViewedCount, 1)
    }

    // MARK: - toggle: optimistic + reconcile

    func test_toggle_addReaction_optimisticAndServerAgrees() async {
        let post = StubData.feedPost(reactionSummary: nil)
        let stub = StubPostService()
        stub.reactionResult = true  // Server confirms reaction is now on.
        let vm = PostDetailViewModel(postService: stub)
        await vm.bootstrap(post: post, userId: UUID())

        await vm.toggle(.heart, postId: post.postId)

        XCTAssertTrue(vm.myReactions.contains(.heart))
        XCTAssertEqual(vm.reactionCounts[.heart], 1)
    }

    func test_toggle_removeReaction_optimisticAndServerAgrees() async {
        let post = StubData.feedPost(reactionSummary: ["heart": 1])
        let stub = StubPostService()
        stub.reactionResult = false  // Server confirms reaction is now off.
        stub.myReactionsResult = [.heart]
        let vm = PostDetailViewModel(postService: stub)
        await vm.bootstrap(post: post, userId: UUID())
        XCTAssertTrue(vm.myReactions.contains(.heart))

        await vm.toggle(.heart, postId: post.postId)

        XCTAssertFalse(vm.myReactions.contains(.heart))
        XCTAssertEqual(vm.reactionCounts[.heart], 0)
    }

    func test_toggle_serverDisagrees_reconciles() async {
        // Client optimistically adds, but server returns "off" — VM must
        // reconcile by removing the optimistic add.
        let post = StubData.feedPost(reactionSummary: nil)
        let stub = StubPostService()
        stub.reactionResult = false  // Server disagrees: actually off.
        let vm = PostDetailViewModel(postService: stub)
        await vm.bootstrap(post: post, userId: UUID())

        await vm.toggle(.heart, postId: post.postId)

        XCTAssertFalse(vm.myReactions.contains(.heart), "Reconcile should remove the optimistic add")
        XCTAssertEqual(vm.reactionCounts[.heart] ?? 0, 0)
    }

    // MARK: - toggle: rollback on error

    func test_toggle_serverErrors_rollsBackOptimisticAdd() async {
        let post = StubData.feedPost(reactionSummary: ["heart": 2])
        let stub = StubPostService()
        stub.toggleError = NSError(domain: "test", code: 1)
        let vm = PostDetailViewModel(postService: stub)
        await vm.bootstrap(post: post, userId: UUID())

        await vm.toggle(.fire, postId: post.postId)

        XCTAssertFalse(vm.myReactions.contains(.fire), "Failed toggle should leave reaction off")
        XCTAssertEqual(vm.reactionCounts[.fire] ?? 0, 0)
        // The unrelated heart count is untouched.
        XCTAssertEqual(vm.reactionCounts[.heart], 2)
    }

    func test_toggle_serverErrors_rollsBackOptimisticRemove() async {
        let post = StubData.feedPost(reactionSummary: ["heart": 1])
        let stub = StubPostService()
        stub.toggleError = NSError(domain: "test", code: 1)
        stub.myReactionsResult = [.heart]
        let vm = PostDetailViewModel(postService: stub)
        await vm.bootstrap(post: post, userId: UUID())
        XCTAssertTrue(vm.myReactions.contains(.heart))

        await vm.toggle(.heart, postId: post.postId)

        XCTAssertTrue(vm.myReactions.contains(.heart), "Failed remove should leave reaction on")
        XCTAssertEqual(vm.reactionCounts[.heart], 1)
    }

    // MARK: - toggle: inFlight guard (race protection)

    func test_toggle_concurrentSameReaction_secondCallIsDropped() async {
        // Two rapid toggles of the same reaction. The second must early-return
        // (via the inFlight guard) — otherwise the rollback paths in the two
        // racing calls can stomp on each other and produce wrong counts.
        let post = StubData.feedPost(reactionSummary: nil)
        let stub = StubPostService()
        stub.reactionResult = true
        stub.toggleDelay = 0.05  // Hold the first call in-flight long enough.
        let vm = PostDetailViewModel(postService: stub)
        await vm.bootstrap(post: post, userId: UUID())

        async let first: Void  = vm.toggle(.heart, postId: post.postId)
        async let second: Void = vm.toggle(.heart, postId: post.postId)
        _ = await (first, second)

        XCTAssertEqual(stub.toggleCount, 1, "Only one server toggle should fire when two land in the same window")
        XCTAssertTrue(vm.myReactions.contains(.heart))
        XCTAssertEqual(vm.reactionCounts[.heart], 1)
    }

    func test_toggle_concurrentDifferentReactions_bothFire() async {
        // Heart + fire are independent — the guard is per-reaction, so they
        // should both reach the server.
        let post = StubData.feedPost(reactionSummary: nil)
        let stub = StubPostService()
        stub.reactionResult = true
        stub.toggleDelay = 0.02
        let vm = PostDetailViewModel(postService: stub)
        await vm.bootstrap(post: post, userId: UUID())

        async let h: Void = vm.toggle(.heart, postId: post.postId)
        async let f: Void = vm.toggle(.fire, postId: post.postId)
        _ = await (h, f)

        XCTAssertEqual(stub.toggleCount, 2)
        XCTAssertTrue(vm.myReactions.contains(.heart))
        XCTAssertTrue(vm.myReactions.contains(.fire))
    }
}

// MARK: - Stub

private final class StubPostService: PostServicing, @unchecked Sendable {
    var reactionResult: Bool = true
    var toggleError: Error?
    var toggleDelay: TimeInterval = 0
    var toggleCount = 0
    var markViewedCount = 0
    var myReactionsResult: Set<ReactionType> = []

    func getFeed(groupId: UUID, date: Date) async throws -> [FeedPost] { [] }
    func getMemories(groupId: UUID) async throws -> [MemoryPost] { [] }
    func getArchive(groupId: UUID, before: String?, limit: Int, onlyMine: Bool) async throws -> [ArchivePost] { [] }

    func toggleReaction(postId: UUID, reaction: ReactionType) async throws -> Bool {
        toggleCount += 1
        if toggleDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(toggleDelay * 1_000_000_000))
        }
        if let toggleError { throw toggleError }
        return reactionResult
    }

    func markViewed(postId: UUID) async throws {
        markViewedCount += 1
    }

    func myReactions(postId: UUID, userId: UUID) async throws -> Set<ReactionType> {
        myReactionsResult
    }
}

// MARK: - Fixtures

private enum StubData {
    static func feedPost(reactionSummary: [String: Int]? = nil) -> FeedPost {
        FeedPost(
            postId: UUID(),
            authorId: UUID(),
            authorName: "tester",
            authorAvatar: nil,
            frontImagePath: "f.jpg",
            backImagePath: "b.jpg",
            caption: nil,
            postedAt: Date(),
            isLate: false,
            viewCount: 0,
            reactionSummary: reactionSummary
        )
    }
}
