import SwiftUI
import UIKit

struct CapturePreviewView: View {

    let front: UIImage
    let back: UIImage
    @Binding var caption: String

    let onRetake: () -> Void
    let onPost: () -> Void

    @FocusState private var isCaptionFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: back)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()

                    Image(uiImage: front)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .stroke(.white.opacity(0.6), lineWidth: 2)
                        )
                        .padding(Spacing.md)
                        .padding(.top, Spacing.xl)
                }
                .ignoresSafeArea()
            }

            VStack {
                Spacer()
                captionField
                actionRow
            }
        }
    }

    private var captionField: some View {
        TextField(String(localized: "camera.preview.caption.placeholder"), text: $caption, axis: .vertical)
            .font(.chBody)
            .foregroundStyle(.white)
            .tint(.chTether)
            .lineLimit(1...3)
            .focused($isCaptionFocused)
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(.black.opacity(0.5))
            )
            .overlay(alignment: .topTrailing) {
                if !caption.isEmpty {
                    Text("\(caption.count)/140")
                        .font(.chMicro)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(Spacing.xs)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)
    }

    private var actionRow: some View {
        HStack(spacing: Spacing.md) {
            Button {
                onRetake()
            } label: {
                Text("camera.preview.retake")
                    .font(.chHeadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .stroke(.white, lineWidth: 1.5)
                    )
            }

            Button {
                onPost()
            } label: {
                Text("camera.preview.post")
                    .font(.chHeadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(.chTether)
                    )
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.lg)
    }
}
