import SwiftUI

struct GroupSettingsView: View {

    let group: FriendGroup
    let currentUserId: UUID
    let onLeave: () -> Void
    let onMutate: () -> Void

    @State private var viewModel: GroupSettingsViewModel
    @State private var showEditSheet = false
    @State private var showLeaveConfirm = false
    @State private var memberToActOn: GroupMember?
    @State private var memberToReport: GroupMember?
    @State private var showReportConfirmation = false
    @Environment(\.dismiss) private var dismiss

    init(
        group: FriendGroup,
        currentUserId: UUID,
        onLeave: @escaping () -> Void,
        onMutate: @escaping () -> Void
    ) {
        self.group = group
        self.currentUserId = currentUserId
        self.onLeave = onLeave
        self.onMutate = onMutate
        _viewModel = State(initialValue: GroupSettingsViewModel(
            group: group,
            currentUserId: currentUserId
        ))
    }

    var body: some View {
        ZStack {
            Color.chCream.ignoresSafeArea()

            switch viewModel.loadState {
            case .loading:
                ProgressView().tint(.chTether)
            case .error(let message):
                errorView(message)
            case .loaded:
                content
            }
        }
        .navigationTitle(Text("group.settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .onChange(of: viewModel.lastMutationToken) { _, _ in onMutate() }
        .sheet(isPresented: $showEditSheet) {
            editSheet
        }
        .sheet(item: invitePayloadBinding) { payload in
            ShareSheet(items: [payload.text])
        }
        .alert(Text("group.settings.leave.title \(group.name)"), isPresented: $showLeaveConfirm) {
            Button(role: .destructive) {
                Task {
                    let ok = await viewModel.leaveGroup()
                    if ok {
                        onLeave()
                        dismiss()
                    }
                }
            } label: {
                Text("group.settings.leave.confirm.cta")
            }
            Button(role: .cancel) {} label: { Text("common.cancel") }
        } message: {
            Text(leaveMessage)
        }
        .alert(Text("group.settings.error.couldntComplete"), isPresented: actionErrorBinding) {
            Button(role: .cancel) { viewModel.actionError = nil } label: { Text("common.ok") }
        } message: {
            Text(viewModel.actionError ?? "")
        }
        .confirmationDialog(
            memberToActOn.map(memberDialogTitle) ?? "",
            isPresented: memberDialogBinding,
            presenting: memberToActOn
        ) { member in
            if viewModel.isAdmin && member.userId != currentUserId {
                if member.role != .admin {
                    Button {
                        Task { await viewModel.promoteAdmin(member); memberToActOn = nil }
                    } label: {
                        Text("group.settings.member.action.makeAdmin")
                    }
                }
                Button(role: .destructive) {
                    Task { await viewModel.removeMember(member); memberToActOn = nil }
                } label: {
                    Text("group.settings.member.action.remove")
                }
            }
            // Report + block available to ANY non-self member, regardless of
            // admin status — App Store requires both for UGC apps.
            if member.userId != currentUserId {
                Button(role: .destructive) {
                    let m = member
                    memberToActOn = nil
                    memberToReport = m
                } label: {
                    Text("report.member.action")
                }
                Button(role: .destructive) {
                    let m = member
                    memberToActOn = nil
                    Task { await viewModel.blockMember(m); onMutate() }
                } label: {
                    Text("blocks.action")
                }
            }
            Button(role: .cancel) { memberToActOn = nil } label: { Text("common.cancel") }
        }
        .sheet(item: $memberToReport) { member in
            ReportSheet(
                target: .user(id: member.userId, displayName: member.displayName),
                onSubmitted: { showReportConfirmation = true }
            )
        }
        .alert(Text("report.confirmation.title"), isPresented: $showReportConfirmation) {
            Button(role: .cancel) {} label: { Text("common.ok") }
        } message: {
            Text("report.confirmation.message")
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                    .padding(.horizontal, Spacing.md)

                membersSection
                    .padding(.horizontal, Spacing.md)

                inviteSection
                    .padding(.horizontal, Spacing.md)

                dangerZone
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.md)
            }
            .padding(.vertical, Spacing.md)
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            Text(group.emoji ?? "🌱")
                .font(.system(size: 56))
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.chDisplay)
                    .foregroundStyle(.chInk)
                    .lineLimit(2)
                Text("group.settings.members.count \(viewModel.members.count)")
                    .font(.chCaption)
                    .foregroundStyle(.chInkSoft)
            }
            Spacer()
            if viewModel.isAdmin {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.chInk)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.chPeach.opacity(0.5)))
                }
                .accessibilityLabel(Text("group.settings.edit.label"))
            }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("group.settings.members.section")
                .font(.chHeadline)
                .foregroundStyle(.chInk)

            VStack(spacing: 0) {
                ForEach(viewModel.members) { member in
                    Button {
                        memberToActOn = member
                    } label: {
                        memberRow(member)
                    }
                    .buttonStyle(.plain)
                    .disabled(member.userId == currentUserId && !viewModel.isAdmin)
                    if member.id != viewModel.members.last?.id {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(.white)
            )
        }
    }

    private func memberRow(_ member: GroupMember) -> some View {
        HStack(spacing: Spacing.sm) {
            AvatarView(
                name: member.displayName,
                avatarPath: member.avatarUrl,
                size: 40
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.displayName.lowercased())
                        .font(.chBody.weight(.semibold))
                        .foregroundStyle(.chInk)
                    if member.role == .admin {
                        Text("group.settings.member.adminBadge")
                            .font(.chMicro)
                            .foregroundStyle(.chTether)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.chTether.opacity(0.12)))
                    }
                    if member.userId == currentUserId {
                        Text("group.settings.member.youBadge")
                            .font(.chMicro)
                            .foregroundStyle(.chInkSoft)
                    }
                }
                Text("group.settings.member.joinedDate \(formatDate(member.joinedAt))")
                    .font(.chMicro)
                    .foregroundStyle(.chInkSoft)
            }

            Spacer()
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .contentShape(Rectangle())
    }

    private var inviteSection: some View {
        Button {
            Task { await viewModel.generateInvite() }
        } label: {
            HStack {
                Image(systemName: "link")
                Text("group.settings.invite.cta")
                    .font(.chHeadline)
                Spacer()
                if viewModel.actionInFlight {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(.chTether)
            )
        }
        .disabled(viewModel.actionInFlight)
    }

    private var dangerZone: some View {
        Button(role: .destructive) {
            showLeaveConfirm = true
        } label: {
            Text("group.settings.leave")
                .font(.chHeadline)
                .foregroundStyle(.chError)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(.chError, lineWidth: 1.5)
                )
        }
    }

    // MARK: - Edit sheet

    private var editSheet: some View {
        NavigationStack {
            EditGroupSheet(
                initialName: group.name,
                initialEmoji: group.emoji ?? "",
                onSave: { name, emoji in
                    Task {
                        await viewModel.updateGroup(name: name, emoji: emoji.isEmpty ? nil : emoji)
                        showEditSheet = false
                    }
                },
                onCancel: { showEditSheet = false }
            )
        }
    }

    // MARK: - Helpers

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Text(message).font(.chHeadline).foregroundStyle(.chInk)
            Button {
                Task { await viewModel.load() }
            } label: {
                Text("common.retry")
            }
            .foregroundStyle(.chTether)
        }
    }

    private var leaveMessage: LocalizedStringKey {
        if viewModel.isAdmin && viewModel.members.count > 1 {
            return "group.settings.leave.message.admin"
        }
        return "group.settings.leave.message.member"
    }

    private func memberDialogTitle(_ member: GroupMember) -> String {
        member.displayName.lowercased()
    }

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date).lowercased()
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    // MARK: - Bindings

    private var invitePayloadBinding: Binding<InvitePayloadWrapper?> {
        Binding(
            get: {
                guard let text = viewModel.inviteText else { return nil }
                return InvitePayloadWrapper(text: text)
            },
            set: { newValue in
                if newValue == nil { viewModel.inviteText = nil }
            }
        )
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.actionError != nil },
            set: { if !$0 { viewModel.actionError = nil } }
        )
    }

    private var memberDialogBinding: Binding<Bool> {
        Binding(
            get: { memberToActOn != nil },
            set: { if !$0 { memberToActOn = nil } }
        )
    }

    private struct InvitePayloadWrapper: Identifiable {
        let id = UUID()
        let text: String
    }
}

private struct EditGroupSheet: View {
    let initialName: String
    let initialEmoji: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var emoji: String

    init(initialName: String, initialEmoji: String, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.initialName = initialName
        self.initialEmoji = initialEmoji
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: initialName)
        _emoji = State(initialValue: initialEmoji)
    }

    var body: some View {
        ZStack {
            Color.chCream.ignoresSafeArea()
            VStack(spacing: Spacing.lg) {
                Text("group.edit.title")
                    .font(.chHeadline)
                    .foregroundStyle(.chInk)

                TextField(String(localized: "group.edit.name.placeholder"), text: $name)
                    .font(.chBody)
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md).fill(.white)
                    )
                    .padding(.horizontal, Spacing.lg)

                TextField(String(localized: "group.edit.emoji.placeholder"), text: $emoji)
                    .font(.system(size: 32))
                    .multilineTextAlignment(.center)
                    .frame(width: 80, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md).fill(.white)
                    )

                Button {
                    onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), emoji)
                } label: {
                    Text("group.edit.save")
                        .font(.chHeadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .chInkSoft.opacity(0.3) : .chTether)
                        )
                        .padding(.horizontal, Spacing.lg)
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(action: onCancel) {
                    Text("group.edit.cancel")
                }
                    .foregroundStyle(.chInkSoft)
                    .padding(.bottom, Spacing.md)
            }
            .padding(.top, Spacing.lg)
        }
        .presentationDetents([.medium])
    }
}
