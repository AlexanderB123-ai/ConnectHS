import XCTest
@testable import ConnectHS

/// State-transition tests for `FeedViewModel`. Uses local stub services that
/// conform to `PostServicing` / `GroupServicing`, so the tests run without
/// hitting Supabase. WidgetSyncService and Realtime are NOT stubbed — the
/// VM dispatches widget I/O to a detached Task (no-op in test environment
/// because the App Group container doesn't exist) and the subscribe path
/// fails-fast on a missing realtime channel (logged, no state effect).
@MainActor
final class FeedViewModelTests: XCTestCase {

    // MARK: - load()

    func test_load_noGroups_landsOnEmpty() async throws {
        let vm = FeedViewModel(
            postService: StubPostService(),
            groupService: StubGroupService(groups: [])
        )
        await vm.load()

        XCTAssertEqual(vm.posts.count, 0)
        XCTAssertEqual(vm.memories.count, 0)
        XCTAssertNil(vm.selectedGroup)
        XCTAssertNil(vm.reloadError)
        if case .empty = vm.loadState { /* ok */ } else {
            XCTFail("Expected .empty, got \(vm.loadState)")
        }
    }

    func test_load_withGroupAndPosts_landsOnPosts() async throws {
        let group = StubData.group(name: "the boys")
        let post = StubData.feedPost(authorName: "alex")
        let vm = FeedViewModel(
            postService: StubPostService(feed: [post]),
            groupService: StubGroupService(groups: [group], members: [StubData.member()])
        )
        await vm.load()

        XCTAssertEqual(vm.posts.count, 1)
        XCTAssertEqual(vm.selectedGroup?.id, group.id)
        XCTAssertEqual(vm.selectedGroupMemberCount, 1)
        XCTAssertNil(vm.reloadError)
        if case .posts = vm.loadState { /* ok */ } else {
            XCTFail("Expected .posts, got \(vm.loadState)")
        }
    }

    func test_load_withGroupNoPosts_landsOnEmpty() async throws {
        let group = StubData.group()
        let vm = FeedViewModel(
            postService: StubPostService(feed: []),
            groupService: StubGroupService(groups: [group])
        )
        await vm.load()

        XCTAssertTrue(vm.posts.isEmpty)
        XCTAssertEqual(vm.selectedGroup?.id, group.id)
        if case .empty = vm.loadState { /* ok */ } else {
            XCTFail("Expected .empty, got \(vm.loadState)")
        }
    }

    func test_load_fetchGroupsThrows_landsOnError() async throws {
        let vm = FeedViewModel(
            postService: StubPostService(),
            groupService: StubGroupService(fetchGroupsError: NSError(domain: "test", code: 1))
        )
        await vm.load()

        if case .error = vm.loadState { /* ok */ } else {
            XCTFail("Expected .error, got \(vm.loadState)")
        }
    }

    // MARK: - reload()

    func test_reload_allFetchesFail_setsReloadErrorAndKeepsStaleData() async throws {
        let group = StubData.group()
        let originalPost = StubData.feedPost(authorName: "alex")
        // First load succeeds.
        let post = StubPostService(feed: [originalPost])
        let grp = StubGroupService(groups: [group], members: [StubData.member()])
        let vm = FeedViewModel(postService: post, groupService: grp)
        await vm.load()
        XCTAssertEqual(vm.posts.count, 1)

        // Flip all three reload fetches to fail.
        post.feedError = NSError(domain: "test", code: 2)
        post.memoriesError = NSError(domain: "test", code: 3)
        grp.membersError = NSError(domain: "test", code: 4)
        await vm.reload()

        // Stale data preserved.
        XCTAssertEqual(vm.posts.count, 1, "Stale feed should NOT be wiped on transient failure")
        XCTAssertEqual(vm.posts.first?.postId, originalPost.postId)
        // Non-blocking banner surfaced.
        XCTAssertNotNil(vm.reloadError, "reloadError should be set when every fetch fails")
    }

    func test_reload_partialFailure_doesNotSurfaceBanner() async throws {
        let group = StubData.group()
        let post = StubPostService(feed: [StubData.feedPost()])
        let grp = StubGroupService(groups: [group])
        let vm = FeedViewModel(postService: post, groupService: grp)
        await vm.load()

        // Only the memory fetch fails — banner should NOT show.
        post.memoriesError = NSError(domain: "test", code: 3)
        await vm.reload()

        XCTAssertNil(vm.reloadError, "Partial failure (1 of 3) shouldn't trigger the banner")
    }

    func test_dismissReloadError_clearsBanner() async throws {
        let group = StubData.group()
        let post = StubPostService(feed: [StubData.feedPost()])
        let grp = StubGroupService(groups: [group])
        let vm = FeedViewModel(postService: post, groupService: grp)
        await vm.load()

        post.feedError = NSError(domain: "test", code: 1)
        post.memoriesError = NSError(domain: "test", code: 1)
        grp.membersError = NSError(domain: "test", code: 1)
        await vm.reload()
        XCTAssertNotNil(vm.reloadError)

        vm.dismissReloadError()
        XCTAssertNil(vm.reloadError)
    }

    // MARK: - selectGroup()

    func test_selectGroup_switchesAndReloadsFeed() async throws {
        let a = StubData.group(name: "group a")
        let b = StubData.group(name: "group b")
        let postA = StubData.feedPost(authorName: "from-a")
        let postB = StubData.feedPost(authorName: "from-b")

        let stub = StubPostService(feed: [postA])
        let vm = FeedViewModel(
            postService: stub,
            groupService: StubGroupService(groups: [a, b])
        )
        await vm.load()
        XCTAssertEqual(vm.selectedGroup?.id, a.id)

        // Swap the post service to return b's feed when the next reload fires.
        stub.feed = [postB]
        await vm.selectGroup(b)

        XCTAssertEqual(vm.selectedGroup?.id, b.id)
        XCTAssertEqual(vm.posts.first?.authorName, "from-b")
    }

    func test_selectGroup_sameGroupIsNoOp() async throws {
        let group = StubData.group()
        let stub = StubPostService(feed: [StubData.feedPost()])
        let vm = FeedViewModel(
            postService: stub,
            groupService: StubGroupService(groups: [group])
        )
        await vm.load()
        stub.feedFetchCount = 0
        await vm.selectGroup(group)

        XCTAssertEqual(stub.feedFetchCount, 0, "Selecting the already-selected group should not trigger a refetch")
    }
}

// MARK: - Stubs

private final class StubPostService: PostServicing, @unchecked Sendable {
    var feed: [FeedPost]
    var memories: [MemoryPost]
    var feedError: Error?
    var memoriesError: Error?
    var reactionResult: Bool = true
    var toggleError: Error?
    var myReactionsResult: Set<ReactionType> = []
    var markViewedError: Error?

    var feedFetchCount = 0

    init(feed: [FeedPost] = [], memories: [MemoryPost] = []) {
        self.feed = feed
        self.memories = memories
    }

    func getFeed(groupId: UUID, date: Date) async throws -> [FeedPost] {
        feedFetchCount += 1
        if let feedError { throw feedError }
        return feed
    }

    func getMemories(groupId: UUID) async throws -> [MemoryPost] {
        if let memoriesError { throw memoriesError }
        return memories
    }

    func toggleReaction(postId: UUID, reaction: ReactionType) async throws -> Bool {
        if let toggleError { throw toggleError }
        return reactionResult
    }

    func markViewed(postId: UUID) async throws {
        if let markViewedError { throw markViewedError }
    }

    func myReactions(postId: UUID, userId: UUID) async throws -> Set<ReactionType> {
        myReactionsResult
    }
}

private final class StubGroupService: GroupServicing, @unchecked Sendable {
    var groups: [FriendGroup]
    var members: [GroupMember]
    var fetchGroupsError: Error?
    var membersError: Error?

    init(
        groups: [FriendGroup] = [],
        members: [GroupMember] = [],
        fetchGroupsError: Error? = nil,
        membersError: Error? = nil
    ) {
        self.groups = groups
        self.members = members
        self.fetchGroupsError = fetchGroupsError
        self.membersError = membersError
    }

    func fetchGroups() async throws -> [FriendGroup] {
        if let fetchGroupsError { throw fetchGroupsError }
        return groups
    }

    func listMembers(groupId: UUID) async throws -> [GroupMember] {
        if let membersError { throw membersError }
        return members
    }
}

// MARK: - Fixtures

private enum StubData {
    static func group(name: String = "test group") -> FriendGroup {
        FriendGroup(
            id: UUID(),
            name: name,
            emoji: "🧪",
            createdBy: UUID(),
            memberLimit: 25,
            createdAt: Date(),
            updatedAt: Date(),
            deletedAt: nil
        )
    }

    static func feedPost(
        authorName: String = "tester",
        reactionSummary: [String: Int]? = nil
    ) -> FeedPost {
        FeedPost(
            postId: UUID(),
            authorId: UUID(),
            authorName: authorName,
            authorAvatar: nil,
            frontImagePath: "front.jpg",
            backImagePath: "back.jpg",
            caption: nil,
            postedAt: Date(),
            isLate: false,
            viewCount: 0,
            reactionSummary: reactionSummary
        )
    }

    static func member() -> GroupMember {
        GroupMember(
            userId: UUID(),
            displayName: "tester",
            avatarUrl: nil,
            role: .admin,
            joinedAt: Date()
        )
    }
}
