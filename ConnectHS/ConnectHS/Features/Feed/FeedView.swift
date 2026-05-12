import SwiftUI

struct FeedView: View {
    let user: AppUser
    @Bindable var coordinator: RootCoordinator
    @Bindable var authViewModel: AuthViewModel

    @State private var viewModel = FeedViewModel()
    @State private var showCamera = false
    @State private var showGroupOnboarding = false
    @State private var invitePayload: InvitePayload?
    @State private var inviteError: String?
    @State private var reportTarget: ReportTargetPayload?
    @State private var showReportConfirmation = false
    @State private var blockConfirmation: BlockConfirmation?
    @State private var blockError: String?

    @Environment(\.scenePhase) private var scenePhase

    private let blockService = BlockService()

    private struct ReportTargetPayload: Identifiable {
        let id = UUID()
        let postId: UUID
        let authorName: String
    }

    private struct BlockConfirmation: Identifiable {
        let id = UUID()
        let userId: UUID
        let displayName: String
    }

    private struct InvitePayload: Identifiable {
        let id = UUID()
        let text: String
    }

    private let groupService = GroupService()

    var body: some View {
        ZStack(alignment: .top) {
            Color.chCream.ignoresSafeArea()

            switch viewModel.loadState {
            case .loading:
                ProgressView().tint(.chTether)
            case .error(let message):
                errorView(message)
            case .empty:
                emptyView
            case .posts:
                feedContent
            }

            // Non-blocking reload error banner: shows when a background
            // reload (pull-to-refresh, foreground-resume) fails entirely.
            // Stale data stays visible underneath — better than wiping
            // the feed on a transient network blip.
            if let reloadError = viewModel.reloadError {
                reloadErrorBanner(reloadError)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.reloadError)
        .navigationTitle(viewModel.selectedGroup?.name ?? String(localized: "feed.title.fallback"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                groupMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if viewModel.selectedGroup != nil { showCamera = true }
                } label: {
                    Image(systemName: "camera.fill")
                        .foregroundStyle(.chTether)
                }
                .disabled(viewModel.selectedGroup == nil)
                .accessibilityLabel(Text("feed.toolbar.camera.label"))
                .accessibilityHint(Text("feed.toolbar.camera.hint"))
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            if let group = viewModel.selectedGroup {
                CameraView(
                    group: group,
                    user: user,
                    onDismiss: {
                        showCamera = false
                        Task { await viewModel.reload() }
                    }
                )
            }
        }
        .sheet(item: $invitePayload) { payload in
            ShareSheet(items: [payload.text])
        }
        .sheet(isPresented: $showGroupOnboarding, onDismiss: {
            // After the user joins or creates inside the sheet, GroupOnboarding
            // calls authViewModel.bootstrap() which re-evaluates memberships.
            // Reload the feed so the new group becomes selectable here.
            Task { await viewModel.load() }
        }) {
            NavigationStack {
                GroupOnboardingView(authViewModel: authViewModel, user: user)
            }
        }
        .sheet(item: $reportTarget) { payload in
            ReportSheet(
                target: .post(id: payload.postId, authorName: payload.authorName),
                onSubmitted: { showReportConfirmation = true }
            )
        }
        .alert(Text("report.confirmation.title"), isPresented: $showReportConfirmation) {
            Button(role: .cancel) {} label: { Text("common.ok") }
        } message: {
            Text("report.confirmation.message")
        }
        .confirmationDialog(
            blockConfirmation.map { "block \($0.displayName.lowercased())?" } ?? "",
            isPresented: Binding(
                get: { blockConfirmation != nil },
                set: { if !$0 { blockConfirmation = nil } }
            ),
            presenting: blockConfirmation
        ) { confirm in
            Button(role: .destructive) {
                Task { await performBlock(userId: confirm.userId) }
            } label: {
                Text("blocks.action")
            }
            Button(role: .cancel) { blockConfirmation = nil } label: { Text("common.cancel") }
        } message: { _ in
            Text("blocks.confirm.message")
        }
        .alert(Text("feed.invite.error.title"), isPresented: Binding(
            get: { inviteError != nil },
            set: { if !$0 { inviteError = nil } }
        )) {
            Button(role: .cancel) { inviteError = nil } label: { Text("common.ok") }
        } message: {
            Text(inviteError ?? "")
        }
        .alert(Text("blocks.error.title"), isPresented: Binding(
            get: { blockError != nil },
            set: { if !$0 { blockError = nil } }
        )) {
            Button(role: .cancel) { blockError = nil } label: { Text("common.ok") }
        } message: {
            Text(blockError ?? "")
        }
        .navigationDestination(for: PostCarousel.self) { carousel in
            PostDetailView(carousel: carousel, currentUserId: user.id)
        }
        .navigationDestination(for: MemoryCarousel.self) { carousel in
            MemoryDetailView(carousel: carousel, currentUserId: user.id)
        }
        .navigationDestination(for: FriendGroup.self) { group in
            GroupSettingsView(
                group: group,
                currentUserId: user.id,
                onLeave: {
                    Task { await viewModel.reload() }
                },
                onMutate: {
                    Task { await viewModel.reload() }
                }
            )
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: coordinator.cameraRequest) { _, newValue in
            guard newValue != nil, viewModel.selectedGroup != nil else { return }
            showCamera = true
        }
        .onChange(of: coordinator.pendingGroupSwitch) { _, target in
            guard let target else { return }
            Task {
                await viewModel.selectGroup(id: target)
                coordinator.pendingGroupSwitch = nil
            }
        }
        .onDisappear {
            Task { await viewModel.unsubscribe() }
        }
        .onChange(of: scenePhase) { previous, current in
            // Coming back from background: realtime may have missed events
            // while the socket was suspended (and the user expects fresh
            // data after they put the phone down). Cheap reload covers it.
            guard current == .active, previous == .background else { return }
            Task { await viewModel.reload() }
        }
        .refreshable {
            await viewModel.reload()
        }
    }

    // MARK: - Group selector

    @ViewBuilder
    private var groupMenu: some View {
        Menu {
            if viewModel.groups.count > 1 {
                Section(header: Text("feed.menu.groups.section")) {
                    ForEach(viewModel.groups) { group in
                        Button {
                            Task { await viewModel.selectGroup(group) }
                        } label: {
                            HStack {
                                Text("\(group.emoji ?? "") \(group.name)")
                                if group.id == viewModel.selectedGroup?.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            if let active = viewModel.selectedGroup {
                Section {
                    Button {
                        Task { await createInvite(for: active) }
                    } label: {
                        Label {
                            Text("feed.invite.menu.entry \(active.name)")
                        } icon: {
                            Image(systemName: "person.crop.circle.badge.plus")
                        }
                    }
                    Button {
                        coordinator.feedPath.append(active)
                    } label: {
                        Label {
                            Text("feed.settings.menu.entry")
                        } icon: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.selectedGroup?.emoji ?? "")
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.chInk)
        }
        .accessibilityLabel(
            Text(
                "feed.menu.group.label \(viewModel.selectedGroup?.name ?? String(localized: "feed.menu.group.none"))"
            )
        )
        .accessibilityHint(Text("feed.menu.group.hint"))
    }

    private func createInvite(for group: FriendGroup) async {
        do {
            let code = try await groupService.createInvite(groupId: group.id)
            invitePayload = InvitePayload(text: InviteURL.shareText(code: code))
        } catch {
            inviteError = String(localized: "group.settings.error.invite")
        }
    }

    private func performBlock(userId: UUID) async {
        blockConfirmation = nil
        do {
            try await blockService.block(targetId: userId)
            await viewModel.reload()
        } catch {
            blockError = String(localized: "blocks.error.block")
        }
    }

    // MARK: - Feed content

    private var feedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if !viewModel.memories.isEmpty {
                    MemoryRibbonView(
                        memories: viewModel.memories,
                        currentUserId: user.id
                    )
                    .padding(.horizontal, Spacing.md)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Spacing.sm),
                        GridItem(.flexible(), spacing: Spacing.sm)
                    ],
                    spacing: Spacing.sm
                ) {
                    ForEach(viewModel.posts) { post in
                        NavigationLink(value: PostCarousel(posts: viewModel.posts, initialId: post.id)) {
                            FeedPostCard(post: post)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if post.authorId != user.id {
                                Button(role: .destructive) {
                                    reportTarget = ReportTargetPayload(
                                        postId: post.postId,
                                        authorName: post.authorName
                                    )
                                } label: {
                                    Label {
                                        Text("report.member.action")
                                    } icon: {
                                        Image(systemName: "flag")
                                    }
                                }
                                Button(role: .destructive) {
                                    blockConfirmation = BlockConfirmation(
                                        userId: post.authorId,
                                        displayName: post.authorName
                                    )
                                } label: {
                                    Label {
                                        Text("blocks.action")
                                    } icon: {
                                        Image(systemName: "hand.raised")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            .padding(.vertical, Spacing.md)
        }
    }

    // MARK: - Empty state

    private var emptyView: some View {
        VStack(spacing: Spacing.md) {
            if !viewModel.memories.isEmpty {
                MemoryRibbonView(
                    memories: viewModel.memories,
                    currentUserId: user.id
                )
                .padding(.horizontal, Spacing.md)
            }

            Spacer()

            switch emptyKind {
            case .noGroup:
                noGroupBlock
            case .soloGroup:
                soloGroupBlock
            case .friendsHaventPosted:
                friendsHaventPostedBlock
            }

            Spacer()
        }
        .padding(.vertical, Spacing.md)
    }

    private enum EmptyKind {
        case noGroup
        case soloGroup
        case friendsHaventPosted
    }

    private var emptyKind: EmptyKind {
        if viewModel.selectedGroup == nil { return .noGroup }
        if viewModel.selectedGroupMemberCount <= 1 { return .soloGroup }
        return .friendsHaventPosted
    }

    private var noGroupBlock: some View {
        VStack(spacing: Spacing.md) {
            Text("feed.empty.noGroup.title")
                .font(.chHeadline)
                .foregroundStyle(.chInk)
            Text("feed.empty.noGroup.subtitle")
                .font(.chBody)
                .foregroundStyle(.chInkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
            Button {
                showGroupOnboarding = true
            } label: {
                Text("feed.empty.noGroup.cta")
                    .font(.chHeadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(.chTether)
                    )
            }
        }
    }

    private var soloGroupBlock: some View {
        VStack(spacing: Spacing.md) {
            Text("feed.empty.solo.title")
                .font(.chHeadline)
                .foregroundStyle(.chInk)
            Text("feed.empty.solo.subtitle")
                .font(.chBody)
                .foregroundStyle(.chInkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
            Button {
                showCamera = true
            } label: {
                Text("feed.empty.cta")
                    .font(.chHeadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(.chTether)
                    )
            }
        }
    }

    private var friendsHaventPostedBlock: some View {
        VStack(spacing: Spacing.md) {
            Text("feed.empty.title")
                .font(.chHeadline)
                .foregroundStyle(.chInk)
            Text("feed.empty.subtitle")
                .font(.chBody)
                .foregroundStyle(.chInkSoft)
            Button {
                showCamera = true
            } label: {
                Text("feed.empty.cta")
                    .font(.chHeadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(.chTether)
                    )
            }
        }
    }

    private func reloadErrorBanner(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.chWarning)
            Text(message)
                .font(.chCaption)
                .foregroundStyle(.chInk)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                viewModel.dismissReloadError()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.chInkSoft)
            }
            .accessibilityLabel(Text("feed.error.refresh.dismiss"))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        )
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Text("common.error.generic")
                .font(.chHeadline)
                .foregroundStyle(.chInk)
            Text(message)
                .font(.chBody)
                .foregroundStyle(.chInkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
            Button {
                Task { await viewModel.load() }
            } label: {
                Text("common.retry")
            }
            .font(.chBody)
            .foregroundStyle(.chTether)
        }
    }
}

// MARK: - Feed Post Card

struct FeedPostCard: View {
    let post: FeedPost

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ZStack(alignment: .topTrailing) {
                RemoteImage(imagePath: post.backImagePath)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))

                RemoteImage(imagePath: post.frontImagePath)
                    .aspectRatio(3.0 / 4.0, contentMode: .fill)
                    .frame(width: 44, height: 58)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(.white.opacity(0.7), lineWidth: 1.5)
                    )
                    .padding(Spacing.xs)
            }

            HStack(spacing: Spacing.xs) {
                Text(post.authorName.lowercased())
                    .font(.chCaption)
                    .foregroundStyle(.chInkSoft)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let total = totalReactions, total > 0 {
                    Text("\(total)")
                        .font(.chMicro)
                        .foregroundStyle(.chInkSoft)
                }
            }
        }
    }

    private var totalReactions: Int? {
        guard let summary = post.reactionSummary else { return nil }
        return summary.values.reduce(0, +)
    }
}

#Preview {
    NavigationStack {
        FeedView(
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
            coordinator: RootCoordinator(),
            authViewModel: AuthViewModel()
        )
    }
}
