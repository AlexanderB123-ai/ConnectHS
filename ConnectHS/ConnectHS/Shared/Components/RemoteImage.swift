import SwiftUI

/// Resolves a Supabase Storage path → signed URL via `SignedURLCache` and renders
/// the image with `AsyncImage`. Falls back to a peach placeholder while loading
/// or on failure so the UI never has a hard empty state.
struct RemoteImage: View {

    let imagePath: String
    var contentMode: ContentMode = .fill

    @State private var resolvedURL: URL?
    @State private var didFail = false

    var body: some View {
        ZStack {
            placeholder

            if let url = resolvedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            }
        }
        .task(id: imagePath) {
            didFail = false
            resolvedURL = nil
            do {
                resolvedURL = try await SignedURLCache.shared.url(for: imagePath)
            } catch {
                didFail = true
            }
        }
    }

    private var placeholder: some View {
        Color.chPeach.opacity(0.3)
    }
}

#Preview {
    RemoteImage(imagePath: "preview/missing.jpg")
        .frame(width: 200, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
}
