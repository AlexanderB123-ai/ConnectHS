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
    var selectedGroup: FriendGroup?

    private let postService = PostService()
    private let groupService = GroupService()
    private let logger = Logger(subsystem: "com.connecths.app", category: "FeedVM")

    private var realtimeTask: Task<Void, Never>?
    private var realtimeChannel: RealtimeChannelV2?
    private var subscribedGroupId: UUID?

    // MARK: - Loading

    func load() async {
        loadState = .loading
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
            await syncWidget(for: group)
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
        posts = (try? await feedFetch) ?? []
        memories = (try? await memoryFetch) ?? []
        selectedGroupMemberCount = (try? await memberFetch)?.count ?? 0
        loadState = posts.isEmpty ? .empty : .posts
        // If the initial subscribe failed (network down at app launch),
        // subscribedGroupId is still nil. `subscribe` is idempotent — it
        // early-returns when already subscribed — so this only does real
        // work in the recovery case.
        await subscribe(to: group.id)
        await syncWidget(for: group)
    }

    func selectGroup(_ group: FriendGroup) async {
        guard group.id != selectedGroup?.id else { return }
        selectedGroup = group
        await reload()
        await subscribe(to: group.id)
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

    /// Push the newest post in the active group to the home-screen widget.
    /// `WidgetSyncService.refresh(latest:group:)` no-ops when the post hasn't
    /// changed, so this is safe to call from every load/reload.
    private func syncWidget(for group: FriendGroup) async {
        await WidgetSyncService.shared.refresh(latest: posts.first, group: group)
    }
}
