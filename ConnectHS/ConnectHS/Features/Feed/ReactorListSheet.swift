import SwiftUI

/// Long-press a reaction pill on PostDetailView → this sheet. Lists every
/// group member who reacted with that emoji, ordered by when they reacted.
/// Pure presentational; loads via `PostService.listReactors` on appear.
struct ReactorListSheet: View {

    let postId: UUID
    let reaction: ReactionType

    @State private var reactors: [PostReactor] = []
    @State private var loadState: LoadState = .loading
    @Environment(\.dismiss) private var dismiss

    private enum LoadState: Sendable { case loading, loaded, error }
    private let postService = PostService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chCream.ignoresSafeArea()
                content
            }
            .navigationTitle(Text("post.reactors.title \(reaction.emoji)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("common.ok")
                    }
                }
            }
            .task { await load() }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView().tint(.chTether)
        case .error:
            VStack(spacing: Spacing.sm) {
                Text("post.reactors.error")
                    .foregroundStyle(.chError)
                Button {
                    Task { await load() }
                } label: {
                    Text("common.retry")
                }
                .foregroundStyle(.chTether)
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        List(reactors) { reactor in
            HStack(spacing: Spacing.md) {
                AvatarView(
                    name: reactor.displayName,
                    avatarPath: reactor.avatarUrl,
                    size: 36
                )
                Text(reactor.displayName.lowercased())
                    .font(.chBody)
                    .foregroundStyle(.chInk)
                Spacer()
                Text(timeAgo(reactor.reactedAt))
                    .font(.chMicro)
                    .foregroundStyle(.chInkSoft)
            }
            .listRowBackground(Color.chCream)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func load() async {
        loadState = .loading
        do {
            reactors = try await postService.listReactors(postId: postId, reaction: reaction)
            loadState = .loaded
        } catch {
            loadState = .error
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
