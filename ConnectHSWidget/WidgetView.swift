import SwiftUI
import WidgetKit
import UIKit

/// Renders a `LatestPostPayload` from the App Group container. Memory
/// budget for widgets is ~30 MB; we lean on the fact that the writer
/// downscales to 256×256 and never decode a fresh thumb more than once
/// per body evaluation.
struct WidgetView: View {

    let entry: LatestPostEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let payload = entry.payload {
            populated(payload: payload)
                .widgetURL(URL(string: "connecths://post/\(payload.postID.uuidString)"))
        } else {
            empty
                .widgetURL(URL(string: "connecths://camera"))
        }
    }

    // MARK: - Populated

    @ViewBuilder
    private func populated(payload: LatestPostPayload) -> some View {
        let backImage = decode(payload.backImageThumbBase64)
        let frontImage = decode(payload.frontImageThumbBase64)

        ZStack {
            // Blurred back as a soft cream-leaning bed; the foreground image
            // sits on top with rounded corners.
            if let backImage {
                Image(uiImage: backImage)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 30)
                    .clipped()

                Image(uiImage: backImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(6)
            } else {
                Color(red: 0.98, green: 0.97, blue: 0.94)
            }

            VStack {
                HStack {
                    Spacer()
                    if let frontImage {
                        Image(uiImage: frontImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: family == .systemSmall ? 38 : 46,
                                   height: family == .systemSmall ? 50 : 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white.opacity(0.85), lineWidth: 1.5)
                            )
                            .padding(10)
                    }
                }
                Spacer()
            }

            if family == .systemMedium {
                VStack {
                    Spacer()
                    HStack {
                        Text("\(payload.authorName.lowercased()) · \(relative(payload.postedAt))")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.5))
                            .clipShape(Capsule())
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(10)
                }
            }
        }
    }

    // MARK: - Empty

    private var empty: some View {
        ZStack {
            Color(red: 0.98, green: 0.97, blue: 0.94)
            VStack(spacing: 6) {
                Text("📷")
                    .font(.system(size: family == .systemSmall ? 28 : 34))
                Text("no moments yet")
                    .font(.caption)
                    .foregroundColor(.black.opacity(0.55))
            }
        }
    }

    // MARK: - Helpers

    private func decode(_ base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview(as: .systemSmall) {
    ConnectHSWidget()
} timeline: {
    LatestPostEntry(date: Date(), payload: nil)
}

#Preview(as: .systemMedium) {
    ConnectHSWidget()
} timeline: {
    LatestPostEntry(date: Date(), payload: nil)
}
