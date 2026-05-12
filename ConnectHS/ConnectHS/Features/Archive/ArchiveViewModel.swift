import Foundation
import Observation
import os

@MainActor
@Observable
final class ArchiveViewModel {

    enum LoadState: Sendable {
        case loading
        case empty
        case posts
        case error(String)
    }

    /// One month's worth of archive posts, used as a section in the grid.
    struct MonthSection: Identifiable, Hashable, Sendable {
        let id: String          // "yyyy-MM"
        let title: String       // "March 2026"
        var posts: [ArchivePost]
    }

    private(set) var loadState: LoadState = .loading
    private(set) var sections: [MonthSection] = []
    private(set) var isLoadingMore = false
    private(set) var hasMore = true

    var onlyMine = false
    var groups: [FriendGroup] = []
    var selectedGroup: FriendGroup?

    private let postService = PostService()
    private let groupService = GroupService()
    private let logger = Logger(subsystem: "com.connecths.app", category: "ArchiveVM")

    private let pageSize = 60
    private var oldestPromptDate: String?

    // MARK: - Lifecycle

    func load() async {
        loadState = .loading
        sections = []
        oldestPromptDate = nil
        hasMore = true

        do {
            if groups.isEmpty {
                groups = try await groupService.fetchGroups()
            }
            if selectedGroup == nil {
                selectedGroup = groups.first
            }
            guard let group = selectedGroup else {
                loadState = .empty
                return
            }
            try await fetchPage(groupId: group.id, reset: true)
            loadState = sections.isEmpty ? .empty : .posts
        } catch {
            logger.error("Archive load failed: \(error.localizedDescription)")
            loadState = .error("couldn't load archive. try again.")
        }
    }

    func loadMore() async {
        guard !isLoadingMore, hasMore, let group = selectedGroup else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            try await fetchPage(groupId: group.id, reset: false)
        } catch {
            logger.error("Archive page failed: \(error.localizedDescription)")
        }
    }

    func toggleOnlyMine() async {
        onlyMine.toggle()
        await load()
    }

    func selectGroup(_ group: FriendGroup) async {
        guard group.id != selectedGroup?.id else { return }
        selectedGroup = group
        await load()
    }

    // MARK: - Paging

    private func fetchPage(groupId: UUID, reset: Bool) async throws {
        let page = try await postService.getArchive(
            groupId: groupId,
            before: oldestPromptDate,
            limit: pageSize,
            onlyMine: onlyMine
        )
        if page.isEmpty {
            hasMore = false
            return
        }
        oldestPromptDate = page.last?.promptDate
        if page.count < pageSize {
            hasMore = false
        }
        if reset {
            sections = bucketIntoMonths(page)
        } else {
            mergeIntoSections(page)
        }
    }

    private func bucketIntoMonths(_ posts: [ArchivePost]) -> [MonthSection] {
        var byKey: [String: MonthSection] = [:]
        var keysInOrder: [String] = []

        for post in posts {
            let (key, title) = monthKeyAndTitle(for: post.promptDate)
            if byKey[key] == nil {
                byKey[key] = MonthSection(id: key, title: title, posts: [])
                keysInOrder.append(key)
            }
            byKey[key]?.posts.append(post)
        }
        return keysInOrder.compactMap { byKey[$0] }
    }

    private func mergeIntoSections(_ posts: [ArchivePost]) {
        for post in posts {
            let (key, title) = monthKeyAndTitle(for: post.promptDate)
            if let idx = sections.firstIndex(where: { $0.id == key }) {
                sections[idx].posts.append(post)
            } else {
                sections.append(MonthSection(id: key, title: title, posts: [post]))
            }
        }
    }

    private func monthKeyAndTitle(for promptDate: String) -> (String, String) {
        // promptDate format from PostgREST: "yyyy-MM-dd"
        let key = String(promptDate.prefix(7))
        if let date = Self.parser.date(from: promptDate) {
            return (key, Self.display.string(from: date).lowercased())
        }
        return (key, key)
    }

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()
}
