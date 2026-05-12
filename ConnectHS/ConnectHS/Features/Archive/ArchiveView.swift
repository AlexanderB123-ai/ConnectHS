import SwiftUI

struct ArchiveView: View {
    let user: AppUser

    @State private var viewModel = ArchiveViewModel()

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm)
    ]

    var body: some View {
        ZStack {
            Color.chCream.ignoresSafeArea()

            switch viewModel.loadState {
            case .loading:
                ProgressView().tint(.chTether)
            case .error(let message):
                errorView(message)
            case .empty:
                emptyView
            case .posts:
                gridContent
            }
        }
        .navigationTitle(Text("archive.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu
            }
        }
        .navigationDestination(for: PostCarousel.self) { carousel in
            PostDetailView(carousel: carousel, currentUserId: user.id)
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Filter

    @ViewBuilder
    private var filterMenu: some View {
        Menu {
            Button {
                Task { await viewModel.toggleOnlyMine() }
            } label: {
                if viewModel.onlyMine {
                    Label {
                        Text("archive.filter.onlyMine")
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                } else {
                    Text("archive.filter.onlyMine")
                }
            }
        } label: {
            Image(systemName: viewModel.onlyMine ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .foregroundStyle(.chTether)
        }
    }

    // MARK: - Grid

    private var gridContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg, pinnedViews: [.sectionHeaders]) {
                ForEach(viewModel.sections) { section in
                    Section {
                        LazyVGrid(columns: columns, spacing: Spacing.sm) {
                            ForEach(section.posts) { post in
                                NavigationLink(value: PostCarousel(
                                    posts: section.posts.map { $0.asFeedPost },
                                    initialId: post.id
                                )) {
                                    ArchiveThumbnail(post: post)
                                }
                                .buttonStyle(.plain)
                                .task {
                                    if post.id == viewModel.sections.last?.posts.last?.id {
                                        await viewModel.loadMore()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    } header: {
                        Text(section.title)
                            .font(.chHeadline)
                            .foregroundStyle(.chInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(Color.chCream)
                    }
                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView().tint(.chTether)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.md)
                }
            }
            .padding(.vertical, Spacing.md)
        }
    }

    // MARK: - Empty / error

    private var emptyView: some View {
        VStack(spacing: Spacing.md) {
            Text("archive.empty.title")
                .font(.chHeadline)
                .foregroundStyle(.chInk)
            Text("archive.empty.subtitle")
                .font(.chBody)
                .foregroundStyle(.chInkSoft)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Text(message)
                .font(.chHeadline)
                .foregroundStyle(.chInk)
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

// MARK: - Thumbnail

private struct ArchiveThumbnail: View {
    let post: ArchivePost

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RemoteImage(imagePath: post.backImagePath)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))

            RemoteImage(imagePath: post.frontImagePath)
                .aspectRatio(3.0 / 4.0, contentMode: .fill)
                .frame(width: 28, height: 36)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.white.opacity(0.6), lineWidth: 1)
                )
                .padding(3)
        }
    }
}

#Preview {
    NavigationStack {
        ArchiveView(
            user: AppUser(
                id: UUID(),
                displayName: "Alex",
                authMethod: .phone,
                timezone: "America/New_York",
                isAgeVerified: true,
                isBlocked: false,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
    }
}
