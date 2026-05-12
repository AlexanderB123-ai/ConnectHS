import SwiftUI
import UIKit
import UserNotifications
import os

struct MainTabView: View {
    let user: AppUser
    @Bindable var authViewModel: AuthViewModel

    @State private var coordinator = RootCoordinator()
    @State private var router = DeepLinkRouter.shared
    @State private var showNotificationPrompt = false
    @State private var didCheckNotificationStatus = false

    private let postService = PostService()
    private let logger = Logger(subsystem: "com.connecths.app", category: "MainTab")

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            NavigationStack(path: $coordinator.feedPath) {
                FeedView(user: user, coordinator: coordinator, authViewModel: authViewModel)
            }
            .tabItem {
                Label {
                    Text("main.tab.today")
                } icon: {
                    Image(systemName: "sun.max.fill")
                }
            }
            .tag(0)

            NavigationStack {
                ArchiveView(user: user)
            }
            .tabItem {
                Label {
                    Text("main.tab.archive")
                } icon: {
                    Image(systemName: "clock.fill")
                }
            }
            .tag(1)

            NavigationStack {
                ProfileView(user: user, authViewModel: authViewModel)
            }
            .tabItem {
                Label {
                    Text("main.tab.you")
                } icon: {
                    Image(systemName: "person.fill")
                }
            }
            .tag(2)
        }
        .tint(.chTether)
        .sheet(isPresented: $showNotificationPrompt) {
            NotificationPermissionSheet { _ in }
        }
        .task {
            await maybePromptForNotifications()
            await drainPendingDeepLink()
        }
        .onChange(of: router.pending) { _, url in
            guard url != nil else { return }
            Task { await drainPendingDeepLink() }
        }
    }

    /// First time the user lands in the main app, ask for notification
    /// permission if they haven't been asked before. Per spec we never
    /// re-prompt; settings deep-link is how they recover.
    private func maybePromptForNotifications() async {
        guard !didCheckNotificationStatus else { return }
        didCheckNotificationStatus = true

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            // If already authorized, kick off remote registration so the token
            // upserts after a fresh install on a previously-authorized account.
            if settings.authorizationStatus == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return
        }

        showNotificationPrompt = true
    }

    // MARK: - Deep-link routing

    /// Pull the most recent URL out of `DeepLinkRouter`, route it, and clear
    /// it. Called both on first appear (covers cold-start taps that landed
    /// in the router before this view mounted) and on every `pending` change.
    private func drainPendingDeepLink() async {
        guard let url = DeepLinkRouter.shared.pending else { return }
        DeepLinkRouter.shared.clear()
        await route(url)
    }

    private func route(_ url: URL) async {
        guard url.scheme == "connecths" else {
            logger.info("Ignoring non-connecths URL: \(url.absoluteString, privacy: .public)")
            return
        }

        let host = url.host(percentEncoded: false) ?? ""
        // host == "post" means url == connecths://post/{uuid}; the path-component
        // we want is the first non-empty segment after the host.
        let segments = url.pathComponents.filter { $0 != "/" }
        let firstSegment = segments.first

        switch host {
        case "post":
            guard let id = firstSegment.flatMap(UUID.init(uuidString:)) else { return }
            await openPost(id: id)
        case "memory":
            guard let id = firstSegment.flatMap(UUID.init(uuidString:)) else { return }
            await openMemory(id: id)
        case "camera":
            openCamera()
        case "group":
            guard let id = firstSegment.flatMap(UUID.init(uuidString:)) else { return }
            openGroup(id: id)
        default:
            logger.info("Unknown deep-link host: \(host, privacy: .public)")
        }
    }

    private func openPost(id: UUID) async {
        coordinator.selectedTab = 0
        do {
            guard let resolved = try await postService.getPost(id: id) else {
                logger.info("Deep-link post \(id, privacy: .public) not visible to user")
                return
            }
            // If the post lives in a different group, switch context first so
            // the back-stack lands the user on the correct feed.
            coordinator.pendingGroupSwitch = resolved.groupId
            // Deep-link lands on a single-element carousel — TabView handles
            // it gracefully (no pager dots when there's just one page).
            let feedPost = resolved.asFeedPost
            coordinator.feedPath.append(PostCarousel(posts: [feedPost], initialId: feedPost.id))
        } catch {
            logger.error("Deep-link post fetch failed: \(error.localizedDescription)")
        }
    }

    private func openMemory(id: UUID) async {
        coordinator.selectedTab = 0
        do {
            guard let resolved = try await postService.getPost(id: id) else { return }
            coordinator.pendingGroupSwitch = resolved.groupId
            let memory = MemoryPost(
                postId: resolved.postId,
                promptDate: resolved.promptDate,
                yearsAgo: yearsAgo(from: resolved.promptDate),
                authorName: resolved.authorName,
                frontImagePath: resolved.frontImagePath,
                backImagePath: resolved.backImagePath,
                caption: resolved.caption
            )
            // Deep links land on a single memory; the carousel still handles
            // the case gracefully (one page, no pager dots).
            coordinator.feedPath.append(MemoryCarousel(memories: [memory], initialId: memory.id))
        } catch {
            logger.error("Deep-link memory fetch failed: \(error.localizedDescription)")
        }
    }

    private func openCamera() {
        coordinator.selectedTab = 0
        coordinator.cameraRequest = UUID()
    }

    private func openGroup(id: UUID) {
        coordinator.selectedTab = 0
        coordinator.pendingGroupSwitch = id
    }

    private func yearsAgo(from promptDateString: String) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let postDate = formatter.date(from: promptDateString) else { return 0 }
        let years = Calendar.current.dateComponents([.year], from: postDate, to: Date()).year ?? 0
        return max(years, 0)
    }
}

#Preview {
    MainTabView(
        user: AppUser(
            id: UUID(),
            displayName: "Alex",
            authMethod: .phone,
            timezone: "America/New_York",
            isAgeVerified: true,
            isBlocked: false,
            createdAt: Date(),
            updatedAt: Date()
        ),
        authViewModel: AuthViewModel()
    )
}
