import SwiftUI

/// Renders a user's profile photo if `avatarPath` resolves, falls back to a
/// peach initials disc otherwise. Self-contained signed-URL fetch via
/// `AvatarService` so the component can drop in anywhere without callers
/// knowing about Supabase Storage.
///
/// Initials use the first letter of each leading-and-second word
/// (e.g. "Sarah Lee" → "SL", "kai" → "K") to match the original ad-hoc
/// initials code that lived in PostDetailView / GroupSettingsView.
struct AvatarView: View {

    let name: String
    let avatarPath: String?
    var size: CGFloat = 40

    @State private var resolvedURL: URL?

    private let service = AvatarService()

    var body: some View {
        ZStack {
            initialsBackground

            if let url = resolvedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        // Briefly transparent while AsyncImage loads — the
                        // initials underneath show through.
                        Color.clear
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: avatarPath) {
            resolvedURL = nil
            guard let path = avatarPath, !path.isEmpty else { return }
            resolvedURL = try? await service.signedURL(for: path)
        }
    }

    private var initialsBackground: some View {
        Circle()
            .fill(.chPeach)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.40, weight: .semibold, design: .rounded))
                    .foregroundStyle(.chInk)
            }
    }

    private var initials: String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }
}

#Preview {
    HStack(spacing: 20) {
        AvatarView(name: "Sarah Lee", avatarPath: nil, size: 60)
        AvatarView(name: "ben", avatarPath: nil, size: 40)
        AvatarView(name: "ava", avatarPath: nil, size: 28)
    }
    .padding()
}
