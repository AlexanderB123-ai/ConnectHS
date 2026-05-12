import SwiftUI
import UIKit

struct CameraPermissionView: View {

    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                Spacer()
                Image(systemName: "camera.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.8))
                Text("camera.permission.title")
                    .font(.chHeadline)
                    .foregroundStyle(.white)
                Text("camera.permission.subtitle")
                    .font(.chBody)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)

                Spacer()

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("camera.permission.openSettings")
                        .font(.chHeadline)
                        .foregroundStyle(.chInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(.white)
                        )
                }
                .padding(.horizontal, Spacing.md)

                Button(action: onDismiss) {
                    Text("camera.permission.skip")
                }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, Spacing.lg)
            }
        }
    }
}

#Preview {
    CameraPermissionView(onDismiss: {})
}
