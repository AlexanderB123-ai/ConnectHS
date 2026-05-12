import SwiftUI
import UserNotifications
import UIKit
import os

/// Asked once, at the first natural moment — after the user has reached the
/// main app (i.e. they've joined or created a group). Per spec we never
/// re-prompt; if they say "not now," the in-app banner in profile is the
/// route back.
struct NotificationPermissionSheet: View {

    let onDecision: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    private let logger = Logger(subsystem: "com.connecths.app", category: "NotifPermSheet")

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(.chTether)

            VStack(spacing: Spacing.sm) {
                Text("notifications.permission.title")
                    .font(.chDisplay)
                    .foregroundStyle(.chInk)
                    .multilineTextAlignment(.center)

                Text("notifications.permission.subtitle")
                    .font(.chBody)
                    .foregroundStyle(.chInkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            Spacer()

            VStack(spacing: Spacing.sm) {
                Button {
                    Task { await request(grant: true) }
                } label: {
                    HStack {
                        if isRequesting {
                            ProgressView().tint(.white)
                        } else {
                            Text("notifications.permission.allow")
                                .font(.chHeadline)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(RoundedRectangle(cornerRadius: CornerRadius.md).fill(.chTether))
                }
                .disabled(isRequesting)

                Button {
                    onDecision(false)
                    dismiss()
                } label: {
                    Text("notifications.permission.skip")
                        .font(.chBody)
                        .foregroundStyle(.chInkSoft)
                        .frame(height: 44)
                }
                .disabled(isRequesting)
            }
        }
        .padding(Spacing.lg)
        .background(Color.chCream.ignoresSafeArea())
    }

    private func request(grant: Bool) async {
        isRequesting = true
        defer { isRequesting = false }

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            onDecision(granted)
        } catch {
            logger.error("Authorization request failed: \(error.localizedDescription)")
            onDecision(false)
        }
        dismiss()
    }
}

#Preview {
    NotificationPermissionSheet { _ in }
}
