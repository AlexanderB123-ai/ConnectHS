import Foundation
import UIKit
import Supabase

/// Wraps APNs token persistence in the `device_tokens` table.
/// Until Apple Developer enrollment ships the `aps-environment` entitlement,
/// `UIApplication.registerForRemoteNotifications()` will fire
/// `didFailToRegisterForRemoteNotifications` and these methods won't be called —
/// that's expected; the row is best-effort and reused once the cap is enabled.
struct PushService: Sendable {

    func registerToken(_ token: String) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        struct Row: Encodable {
            let user_id: String
            let apns_token: String
            let device_id: String
            let app_version: String?
            let last_seen_at: String
        }

        let row = Row(
            user_id: userId.uuidString,
            apns_token: token,
            device_id: deviceId,
            app_version: appVersion,
            last_seen_at: ISO8601DateFormatter().string(from: Date())
        )

        try await supabase
            .from("device_tokens")
            .upsert(row, onConflict: "user_id,device_id")
            .execute()
    }

    func unregisterCurrentDevice() async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id
        guard let deviceId = UIDevice.current.identifierForVendor?.uuidString else { return }

        try await supabase
            .from("device_tokens")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("device_id", value: deviceId)
            .execute()
    }

    // MARK: - Settings

    /// Read the caller's notification settings row. Returns defaults if no
    /// row exists (the trigger backfill should mean this never fires, but
    /// we guard anyway for accounts created before that migration).
    func fetchSettings(userId: UUID) async throws -> NotificationSettings {
        let rows: [NotificationSettings] = try await supabase
            .from("notification_settings")
            .select()
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first ?? NotificationSettings.defaults(for: userId)
    }

    /// Persist the caller's settings. RLS on `notification_settings` lets a
    /// user read/write only their own row; we still pass user_id explicitly
    /// for the upsert key.
    func updateSettings(_ settings: NotificationSettings) async throws {
        var copy = settings
        copy.updatedAt = Date()
        try await supabase
            .from("notification_settings")
            .upsert(copy, onConflict: "user_id")
            .execute()
    }
}
