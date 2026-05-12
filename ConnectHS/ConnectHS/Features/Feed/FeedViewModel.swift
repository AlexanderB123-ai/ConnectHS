import Foundation
import Observation
import os
import Supabase

@MainActor
@Observable
final class FeedViewModel {

    enum LoadState: Sendable {
        case loading
        case empty
        case posts
        case error(String)
    }

    private(set) var loadState: LoadState = .loading
    private(set) var posts: [FeedPost] = []
    private(set) var memories: [MemoryPost] = []
    private(set) var groups: [FriendGroup] = []
    /// Member count for the currently-selected group, used by FeedView's
    /// empty state to swap copy when the user is the only member yet.
    private(set) var selectedGroupMemberCount: Int = 0
    /// Non-blocking error from a background reload (foreground-resume,
    /// pull-to-refresh, realtime-triggered reload). When set, the existing
    /// `posts` / `loadState` are preserved — the view surfaces a subtle
    /// inline banner rather than wiping the feed. Nil on the happy path.
    private(set) var reloadError: String?
    var selectedGroup: FriendGroup?

    private let postService: PostServicing
    private let groupService: GroupServicing
    private let logger = Logger(subsystem: "com.connecths.app", category: "FeedVM")

    /// Nil defaults + in-body initialization keeps the implicit MainActor
    /// isolation on the service structs from leaking into the call site
    /// (default-arg expressions are evaluated as nonisolated, which would
    /// otherwise produce "call to main actor-isolated initializer in a
    /// synchronous nonisolated context" warnings under Swift 6 strict
    /// concurrency on this project's `SWIFT_DEFAULT_ACTOR_ISOLATION =
    /// MainActor` setting).
    init(
        postService: PostServicing? = nil,
        groupService: GroupServicing? = nil
    ) {
        self.postService = postService ?? PostService()
        self.groupService = groupService ?? GroupService()
    }

    private var realtimeTask: Task<Void, Never>?
    private var realtimeChannel: RealtimeChannelV2?
    private var subscribedGroupId: UUID?

    // MARK: - Loading

    func load() async {
        loadState = .loading
        reloadError = nil
        do {
            groups = try await groupService.fetchGroups()
            if selectedGroup == nil {
                selectedGroup = groups.first
            }
            guard let group = selectedGroup else {
                posts = []
                memories = []
                loadState = .empty
                return
            }

            async let feedFetch = postService.getFeed(groupId: group.id)
            async let memoryFetch = postService.getMemories(groupId: group.id)
            async let memberFetch = groupService.listMembers(groupId: group.id)
            posts = (try? await feedFetch) ?? []
            memories = (try? await memoryFetch) ?? []
            selectedGroupMemberCount = (try? await memberFetch)?.count ?? 0
            loadState = posts.isEmpty ? .empty : .posts
            await subscribe(to: group.id)
            // Widget I/O is not on the user-visible critical path; detach so
            // the feed state update isn't blocked on UserDefaults + JPEG
            // encode + signed-URL fetch in WidgetSyncService.
            syncWidgetDetached(for: group)
        } catch {
            logger.error("Feed load failed: \(error.localizedDescription)")
            loadState = .error(String(localized: "feed.error.couldntLoad"))
        }
    }

    func reload() async {
        guard let group = selectedGroup else {
            await load()
            return
        }
        async let feedFetch = postService.getFeed(groupId: group.id)
        async let memoryFetch = postService.getMemories(groupId: group.id)
        async let memberFetch = groupService.listMembers(groupId: group.id)

        // Track individual failures: if all three throw, we surface a
        // non-blocking banner but keep the stale-but-shown data. Don't
        // overwrite posts/memories with empty arrays on a transient failure
        // (network blip, brief Supabase hiccup) — that's worse than stale.
        let feedResult: [FeedPost]? = try? await feedFetch
        let memoryResult: [MemoryPost]? = try? await memoryFetch
        let memberResult: [GroupMember]? = try? await memberFetch

        if let feedResult { posts = feedResult }
        if let memoryResult { memories = memoryResult }
        if let memberResult { selectedGroupMemberCount = memberResult.count }

        let everythingFailed = feedResult == nil && memoryResult == nil && memberResult == nil
        reloadError = everythingFailed ? String(localized: "feed.error.refresh") : nil
        if feedResult != nil {
            loadState = posts.isEmpty ? .empty : .posts
        }
        // If the initial subscribe failed (network down at app launch),
        // subscribedGroupId is still nil. `subscribe` is idempotent — it
        // early-returns when already subscribed — so this only does real
        // work in the recovery case.
        await subscribe(to: group.id)
        syncWidgetDetached(for: group)
    }

    func selectGroup(_ group: FriendGroup) async {
        guard group.id != selectedGroup?.id else { return }
        selectedGroup = group
        // reload() calls subscribe() with the idempotent guard — no need to
        // call it again here. Was previously a dead double-subscribe.
        await reload()
    }

    /// Clears a non-blocking reload error banner — e.g. when the user
    /// dismisses the toast or successfully reloads again.
    func dismissReloadError() {
        reloadError = nil
    }

    /// Deep-link entrypoint: switch the feed to a group by id, fetching the
    /// list first if it hasn't loaded yet.
    func selectGroup(id: UUID) async {
        if groups.isEmpty {
            groups = (try? await groupService.fetchGroups()) ?? []
        }
        guard let group = groups.first(where: { $0.id == id }) else {
            logger.info("Deep-link group switch: group \(id, privacy: .public) not in user's memberships")
            return
        }
        await selectGroup(group)
    }

    // MARK: - Realtime

    private func subscribe(to groupId: UUID) async {
        guard subscribedGroupId != groupId else { return }
        await unsubscribe()

        let channel = supabase.realtimeV2.channel("posts:\(groupId.uuidString)")
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "posts",
            filter: .eq("group_id", value: groupId.uuidString)
        )

        do {
            try await channel.subscribeWithError()
        } catch {
            logger.error("Realtime subscribe failed: \(error.localizedDescription)")
            return
        }

        realtimeChannel = channel
        subscribedGroupId = groupId

        realtimeTask = Task { [weak self] in
            for await _ in inserts {
                guard let self else { return }
                await self.reload()
            }
        }
    }

    func unsubscribe() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let channel = realtimeChannel {
            await channel.unsubscribe()
        }
        realtimeChannel = nil
        subscribedGroupId = nil
    }

    // MARK: - Widget

    /// Push the newest post in the active group to the home-screen widget,
    /// detached from the user-visible feed update path. Widget I/O (JPEG
    /// thumb encode, signed-URL fetch, App Group UserDefaults write) takes
    /// non-trivial time — we don't want the feed waiting on it.
    /// `WidgetSyncService.refresh(latest:group:)` no-ops when the post
    /// hasn't changed, so this is safe to call from every load/reload.
    private func syncWidgetDetached(for group: FriendGroup) {
        let latest = posts.first
        Task { await WidgetSyncService.shared.refresh(latest: latest, group: group) }
    }
}
