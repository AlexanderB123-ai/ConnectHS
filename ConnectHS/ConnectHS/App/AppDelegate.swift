import UIKit
import UserNotifications
import os

/// SwiftUI bridges this through `@UIApplicationDelegateAdaptor` in
/// `ConnectHSApp`. Responsible for:
///   • setting the UNUserNotificationCenter delegate so foreground banners and
///     tap handlers fire,
///   • forwarding the APNs device token to `PushService` on register,
///   • forwarding deep links from notification taps into the app's router.
///
/// Until the Apple Developer Program enrollment lands (planned 2026-06-16),
/// `registerForRemoteNotifications()` will trigger `didFailToRegister…` —
/// we log at info level and move on; everything else stays correct.
final class AppDelegate: NSObject, UIApplicationDelegate {

    private let logger = Logger(subsystem: "com.connecths.app", category: "AppDelegate")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            do {
                try await PushService().registerToken(token)
            } catch {
                logger.error("Failed to persist APNs token: \(error.localizedDescription)")
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.info("APNs registration unavailable: \(error.localizedDescription)")
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if let deepLink = userInfo["deep_link"] as? String,
           let url = URL(string: deepLink) {
            await MainActor.run { DeepLinkRouter.shared.enqueue(url) }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
