import Foundation
import Observation
import os
import Supabase

@MainActor
@Observable
final class AuthViewModel {

    enum State: Sendable {
        case loading
        case unauthenticated
        case authenticating
        case profileIncomplete(AppUser)
        case noGroup(AppUser)
        case active(AppUser)
    }

    private(set) var state: State = .loading
    private(set) var pendingInviteCode: String?
    private let authService = AuthService()
    private let groupService = GroupService()
    private let logger = Logger(subsystem: "com.connecths.app", category: "Auth")

    // MARK: - Phone OTP state

    var phoneNumber = ""
    var otpCode = ""
    var otpError: String?
    var isResendEnabled = false
    var resendCountdown = 30
    var appleNonce: String?

    // MARK: - Profile setup state

    var displayName = ""
    var highSchool = ""
    var gradYear: Int?
    /// Asserted on the welcome screen TOS line ("by continuing you confirm
    /// you're 13+…"). Set to true at sign-in time so we can drop the
    /// in-line toggle from ProfileSetup.
    var isAgeVerified = true

    // MARK: - Bootstrap

    func bootstrap() async {
        do {
            let session = try await authService.currentSession()
            let userId = session.user.id

            // Parallelize: existing-user fetch + memberships fetch happen
            // independently, only the routing decision below depends on both.
            async let userFetch = authService.fetchAppUser(id: userId)
            async let membershipsFetch = authService.fetchGroupMemberships(userId: userId)
            let appUser = try await userFetch
            let memberships = (try? await membershipsFetch) ?? []

            guard let appUser else {
                let newUser = AppUser(
                    id: userId,
                    displayName: "",
                    phoneNumber: session.user.phone,
                    appleUserId: nil,
                    authMethod: session.user.phone != nil ? .phone : .apple,
                    avatarUrl: nil,
                    highSchool: nil,
                    gradYear: nil,
                    birthday: nil,
                    timezone: TimeZone.current.identifier,
                    isAgeVerified: true,
                    isBlocked: false,
                    createdAt: Date(),
                    updatedAt: Date(),
                    deletedAt: nil
                )
                state = .profileIncomplete(newUser)
                return
            }

            if appUser.displayName.isEmpty {
                state = .profileIncomplete(appUser)
                return
            }

            state = memberships.isEmpty ? .noGroup(appUser) : .active(appUser)
        } catch {
            logger.info("No existing session, showing welcome")
            state = .unauthenticated
        }
    }

    // MARK: - Phone OTP

    func sendOTP() async {
        let formattedPhone = formatPhoneE164(phoneNumber)
        state = .authenticating
        otpError = nil
        do {
            try await authService.sendOTP(phone: formattedPhone)
        } catch {
            logger.error("OTP send failed: \(error.localizedDescription)")
            otpError = String(localized: "phone.error.send")
            state = .unauthenticated
        }
    }

    func verifyOTP() async {
        let formattedPhone = formatPhoneE164(phoneNumber)
        otpError = nil
        do {
            let session = try await authService.verifyOTP(phone: formattedPhone, code: otpCode)
            await handleAuthSuccess(session: session)
        } catch {
            logger.error("OTP verify failed: \(error.localizedDescription)")
            otpError = String(localized: "otp.error.invalid")
        }
    }

    // MARK: - Sign in with Apple

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async {
        state = .authenticating
        do {
            let session = try await authService.signInWithApple(idToken: idToken, nonce: nonce)
            if let givenName = fullName?.givenName, !givenName.isEmpty {
                displayName = givenName
            }
            await handleAuthSuccess(session: session)
        } catch {
            logger.error("Apple sign-in failed: \(error.localizedDescription)")
            otpError = String(localized: "auth.error.signIn")
            state = .unauthenticated
        }
    }

    // MARK: - Profile Setup

    func completeProfile(for user: AppUser) async {
        var updatedUser = user
        updatedUser.displayName = displayName
        updatedUser.highSchool = highSchool.isEmpty ? nil : highSchool
        updatedUser.gradYear = gradYear
        updatedUser.isAgeVerified = isAgeVerified
        updatedUser.updatedAt = Date()

        do {
            try await authService.upsertAppUser(updatedUser)
            if let code = pendingInviteCode {
                await redeemPendingInvite(code: code)
            }
            let memberships = try await authService.fetchGroupMemberships(userId: user.id)
            if memberships.isEmpty {
                state = .noGroup(updatedUser)
            } else {
                state = .active(updatedUser)
            }
        } catch {
            logger.error("Profile save failed: \(error.localizedDescription)")
            otpError = String(localized: "auth.error.profile")
        }
    }

    // MARK: - Deep links

    /// Called by `RootView` when a `connecths://invite/{code}` (or universal
    /// link equivalent) lands. If the user is already signed in, redeem
    /// immediately and re-bootstrap so `MainTabView` reloads with the new
    /// group available. Otherwise stash the code and let `handleAuthSuccess`
    /// pick it up after the user signs in.
    func processInvite(url: URL) async {
        guard InviteURL.isInvite(url) else { return }
        guard let code = InviteURL.extractCode(from: url.absoluteString) else {
            logger.error("Invite URL missing code: \(url.absoluteString, privacy: .public)")
            return
        }

        switch state {
        case .loading, .unauthenticated, .authenticating, .profileIncomplete:
            pendingInviteCode = code
        case .noGroup, .active:
            await redeemPendingInvite(code: code)
            await bootstrap()
        }
    }

    private func redeemPendingInvite(code: String) async {
        do {
            _ = try await groupService.redeemInvite(code: code)
            pendingInviteCode = nil
        } catch {
            logger.error("Invite redemption failed: \(error.localizedDescription)")
            otpError = String(localized: "auth.error.invite")
        }
    }

    // MARK: - Profile edit (post-setup)

    /// Edit the existing profile from inside MainTabView (ProfileEditView).
    /// Does NOT transition state — we stay in `.active`/`.noGroup` and just
    /// re-emit the same case with the updated user so observers refresh.
    func updateProfile(
        for user: AppUser,
        displayName: String,
        highSchool: String?,
        gradYear: Int?
    ) async throws {
        var updated = user
        updated.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.highSchool = (highSchool?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        updated.gradYear = gradYear
        updated.updatedAt = Date()

        try await authService.upsertAppUser(updated)

        switch state {
        case .active:
            state = .active(updated)
        case .noGroup:
            state = .noGroup(updated)
        case .profileIncomplete:
            state = .profileIncomplete(updated)
        case .loading, .unauthenticated, .authenticating:
            break
        }
    }

    // MARK: - Skip group onboarding

    /// Per spec/04: a "skip for now" path lets the user enter the main app
    /// without a group. They land on FeedView's empty state and can create
    /// or join a group later from profile.
    func skipGroupOnboarding(for user: AppUser) {
        state = .active(user)
    }

    // MARK: - Account deletion

    /// App Store guideline 5.1.1(v): apps that support account creation
    /// must offer in-app account deletion. Soft-delete via the RPC, then
    /// clear local state (widget, push token, session). Returns true on
    /// success so ProfileView can dismiss the confirmation flow.
    func deleteAccount() async -> Bool {
        do {
            try await authService.deleteMyAccount()
        } catch {
            logger.error("Account deletion failed: \(error.localizedDescription)")
            otpError = String(localized: "auth.error.deleteAccount")
            return false
        }
        await WidgetSyncService.shared.clear()
        await SignedURLCache.shared.clear()
        try? await PushService().unregisterCurrentDevice()
        do {
            try await authService.signOut()
        } catch {
            logger.error("Sign out after deletion failed: \(error.localizedDescription)")
        }
        state = .unauthenticated
        return true
    }

    // MARK: - Sign Out

    func signOut() async {
        // Best-effort: clear the widget so the next user doesn't see the
        // previous user's moment, and drop the APNs token so the abandoned
        // device doesn't keep getting pushes. Failures here must not block
        // sign-out.
        await WidgetSyncService.shared.clear()
        await SignedURLCache.shared.clear()
        try? await PushService().unregisterCurrentDevice()
        do {
            try await authService.signOut()
        } catch {
            logger.error("Sign out error: \(error.localizedDescription)")
        }
        state = .unauthenticated
    }

    // MARK: - Helpers

    private func handleAuthSuccess(session: Auth.Session) async {
        let userId = session.user.id
        do {
            if let appUser = try await authService.fetchAppUser(id: userId) {
                if appUser.displayName.isEmpty {
                    state = .profileIncomplete(appUser)
                } else {
                    if let code = pendingInviteCode {
                        await redeemPendingInvite(code: code)
                    }
                    let memberships = try await authService.fetchGroupMemberships(userId: userId)
                    state = memberships.isEmpty ? .noGroup(appUser) : .active(appUser)
                }
            } else {
                let newUser = AppUser(
                    id: userId,
                    displayName: displayName,
                    phoneNumber: session.user.phone,
                    appleUserId: nil,
                    authMethod: session.user.phone != nil ? .phone : .apple,
                    avatarUrl: nil,
                    highSchool: nil,
                    gradYear: nil,
                    birthday: nil,
                    timezone: TimeZone.current.identifier,
                    isAgeVerified: false,
                    isBlocked: false,
                    createdAt: Date(),
                    updatedAt: Date(),
                    deletedAt: nil
                )
                if newUser.displayName.isEmpty {
                    state = .profileIncomplete(newUser)
                } else {
                    try await authService.upsertAppUser(newUser)
                    state = .noGroup(newUser)
                }
            }
        } catch {
            logger.error("Post-auth user fetch failed: \(error.localizedDescription)")
            state = .unauthenticated
        }
    }

    private func formatPhoneE164(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        if digits.hasPrefix("1") && digits.count == 11 {
            return "+\(digits)"
        } else if digits.count == 10 {
            return "+1\(digits)"
        }
        return "+\(digits)"
    }
}
