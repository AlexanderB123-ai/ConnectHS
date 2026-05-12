import Foundation
import Observation
import os

@MainActor
@Observable
final class GroupSettingsViewModel {

    enum LoadState: Sendable {
        case loading
        case loaded
        case error(String)
    }

    private(set) var loadState: LoadState = .loading
    private(set) var members: [GroupMember] = []
    private(set) var isAdmin: Bool = false
    private(set) var actionInFlight: Bool = false
    var actionError: String?
    var inviteText: String?

    let group: FriendGroup
    let currentUserId: UUID

    /// Bumps when the model commits a change that requires the parent feed
    /// to reload (rename, leave, member removal). The parent observes this.
    private(set) var lastMutationToken: UUID?

    private let groupService = GroupService()
    private let blockService = BlockService()
    private let logger = Logger(subsystem: "com.connecths.app", category: "GroupSettings")

    init(group: FriendGroup, currentUserId: UUID) {
        self.group = group
        self.currentUserId = currentUserId
    }

    func load() async {
        loadState = .loading
        do {
            members = try await groupService.listMembers(groupId: group.id)
            isAdmin = members.contains { $0.userId == currentUserId && $0.role == .admin }
            loadState = .loaded
        } catch {
            logger.error("Member load failed: \(error.localizedDescription)")
            loadState = .error(String(localized: "group.settings.error.couldntLoad"))
        }
    }

    func generateInvite() async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            let code = try await groupService.createInvite(groupId: group.id)
            inviteText = InviteURL.shareText(code: code)
        } catch {
            logger.error("Invite create failed: \(error.localizedDescription)")
            actionError = String(localized: "group.settings.error.invite")
        }
    }

    func updateGroup(name: String, emoji: String?) async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await groupService.updateGroup(groupId: group.id, name: name, emoji: emoji)
            lastMutationToken = UUID()
            await load()
        } catch {
            logger.error("Group update failed: \(error.localizedDescription)")
            actionError = errorMessage(error, default: String(localized: "group.settings.error.update"))
        }
    }

    func promoteAdmin(_ member: GroupMember) async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await groupService.promoteAdmin(groupId: group.id, userId: member.userId)
            await load()
        } catch {
            logger.error("Promote failed: \(error.localizedDescription)")
            actionError = errorMessage(error, default: String(localized: "group.settings.error.promote"))
        }
    }

    func removeMember(_ member: GroupMember) async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await groupService.removeMember(groupId: group.id, userId: member.userId)
            lastMutationToken = UUID()
            await load()
        } catch {
            logger.error("Remove member failed: \(error.localizedDescription)")
            actionError = errorMessage(error, default: String(localized: "group.settings.error.remove"))
        }
    }

    func blockMember(_ member: GroupMember) async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await blockService.block(targetId: member.userId)
        } catch {
            logger.error("Block failed: \(error.localizedDescription)")
            actionError = errorMessage(error, default: String(localized: "blocks.error.block"))
        }
    }

    func leaveGroup() async -> Bool {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await groupService.leaveGroup(groupId: group.id)
            lastMutationToken = UUID()
            return true
        } catch {
            logger.error("Leave failed: \(error.localizedDescription)")
            actionError = errorMessage(error, default: String(localized: "group.settings.error.leave"))
            return false
        }
    }

    private func errorMessage(_ error: Error, default fallback: String) -> String {
        let raw = (error as NSError).localizedDescription.lowercased()
        if raw.contains("only admins") { return String(localized: "group.settings.error.adminOnly") }
        if raw.contains("last admin")  { return String(localized: "group.settings.error.lastAdmin") }
        if raw.contains("not a member") { return String(localized: "group.settings.error.notMember") }
        return fallback
    }
}
