import SwiftUI

/// Manage-blocks list: shows everyone the caller has blocked with an
/// unblock affordance. Reachable from ProfileView via NavigationLink.
struct BlockedUsersView: View {

    @State private var blocks: [BlockedUser] = []
    @State private var loadState: LoadState = .loading
    @State private var actionInFlight: Set<UUID> = []
    @State private var unblockError: String?

    private enum LoadState: Sendable { case loading, loaded, error }
    private let service = BlockService()

    var body: some View {
        ZStack {
            Color.chCream.ignoresSafeArea()

            switch loadState {
            case .loading:
                ProgressView().tint(.chTether)
            case .error:
                VStack(spacing: Spacing.sm) {
                    Text("blocks.error")
                        .foregroundStyle(.chError)
                    Button {
                        Task { await load() }
                    } label: {
                        Text("common.retry")
                    }
                    .foregroundStyle(.chTether)
                }
            case .loaded:
                if blocks.isEmpty {
                    emptyView
                } else {
                    list
                }
            }
        }
        .navigationTitle(Text("blocks.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert(Text("blocks.error.title"), isPresented: Binding(
            get: { unblockError != nil },
            set: { if !$0 { unblockError = nil } }
        )) {
            Button(role: .cancel) { unblockError = nil } label: { Text("common.ok") }
        } message: {
            Text(unblockError ?? "")
        }
    }

    private var emptyView: some View {
        VStack(spacing: Spacing.sm) {
            Text("blocks.empty.title")
                .font(.chHeadline)
                .foregroundStyle(.chInk)
            Text("blocks.empty.subtitle")
                .font(.chBody)
                .foregroundStyle(.chInkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
        }
    }

    private var list: some View {
        List(blocks) { block in
            HStack(spacing: Spacing.md) {
                AvatarView(name: block.displayName, avatarPath: block.avatarUrl, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.displayName.lowercased())
                        .font(.chBody)
                        .foregroundStyle(.chInk)
                    Text("blocks.since \(formatDate(block.blockedAt))")
                        .font(.chMicro)
                        .foregroundStyle(.chInkSoft)
                }
                Spacer()
                Button {
                    Task { await unblock(block) }
                } label: {
                    if actionInFlight.contains(block.userId) {
                        ProgressView()
                    } else {
                        Text("blocks.unblock")
                            .font(.chCaption)
                            .foregroundStyle(.chTether)
                    }
                }
                .disabled(actionInFlight.contains(block.userId))
            }
            .listRowBackground(Color.chCream)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func load() async {
        loadState = .loading
        do {
            blocks = try await service.listMyBlocks()
            loadState = .loaded
        } catch {
            loadState = .error
        }
    }

    private func unblock(_ block: BlockedUser) async {
        actionInFlight.insert(block.userId)
        defer { actionInFlight.remove(block.userId) }
        do {
            try await service.unblock(targetId: block.userId)
            blocks.removeAll { $0.userId == block.userId }
        } catch {
            unblockError = String(localized: "blocks.error.unblock")
        }
    }

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date).lowercased()
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}
