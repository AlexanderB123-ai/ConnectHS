import SwiftUI
import UIKit

struct GroupOnboardingView: View {
    @Bindable var authViewModel: AuthViewModel
    let user: AppUser

    @State private var showCreateFlow = false
    @State private var showJoinFlow = false
    @State private var inviteCode = ""
    @State private var groupName = ""
    @State private var groupEmoji = ""
    @State private var error: String?
    @State private var isLoading = false
    @State private var sharePayload: SharePayload?

    @FocusState private var inviteFieldFocused: Bool
    @FocusState private var groupNameFocused: Bool

    private let groupService = GroupService()

    private struct SharePayload: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        ZStack {
            Color.chCream.ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer()

                Text("group.onboarding.greeting \(user.displayName.lowercased())")
                    .font(.chDisplay)
                    .foregroundStyle(.chInk)

                Text("group.onboarding.subtitle")
                    .font(.chBody)
                    .foregroundStyle(.chInkSoft)
                    .multilineTextAlignment(.center)

                Spacer()

                // Join a group
                Button {
                    showJoinFlow = true
                } label: {
                    Text("group.onboarding.join")
                        .font(.chHeadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(.chTether)
                        )
                }

                // Start a new group
                Button {
                    showCreateFlow = true
                } label: {
                    Text("group.onboarding.create")
                        .font(.chHeadline)
                        .foregroundStyle(.chInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .stroke(.chInk, lineWidth: 1.5)
                        )
                }

                Button {
                    authViewModel.skipGroupOnboarding(for: user)
                } label: {
                    Text("group.onboarding.skip")
                        .font(.chCaption)
                        .foregroundStyle(.chInkSoft)
                }

                Spacer()
                    .frame(height: Spacing.xl)
            }
            .padding(.horizontal, Spacing.lg)
        }
        .navigationTitle("")
        .sheet(isPresented: $showJoinFlow) {
            joinSheet
        }
        .sheet(isPresented: $showCreateFlow) {
            createSheet
        }
        .sheet(item: $sharePayload, onDismiss: {
            // After the share sheet closes, leave the create sheet and finish
            // bootstrap so RootView routes to MainTabView.
            showCreateFlow = false
            Task { await authViewModel.bootstrap() }
        }) { payload in
            ShareSheet(items: [payload.text])
        }
    }

    // MARK: - Join Sheet

    private var joinSheet: some View {
        NavigationStack {
            ZStack {
                Color.chCream.ignoresSafeArea()

                VStack(spacing: Spacing.lg) {
                    Text("group.join.title")
                        .font(.chHeadline)
                        .foregroundStyle(.chInk)

                    TextField(String(localized: "group.join.placeholder"), text: $inviteCode)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($inviteFieldFocused)
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(.white)
                        )
                        .padding(.horizontal, Spacing.lg)
                        .onAppear {
                            peekClipboardForInvite()
                            inviteFieldFocused = true
                        }

                    Button {
                        pasteInviteFromClipboard()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "doc.on.clipboard")
                            Text("group.join.paste")
                                .font(.chCaption)
                        }
                        .foregroundStyle(.chTether)
                    }

                    if let error {
                        Text(error)
                            .font(.chCaption)
                            .foregroundStyle(.chError)
                    }

                    Button {
                        Task { await joinGroup() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        } else {
                            Text("group.join.cta")
                                .font(.chHeadline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(!inviteCode.isEmpty ? .chTether : .chInkSoft.opacity(0.3))
                    )
                    .disabled(inviteCode.isEmpty || isLoading)
                    .padding(.horizontal, Spacing.lg)
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Create Sheet

    private var createSheet: some View {
        NavigationStack {
            ZStack {
                Color.chCream.ignoresSafeArea()

                VStack(spacing: Spacing.lg) {
                    Text("group.create.title")
                        .font(.chHeadline)
                        .foregroundStyle(.chInk)

                    TextField(String(localized: "group.create.name.placeholder"), text: $groupName)
                        .font(.chBody)
                        .focused($groupNameFocused)
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(.white)
                        )
                        .padding(.horizontal, Spacing.lg)
                        .onAppear { groupNameFocused = true }

                    TextField(String(localized: "group.create.emoji.placeholder"), text: $groupEmoji)
                        .font(.system(size: 32))
                        .multilineTextAlignment(.center)
                        .frame(width: 80, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(.white)
                        )

                    if let error {
                        Text(error)
                            .font(.chCaption)
                            .foregroundStyle(.chError)
                    }

                    Button {
                        Task { await createGroup() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        } else {
                            Text("group.create.cta")
                                .font(.chHeadline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(!groupName.isEmpty ? .chTether : .chInkSoft.opacity(0.3))
                    )
                    .disabled(groupName.isEmpty || isLoading)
                    .padding(.horizontal, Spacing.lg)

                    Button {
                        Task { await skipShareAndFinish() }
                    } label: {
                        Text("group.create.skip")
                            .font(.chCaption)
                            .foregroundStyle(.chInkSoft)
                    }
                    .padding(.top, Spacing.xs)
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Actions

    private func joinGroup() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        guard let code = InviteURL.extractCode(from: inviteCode), !code.isEmpty else {
            error = String(localized: "group.join.error.empty")
            return
        }
        do {
            _ = try await groupService.redeemInvite(code: code)
            showJoinFlow = false
            await authViewModel.bootstrap()
        } catch {
            self.error = String(localized: "group.join.error.invalid")
        }
    }

    private func createGroup() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let groupId = try await groupService.createGroup(
                name: groupName,
                emoji: groupEmoji.isEmpty ? nil : groupEmoji
            )
            // Generate the first invite immediately so the user can share it
            // while the moment is still warm. The share sheet's onDismiss will
            // finish onboarding by bootstrapping AuthViewModel. Users who tap
            // "skip" in the create sheet bypass this entirely.
            let code = try await groupService.createInvite(groupId: groupId)
            sharePayload = SharePayload(text: InviteURL.shareText(code: code))
        } catch {
            self.error = String(localized: "group.create.error")
        }
    }

    private func skipShareAndFinish() async {
        showCreateFlow = false
        await authViewModel.bootstrap()
    }

    private func pasteInviteFromClipboard() {
        guard let pasteboard = UIPasteboard.general.string,
              let code = InviteURL.extractCode(from: pasteboard) else { return }
        inviteCode = code
    }

    /// Pre-checks `UIPasteboard.hasURLs` — the metadata read doesn't trigger
    /// the paste banner. We only proceed to read `.string` when at least one
    /// URL is present AND it looks like our invite scheme. The single
    /// `.string` read still surfaces iOS's "pasted from…" notification once,
    /// which is acceptable here because we're explicitly opting into the
    /// "join an invite" surface.
    private func peekClipboardForInvite() {
        guard inviteCode.isEmpty, UIPasteboard.general.hasURLs else { return }
        guard let pasteboard = UIPasteboard.general.string,
              let url = URL(string: pasteboard.trimmingCharacters(in: .whitespacesAndNewlines)),
              InviteURL.isInvite(url),
              let code = InviteURL.extractCode(from: pasteboard) else { return }
        inviteCode = code
    }
}

#Preview {
    NavigationStack {
        GroupOnboardingView(
            authViewModel: AuthViewModel(),
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
