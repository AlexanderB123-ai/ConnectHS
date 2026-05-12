import Foundation
import Supabase
import Auth

struct AuthService: Sendable {

    // MARK: - Phone OTP

    func sendOTP(phone: String) async throws {
        try await supabase.auth.signInWithOTP(phone: phone)
    }

    func verifyOTP(phone: String, code: String) async throws -> Session {
        let response = try await supabase.auth.verifyOTP(
            phone: phone,
            token: code,
            type: .sms
        )
        guard let session = response.session else {
            throw AuthError.sessionMissing
        }
        return session
    }

    // MARK: - Sign in with Apple

    func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        let session = try await supabase.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
        return session
    }

    // MARK: - Session

    func currentSession() async throws -> Session {
        try await supabase.auth.session
    }

    func currentUser() async throws -> Auth.User? {
        try await supabase.auth.session.user
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
    }

    // MARK: - User Profile

    func fetchAppUser(id: UUID) async throws -> AppUser? {
        let response: [AppUser] = try await supabase
            .from("users")
            .select()
            .eq("id", value: id.uuidString)
            .execute()
            .value
        return response.first
    }

    func upsertAppUser(_ user: AppUser) async throws {
        try await supabase
            .from("users")
            .upsert(user)
            .execute()
    }

    /// Soft-deletes the caller's public.users row + memberships + posts, and
    /// drops their device tokens. The auth.users row is intentionally left
    /// alone so the user can recover within the 30-day grace window by
    /// signing back in (their public.users.deleted_at would need to be
    /// cleared by support/admin tooling). After this call the iOS client
    /// should sign out.
    func deleteMyAccount() async throws {
        try await supabase
            .rpc("delete_my_account")
            .execute()
    }

    func fetchGroupMemberships(userId: UUID) async throws -> [GroupMembership] {
        try await supabase
            .from("group_memberships")
            .select()
            .eq("user_id", value: userId.uuidString)
            .is("left_at", value: nil)
            .execute()
            .value
    }
}
