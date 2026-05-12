import SwiftUI

struct PostDetailView: View {

    let carousel: PostCarousel
    let currentUserId: UUID

    @State private var selectedId: UUID
    @State private var viewModel = PostDetailViewModel()
    @State private var reactorSheet: ReactorSheetPayload?
    @State private var reportTarget: ReportTargetPayload?
    @State private var showReportConfirmation = false
    @Environment(\.dismiss) private var dismiss

    private struct ReportTargetPayload: Identifiable {
        let id = UUID()
        let postId: UUID
        let authorName: String
    }

    init(carousel: PostCarousel, currentUserId: UUID) {
        self.carousel = carousel
        self.currentUserId = currentUserId
        _selectedId = State(initialValue: carousel.initialId)
    }

    private struct ReactorSheetPayload: Identifiable {
        let id = UUID()
        let reaction: ReactionType
    }

    private var currentPost: FeedPost? {
        carousel.posts.first(where: { $0.id == selectedId })
    }

    private func viewerIsAuthor(of post: FeedPost) -> Bool {
        post.authorId == currentUserId
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedId) {
                ForEach(carousel.posts) { post in
                    page(post: post)
                        .tag(post.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: carousel.posts.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.black.opacity(0.4)))
                }
                .accessibilityLabel(Text("post.detail.close.label"))
                .accessibilityHint(Text("post.detail.close.hint"))
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 100 && abs(value.translation.width) < 80 {
                        dismiss()
                    }
                }
        )
        .sheet(item: $reactorSheet) { payload in
            if let post = currentPost {
                ReactorListSheet(postId: post.postId, reaction: payload.reaction)
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
        .task {
            if let post = currentPost {
                await viewModel.bootstrap(post: post, userId: currentUserId)
            }
        }
        .onChange(of: selectedId) { _, _ in
            // Reset reaction state and re-bootstrap for the newly-visible post.
            if let post = currentPost {
                Task { await viewModel.bootstrap(post: post, userId: currentUserId) }
            }
        }
    }

    // MARK: - Page

    private func page(post: FeedPost) -> some View {
        ZStack(alignment: .bottom) {
            backWithFrontInset(post: post)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                Spacer()
                metadataPanel(post: post)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Image stack

    private func backWithFrontInset(post: FeedPost) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                RemoteImage(imagePath: post.backImagePath)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                RemoteImage(imagePath: post.frontImagePath)
                    .aspectRatio(3.0 / 4.0, contentMode: .fill)
                    .frame(width: 110, height: 150)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .stroke(.white.opacity(0.7), lineWidth: 2)
                    )
                    .padding(.top, Spacing.xxl + Spacing.md)
                    .padding(.trailing, Spacing.md)
            }
        }
    }

    // MARK: - Metadata + reactions panel

    private func metadataPanel(post: FeedPost) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                AvatarView(
                    name: post.authorName,
                    avatarPath: post.authorAvatar,
                    size: 28
                )

                Text(post.authorName.lowercased())
                    .font(.chHeadline)
                    .foregroundStyle(.white)
                    .onLongPressGesture(minimumDuration: 0.5) {
                        guard post.authorId != currentUserId else { return }
                        reportTarget = ReportTargetPayload(
                            postId: post.postId,
                            authorName: post.authorName
                        )
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityActions {
                        if post.authorId != currentUserId {
                            // Long-press is invisible to VoiceOver users; the
                            // custom action surfaces "report this post" in the
                            // rotor instead.
                            Button(action: {
                                reportTarget = ReportTargetPayload(
                                    postId: post.postId,
                                    authorName: post.authorName
                                )
                            }) {
                                Text("post.detail.report.action")
                            }
                        }
                    }

                Text("·")
                    .foregroundStyle(.white.opacity(0.6))

                Text(timeAgo(post.postedAt))
                    .font(.chCaption)
                    .foregroundStyle(.white.opacity(0.7))

                if post.isLate {
                    Text("post.late")
                        .font(.chMicro)
                        .foregroundStyle(.chWarning)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.chWarning.opacity(0.15)))
                }

                Spacer()
            }

            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(.chBody)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }

            reactionBar(post: post)

            if viewerIsAuthor(of: post) {
                Text("post.viewedBy \(post.viewCount)")
                    .font(.chMicro)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func reactionBar(post: FeedPost) -> some View {
        HStack(spacing: Spacing.xs) {
            ForEach(ReactionType.allCases, id: \.rawValue) { reaction in
                reactionPill(reaction: reaction, post: post)
            }
        }
    }

    private func reactionPill(reaction: ReactionType, post: FeedPost) -> some View {
        let isOn = viewModel.myReactions.contains(reaction)
        let count = viewModel.reactionCounts[reaction] ?? 0

        return Button {
            Task { await viewModel.toggle(reaction, postId: post.postId) }
        } label: {
            HStack(spacing: 4) {
                Text(reaction.emoji)
                    .font(.system(size: 18))
                if count > 0 {
                    Text("\(count)")
                        .font(.chMicro.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isOn ? Color.chTether.opacity(0.85) : Color.white.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(isOn ? Color.chTether : Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(reaction.accessibilityLabelKey)))
        .accessibilityValue(count > 0 ? Text("\(count)") : Text(""))
        .accessibilityHint(Text(isOn ? "reaction.hint.on" : "reaction.hint.off"))
        .onLongPressGesture(minimumDuration: 0.4) {
            guard count > 0 else { return }
            reactorSheet = ReactorSheetPayload(reaction: reaction)
        }
    }

    // MARK: - Helpers

    private func timeAgo(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}

#Preview {
    NavigationStack {
        PostDetailView(
            carousel: PostCarousel(
                posts: [
                    FeedPost(
                        postId: UUID(),
                        authorId: UUID(),
                        authorName: "Alex",
                        authorAvatar: nil,
                        frontImagePath: "demo/front.jpg",
                        backImagePath: "demo/back.jpg",
                        caption: "morning at the diner",
                        postedAt: Date().addingTimeInterval(-7200),
                        isLate: false,
                        viewCount: 7,
                        reactionSummary: ["heart": 3, "fire": 1]
                    )
                ],
                initialId: UUID()
            ),
            currentUserId: UUID()
        )
    }
}
