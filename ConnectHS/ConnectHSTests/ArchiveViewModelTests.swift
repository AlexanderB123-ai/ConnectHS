import XCTest
@testable import ConnectHS

/// Covers `ArchiveViewModel` state transitions and the new `loadGeneration`
/// guard that protects against rapid-fire `load()` invocations stomping a
/// fresh sections grid with a stale fetch's results.
@MainActor
final class ArchiveViewModelTests: XCTestCase {

    // MARK: - Basic states

    func test_load_noGroups_landsOnEmpty() async {
        let vm = ArchiveViewModel(
            postService: StubPostService(),
            groupService: StubGroupService(groups: [])
        )
        await vm.load()

        if case .empty = vm.loadState { /* ok */ } else {
            XCTFail("Expected .empty, got \(vm.loadState)")
        }
        XCTAssertTrue(vm.sections.isEmpty)
    }

    func test_load_withGroupAndPosts_bucketsByMonth() async {
        let group = Fixtures.group()
        let posts = [
            Fixtures.archivePost(promptDate: "2026-03-15", authorName: "alex"),
            Fixtures.archivePost(promptDate: "2026-03-02", authorName: "ben"),
            Fixtures.archivePost(promptDate: "2026-02-28", authorName: "alex"),
        ]
        let vm = ArchiveViewModel(
            postService: StubPostService(archive: posts),
            groupService: StubGroupService(groups: [group])
        )
        await vm.load()

        if case .posts = vm.loadState { /* ok */ } else {
            XCTFail("Expected .posts, got \(vm.loadState)")
        }
        XCTAssertEqual(vm.sections.count, 2, "Should bucket into 2026-03 and 2026-02 sections")
        XCTAssertEqual(vm.sections.first?.posts.count, 2, "March section should have 2 posts")
        XCTAssertEqual(vm.sections.last?.posts.count, 1, "February section should have 1 post")
    }

    func test_load_fetchGroupsThrows_landsOnError() async {
        let vm = ArchiveViewModel(
            postService: StubPostService(),
            groupService: StubGroupService(fetchGroupsError: NSError(domain: "test", code: 1))
        )
        await vm.load()

        if case .error = vm.loadState { /* ok */ } else {
            XCTFail("Expected .error, got \(vm.loadState)")
        }
    }

    // MARK: - loadGeneration race protection

    func test_load_concurrentCalls_staleResultDoesNotStomp() async {
        // Setup: slow stub. The first load() awaits inside getArchive; the
        // second load() bumps `loadGeneration` and triggers its own (fast)
        // fetch. When the slow first fetch resumes, its `myGeneration`
        // check should bail.
        let group = Fixtures.group()
        let slowPosts = [Fixtures.archivePost(promptDate: "2025-01-01", authorName: "stale")]
        let fastPosts = [Fixtures.archivePost(promptDate: "2026-03-15", authorName: "fresh")]
        let stub = StubPostService()
        stub.archive = slowPosts
        stub.archiveDelay = 0.20  // First call sleeps 200ms
        let vm = ArchiveViewModel(
            postService: stub,
            groupService: StubGroupService(groups: [group])
        )

        async let first: Void = vm.load()       // Slow.
        try? await Task.sleep(nanoseconds: 50_000_000)  // Let the first call start.
        stub.archiveDelay = 0                   // Subsequent calls are fast.
        stub.archive = fastPosts
        async let second: Void = vm.load()      // Bumps generation.
        _ = await (first, second)

        // After both settle, the section data should reflect the fast (2nd)
        // fetch — NOT a mix from the stale (1st) one.
        XCTAssertEqual(vm.sections.first?.posts.first?.authorName, "fresh",
                       "Stale load result must not stomp the fresh load's sections")
    }

    // MARK: - Filter & group switch

    func test_toggleOnlyMine_triggersReload() async {
        let stub = StubPostService(archive: [Fixtures.archivePost()])
        let vm = ArchiveViewModel(
            postService: stub,
            groupService: StubGroupService(groups: [Fixtures.group()])
        )
        await vm.load()
        let initialOnlyMine = vm.onlyMine

        stub.fetchCount = 0
        await vm.toggleOnlyMine()

        XCTAssertNotEqual(vm.onlyMine, initialOnlyMine, "Toggling should flip onlyMine")
        XCTAssertGreaterThanOrEqual(stub.fetchCount, 1, "Toggling should refetch")
    }

    // MARK: - Stub services

    private final class StubPostService: PostServicing, @unchecked Sendable {
        var archive: [ArchivePost]
        var archiveError: Error?
        var archiveDelay: TimeInterval = 0
        var fetchCount = 0

        init(archive: [ArchivePost] = []) {
            self.archive = archive
        }

        func getFeed(groupId: UUID, date: Date) async throws -> [FeedPost] { [] }
        func getMemories(groupId: UUID) async throws -> [MemoryPost] { [] }
        func getArchive(groupId: UUID, before: String?, limit: Int, onlyMine: Bool) async throws -> [ArchivePost] {
            fetchCount += 1
            if archiveDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(archiveDelay * 1_000_000_000))
            }
            if let archiveError { throw archiveError }
            return archive
        }
        func toggleReaction(postId: UUID, reaction: ReactionType) async throws -> Bool { false }
        func markViewed(postId: UUID) async throws {}
        func myReactions(postId: UUID, userId: UUID) async throws -> Set<ReactionType> { [] }
    }

    private final class StubGroupService: GroupServicing, @unchecked Sendable {
        var groups: [FriendGroup]
        var fetchGroupsError: Error?

        init(groups: [FriendGroup] = [], fetchGroupsError: Error? = nil) {
            self.groups = groups
            self.fetchGroupsError = fetchGroupsError
        }

        func fetchGroups() async throws -> [FriendGroup] {
            if let fetchGroupsError { throw fetchGroupsError }
            return groups
        }

        func listMembers(groupId: UUID) async throws -> [GroupMember] { [] }
    }
}

// MARK: - Fixtures

private enum Fixtures {
    static func group() -> FriendGroup {
        FriendGroup(
            id: UUID(),
            name: "test",
            emoji: nil,
            createdBy: UUID(),
            memberLimit: 25,
            createdAt: Date(),
            updatedAt: Date(),
            deletedAt: nil
        )
    }

    static func archivePost(
        promptDate: String = "2026-03-15",
        authorName: String = "tester"
    ) -> ArchivePost {
        ArchivePost(
            postId: UUID(),
            authorId: UUID(),
            authorName: authorName,
            authorAvatar: nil,
            frontImagePath: "f.jpg",
            backImagePath: "b.jpg",
            caption: nil,
            promptDate: promptDate,
            postedAt: Date(),
            isLate: false,
            viewCount: 0,
            reactionSummary: nil
        )
    }
}
