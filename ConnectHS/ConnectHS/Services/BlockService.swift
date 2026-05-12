import Foundation
import Supabase

/// Wraps the user_blocks RPCs. Blocks are one-directional (blocker→blocked)
/// and silently filter the blocked user's posts out of the caller's feed,
/// archive, and memories at the RPC layer (see migration 20260509040000).
struct BlockService: Sendable {

    func block(targetId: UUID) async throws {
        try await supabase
            .rpc("block_user", params: ["p_target_id": targetId.uuidString])
            .execute()
    }

    func unblock(targetId: UUID) async throws {
        try await supabase
            .rpc("unblock_user", params: ["p_target_id": targetId.uuidString])
            .execute()
    }

    func listMyBlocks() async throws -> [BlockedUser] {
        try await supabase
            .rpc("list_my_blocked_users")
            .execute()
            .value
    }
}
