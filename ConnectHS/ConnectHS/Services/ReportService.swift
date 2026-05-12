import Foundation
import Supabase

/// Thin wrapper around the `report_user` / `report_post` RPCs. The reports
/// table itself is service-role only; these RPCs are the only client-side
/// write path. Reasons must match `ReportReason` (which mirrors the SQL
/// CHECK constraint).
struct ReportService: Sendable {

    func reportUser(targetId: UUID, reason: ReportReason, details: String?) async throws {
        try await supabase
            .rpc("report_user", params: [
                "p_target_id": targetId.uuidString,
                "p_reason": reason.rawValue,
                "p_details": details ?? ""
            ])
            .execute()
    }

    func reportPost(postId: UUID, reason: ReportReason, details: String?) async throws {
        try await supabase
            .rpc("report_post", params: [
                "p_post_id": postId.uuidString,
                "p_reason": reason.rawValue,
                "p_details": details ?? ""
            ])
            .execute()
    }
}
