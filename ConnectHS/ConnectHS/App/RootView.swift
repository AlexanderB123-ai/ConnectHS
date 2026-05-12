import SwiftUI

struct RootView: View {
    @State private var viewModel = AuthViewModel()
    @State private var router = DeepLinkRouter.shared

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                loadingView

            case .unauthenticated, .authenticating:
                NavigationStack {
                    WelcomeView(viewModel: viewModel)
                }

            case .profileIncomplete(let user):
                NavigationStack {
                    ProfileSetupView(viewModel: viewModel, user: user)
                }

            case .noGroup(let user):
                NavigationStack {
                    GroupOnboardingView(authViewModel: viewModel, user: user)
                }

            case .active(let user):
                MainTabView(user: user, authViewModel: viewModel)
            }
        }
        .task {
            await viewModel.bootstrap()
            await drainInviteIfPresent()
        }
        .onChange(of: router.pending) { _, url in
            guard let url, InviteURL.isInvite(url) else { return }
            // Route invites here so they fire even before MainTabView mounts.
            // Other deep-link kinds (post/memory/camera/group switch) are
            // handled inside MainTabView when state == .active.
            DeepLinkRouter.shared.clear()
            Task { await viewModel.processInvite(url: url) }
        }
    }

    private func drainInviteIfPresent() async {
        guard let url = DeepLinkRouter.shared.pending, InviteURL.isInvite(url) else { return }
        DeepLinkRouter.shared.clear()
        await viewModel.processInvite(url: url)
    }

    private var loadingView: some View {
        ZStack {
            Color.chCream.ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                Text("connecths")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.chInk)
                ProgressView()
                    .tint(.chTether)
            }
        }
    }
}

#Preview {
    RootView()
}
