import Foundation
import Observation
import os

@MainActor
@Observable
final class NotificationSettingsViewModel {

    enum LoadState: Sendable {
        case loading
        case loaded
        case error
    }

    private(set) var loadState: LoadState = .loading
    private(set) var settings: NotificationSettings?

    /// `true` while a debounced upsert is in flight. View can show a subtle
    /// indicator without blocking interaction.
    private(set) var saving: Bool = false
    private(set) var lastError: String?

    private let pushService = PushService()
    private let logger = Logger(subsystem: "com.connecths.app", category: "NotifSettings")
    private let userId: UUID

    private var saveTask: Task<Void, Never>?
    private let debounceNanoseconds: UInt64 = 400_000_000  // 400ms

    init(userId: UUID) {
        self.userId = userId
    }

    /// Call from `.task` / `.onDisappear` to cancel any in-flight debounced
    /// save. Used by the view layer rather than `deinit` because Swift 6's
    /// nonisolated deinit can't touch our MainActor-isolated state.
    func cancelPendingSave() {
        saveTask?.cancel()
    }

    func load() async {
        loadState = .loading
        do {
            settings = try await pushService.fetchSettings(userId: userId)
            loadState = .loaded
        } catch {
            logger.error("Settings load failed: \(error.localizedDescription)")
            loadState = .error
        }
    }

    /// Apply a mutation to the local settings and schedule a debounced upsert.
    /// Multiple rapid toggles within the debounce window only fire one network
    /// request — useful when the user flips a few switches in a row.
    func apply(_ mutation: (inout NotificationSettings) -> Void) {
        guard var current = settings else { return }
        mutation(&current)
        settings = current
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let pending = settings
        saveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanoseconds)
            if Task.isCancelled { return }
            await self.persist(pending)
        }
    }

    private func persist(_ snapshot: NotificationSettings?) async {
        guard let snapshot else { return }
        saving = true
        defer { saving = false }
        do {
            try await pushService.updateSettings(snapshot)
            lastError = nil
        } catch {
            logger.error("Settings save failed: \(error.localizedDescription)")
            lastError = String(localized: "profile.notifications.saveError")
        }
    }
}
