import Foundation
import Observation
import os

/// Single source of truth for incoming deep links — from notification taps
/// (forwarded by `AppDelegate`) and `.onOpenURL` (universal links + the
/// `connecths://` scheme).
///
/// Views observe `pending` and route off of it. They are responsible for
/// clearing the value (`clear()`) once handled so a second link replaces a
/// stale one cleanly.
@MainActor
@Observable
final class DeepLinkRouter {

    static let shared = DeepLinkRouter()

    private(set) var pending: URL?
    private let logger = Logger(subsystem: "com.connecths.app", category: "DeepLinkRouter")

    private init() {}

    func enqueue(_ url: URL) {
        logger.info("Deep link received: \(url.absoluteString, privacy: .public)")
        pending = url
    }

    func clear() {
        pending = nil
    }
}
