import SwiftUI
import PhotosUI
import UIKit
import UserNotifications

struct ProfileView: View {
    let user: AppUser
    @Bindable var authViewModel: AuthViewModel

    @State private var showSignOutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var deletingAccount = false
    @State private var notifVM: NotificationSettingsViewModel
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var avatarPath: String?
    @State private var avatarUploadError: String?
    @State private var avatarUploading = false
    @State private var pushPermissionDenied = false
    /// Bumped after each successful avatar upload so AvatarView's `.id()`
    /// changes and SwiftUI rebuilds it. Without this, re-uploading to the
    /// same Storage path (`{user_id}/avatar.jpg`) wouldn't change
    /// avatarPath, AvatarView's `.task(id: avatarPath)` wouldn't re-fire,
    /// and the user would keep seeing the previous (cached) signed URL.
    @State private var avatarRefreshToken = UUID()

    @Environment(\.scenePhase) private var scenePhase

    private let avatarService = AvatarService()

    init(user: AppUser, authViewModel: AuthViewModel) {
        self.user = user
        self.authViewModel = authViewModel
        _notifVM = State(initialValue: NotificationSettingsViewModel(userId: user.id))
        _avatarPath = State(initialValue: user.avatarUrl)
    }

    var body: some View {
        ZStack {
            Color.chCream.ignoresSafeArea()

            List {
                // Profile header
                Section {
                    HStack(spacing: Spacing.md) {
                        PhotosPicker(
                            selection: $avatarPickerItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            ZStack(alignment: .bottomTrailing) {
                                AvatarView(
                                    name: user.displayName,
                                    avatarPath: avatarPath,
                                    size: 60
                                )
                                .id(avatarRefreshToken)
                                if avatarUploading {
                                    Circle()
                                        .fill(.black.opacity(0.4))
                                        .frame(width: 60, height: 60)
                                        .overlay { ProgressView().tint(.white) }
                                } else {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(.chTether))
                                        .overlay(Circle().stroke(.chCream, lineWidth: 2))
                                        .offset(x: 2, y: 2)
                                }
                            }
                        }
                        .accessibilityLabel(Text("avatar.editor.label"))
                        .disabled(avatarUploading)

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(user.displayName)
                                .font(.chHeadline)
                                .foregroundStyle(.chInk)
                            if let school = user.highSchool {
                                Text(school)
                                    .font(.chCaption)
                                    .foregroundStyle(.chInkSoft)
                            }
                            if let year = user.gradYear {
                                Text("profile.classOf \(String(year))")
                                    .font(.chCaption)
                                    .foregroundStyle(.chInkSoft)
                            }
                        }

                        Spacer()

                        NavigationLink {
                            ProfileEditView(user: user, authViewModel: authViewModel)
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.chInkSoft)
                        }
                        .accessibilityLabel(Text("profile.edit.cta"))
                    }
                    .listRowBackground(Color.chCream)
                }

                notificationsSection

                quietHoursSection

                // About
                Section(header: Text("profile.about.section")) {
                    HStack {
                        Text("profile.about.signInMethod")
                        Spacer()
                        Text(authMethodLabel)
                            .foregroundStyle(.chInkSoft)
                    }
                    HStack {
                        Text("profile.about.joinedOn")
                        Spacer()
                        Text(Self.dateFormatter.string(from: user.createdAt).lowercased())
                            .foregroundStyle(.chInkSoft)
                    }
                    HStack {
                        Text("profile.about.version")
                        Spacer()
                        Text(Self.bundleVersion)
                            .foregroundStyle(.chInkSoft)
                    }
                    Text("profile.about.author")
                        .foregroundStyle(.chInkSoft)
                }

                // Privacy / safety
                Section {
                    NavigationLink {
                        BlockedUsersView()
                    } label: {
                        Label {
                            Text("blocks.entry")
                        } icon: {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(.chTether)
                        }
                    }
                }

                // Sign out
                Section {
                    Button(role: .destructive) {
                        showSignOutConfirmation = true
                    } label: {
                        Text("profile.signOut")
                    }
                }

                // Delete account (App Store guideline 5.1.1(v))
                Section {
                    Button(role: .destructive) {
                        showDeleteAccountConfirmation = true
                    } label: {
                        if deletingAccount {
                            HStack {
                                ProgressView()
                                Text("profile.deleteAccount.inProgress")
                            }
                        } else {
                            Text("profile.deleteAccount")
                        }
                    }
                    .disabled(deletingAccount)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(Text("profile.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await notifVM.load()
            await refreshPushPermission()
        }
        .onChange(of: scenePhase) { previous, current in
            // User likely came back from Settings.app where they may have
            // flipped the push toggle — re-check so the banner reflects
            // reality without forcing a manual nav-out-and-back.
            guard current == .active, previous == .background else { return }
            Task { await refreshPushPermission() }
        }
        .onDisappear { notifVM.cancelPendingSave() }
        .onChange(of: avatarPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await handleAvatarPick(newItem) }
        }
        .alert(Text("avatar.error.upload"), isPresented: Binding(
            get: { avatarUploadError != nil },
            set: { if !$0 { avatarUploadError = nil } }
        )) {
            Button(role: .cancel) { avatarUploadError = nil } label: { Text("common.ok") }
        } message: {
            Text(avatarUploadError ?? "")
        }
        .alert(Text("profile.signOut.confirm.title"), isPresented: $showSignOutConfirmation) {
            Button(role: .destructive) {
                Task { await authViewModel.signOut() }
            } label: {
                Text("profile.signOut")
            }
            Button(role: .cancel) {} label: { Text("common.cancel") }
        } message: {
            Text("profile.signOut.confirm.message")
        }
        .alert(Text("profile.deleteAccount.confirm.title"), isPresented: $showDeleteAccountConfirmation) {
            Button(role: .destructive) {
                Task {
                    deletingAccount = true
                    _ = await authViewModel.deleteAccount()
                    deletingAccount = false
                }
            } label: {
                Text("profile.deleteAccount.confirm.cta")
            }
            Button(role: .cancel) {} label: { Text("common.cancel") }
        } message: {
            Text("profile.deleteAccount.confirm.message")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            switch notifVM.loadState {
            case .loading:
                HStack {
                    Spacer()
                    ProgressView().tint(.chTether)
                    Spacer()
                }
            case .error:
                HStack {
                    Text("profile.notifications.loadError")
                        .foregroundStyle(.chError)
                    Spacer()
                    Button {
                        Task { await notifVM.load() }
                    } label: {
                        Text("common.retry")
                            .foregroundStyle(.chTether)
                    }
                }
            case .loaded:
                if pushPermissionDenied {
                    // Without OS-level permission these toggles are no-ops —
                    // the server-side opt-ins still get respected, but APNs
                    // never delivers anything to a denied app. Send the user
                    // to Settings to flip it.
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.chWarning)
                                Text("profile.notifications.permissionDenied.title")
                                    .foregroundStyle(.chInk)
                                    .font(.chBody)
                            }
                            Text("profile.notifications.permissionDenied.subtitle")
                                .font(.chMicro)
                                .foregroundStyle(.chInkSoft)
                        }
                    }
                }
                Toggle(isOn: dailyPromptBinding) { Text("profile.notifications.dailyPrompt") }
                    .disabled(pushPermissionDenied)
                Toggle(isOn: newPostBinding) { Text("profile.notifications.newPosts") }
                    .disabled(pushPermissionDenied)
                Toggle(isOn: memoryBinding) { Text("profile.notifications.memories") }
                    .disabled(pushPermissionDenied)
                Toggle(isOn: reactionBinding) { Text("profile.notifications.reactions") }
                    .disabled(pushPermissionDenied)
            }
        } header: {
            HStack {
                Text("profile.notifications.section")
                Spacer()
                if notifVM.saving {
                    ProgressView().controlSize(.small)
                } else if let err = notifVM.lastError {
                    Text(err)
                        .font(.chMicro)
                        .foregroundStyle(.chError)
                        .textCase(.none)
                }
            }
        }
        .tint(.chTether)
    }

    @ViewBuilder
    private var quietHoursSection: some View {
        if case .loaded = notifVM.loadState, notifVM.settings != nil {
            Section(header: Text("profile.quietHours.section"),
                    footer: Text("profile.quietHours.footer")) {
                DatePicker(
                    selection: windowStartBinding,
                    displayedComponents: .hourAndMinute
                ) {
                    Text("profile.quietHours.start")
                }
                DatePicker(
                    selection: windowEndBinding,
                    displayedComponents: .hourAndMinute
                ) {
                    Text("profile.quietHours.end")
                }
            }
            .tint(.chTether)
        }
    }

    // MARK: - Bindings

    private var dailyPromptBinding: Binding<Bool> {
        Binding(
            get: { notifVM.settings?.dailyPromptEnabled ?? true },
            set: { newValue in notifVM.apply { $0.dailyPromptEnabled = newValue } }
        )
    }

    private var newPostBinding: Binding<Bool> {
        Binding(
            get: { notifVM.settings?.newPostEnabled ?? true },
            set: { newValue in notifVM.apply { $0.newPostEnabled = newValue } }
        )
    }

    private var memoryBinding: Binding<Bool> {
        Binding(
            get: { notifVM.settings?.memoryEnabled ?? true },
            set: { newValue in notifVM.apply { $0.memoryEnabled = newValue } }
        )
    }

    private var reactionBinding: Binding<Bool> {
        Binding(
            get: { notifVM.settings?.reactionEnabled ?? true },
            set: { newValue in notifVM.apply { $0.reactionEnabled = newValue } }
        )
    }

    private var windowStartBinding: Binding<Date> {
        Binding(
            get: { Self.parseClock(notifVM.settings?.dailyPromptWindowStart ?? "10:00:00") },
            set: { date in
                let raw = Self.formatClock(date)
                notifVM.apply { $0.dailyPromptWindowStart = raw }
            }
        )
    }

    private var windowEndBinding: Binding<Date> {
        Binding(
            get: { Self.parseClock(notifVM.settings?.dailyPromptWindowEnd ?? "22:00:00") },
            set: { date in
                let raw = Self.formatClock(date)
                notifVM.apply { $0.dailyPromptWindowEnd = raw }
            }
        )
    }

    // MARK: - Time helpers

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static func parseClock(_ raw: String) -> Date {
        clockFormatter.date(from: raw) ?? Date()
    }

    private static func formatClock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    private static var bundleVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var authMethodLabel: String {
        switch user.authMethod {
        case .phone: return String(localized: "profile.about.signInMethod.phone")
        case .apple: return String(localized: "profile.about.signInMethod.apple")
        }
    }

    // MARK: - Push permission

    private func refreshPushPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        // Only treat .denied as actively-broken — .notDetermined means we
        // haven't asked yet (MainTabView's first-launch prompt handles it),
        // and .ephemeral / .provisional still deliver something.
        pushPermissionDenied = settings.authorizationStatus == .denied
    }

    // MARK: - Avatar upload

    private func handleAvatarPick(_ item: PhotosPickerItem) async {
        avatarUploading = true
        defer { avatarUploading = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                avatarUploadError = String(localized: "avatar.error.encodeFailed")
                return
            }
            let path = try await avatarService.upload(image: image, userId: user.id)
            avatarPath = path
            avatarRefreshToken = UUID()
        } catch {
            avatarUploadError = String(localized: "avatar.error.upload")
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView(
            user: AppUser(
                id: UUID(),
                displayName: "Alex",
                authMethod: .phone,
                highSchool: "Lincoln High",
                gradYear: 2026,
                timezone: "America/New_York",
                isAgeVerified: true,
                isBlocked: false,
                createdAt: Date(),
                updatedAt: Date()
            ),
            authViewModel: AuthViewModel()
        )
    }
}
