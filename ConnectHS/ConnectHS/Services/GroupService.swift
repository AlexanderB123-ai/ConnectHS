import Foundation
import Supabase
import PostgREST

/// The narrow surface FeedViewModel actually calls. See PostServicing for
/// rationale (injection seam for VM tests).
protocol GroupServicing: Sendable {
    func fetchGroups() async throws -> [FriendGroup]
    func listMembers(groupId: UUID) async throws -> [GroupMember]
}

struct GroupService: Sendable, GroupServicing {

    func createGroup(name: String, emoji: String?) async throws -> UUID {
        let response: UUID = try await supabase
            .rpc("create_group", params: [
                "p_name": name,
                "p_emoji": emoji ?? ""
            ])
            .execute()
            .value
        return response
    }

    func redeemInvite(code: String) async throws -> UUID {
        let response: UUID = try await supabase
            .rpc("redeem_invite", params: ["p_code": code])
            .execute()
            .value
        return response
    }

    func createInvite(groupId: UUID, maxUses: Int? = nil) async throws -> String {
        var params: [String: String] = ["p_group_id": groupId.uuidString]
        if let maxUses {
            params["p_max_uses"] = String(maxUses)
        }
        let code: String = try await supabase
            .rpc("create_invite", params: params)
            .execute()
            .value
        return code
    }

    func fetchGroups() async throws -> [FriendGroup] {
        try await supabase
            .from("groups")
            .select()
            .is("deleted_at", value: nil)
            .execute()
            .value
    }

    func fetchMembers(groupId: UUID) async throws -> [GroupMembership] {
        try await supabase
            .from("group_memberships")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .is("left_at", value: nil)
            .execute()
            .value
    }

    /// Joined member list (membership + user profile) for the settings view.
    func listMembers(groupId: UUID) async throws -> [GroupMember] {
        try await supabase
            .rpc("list_group_members", params: ["p_group_id": groupId.uuidString])
            .execute()
            .value
    }

    func leaveGroup(groupId: UUID) async throws {
        try await supabase
            .rpc("leave_group", params: ["p_group_id": groupId.uuidString])
            .execute()
    }

    func removeMember(groupId: UUID, userId: UUID) async throws {
        try await supabase
            .rpc("remove_member", params: [
                "p_group_id": groupId.uuidString,
                "p_user_id": userId.uuidString
            ])
            .execute()
    }

    func updateGroup(groupId: UUID, name: String, emoji: String?) async throws {
        try await supabase
            .rpc("update_group", params: [
                "p_group_id": groupId.uuidString,
                "p_name": name,
                "p_emoji": emoji ?? ""
            ])
            .execute()
    }

    func promoteAdmin(groupId: UUID, userId: UUID) async throws {
        try await supabase
            .rpc("promote_admin", params: [
                "p_group_id": groupId.uuidString,
                "p_user_id": userId.uuidString
            ])
            .execute()
    }
}
