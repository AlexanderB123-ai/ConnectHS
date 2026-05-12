import SwiftUI
import UIKit

/// Read-only swipeable carousel through the memories surfaced for one date —
/// usually one per prior year. Memories are reflective space, so we
/// deliberately don't expose reactions or view-count UI here; the share
/// affordance is the only outbound action.
struct MemoryDetailView: View {

    let carousel: MemoryCarousel
    let currentUserId: UUID

    @State private var selectedId: UUID
    @State private var sharePayload: SharePayload?
    @State private var isPreparingShare = false
    @Environment(\.dismiss) private var dismiss

    init(carousel: MemoryCarousel, currentUserId: UUID) {
        self.carousel = carousel
        self.currentUserId = currentUserId
        _selectedId = State(initialValue: carousel.initialId)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedId) {
                ForEach(carousel.memories) { memory in
                    page(for: memory)
                        .tag(memory.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: carousel.memories.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.black.opacity(0.4)))
                }
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: [payload.image])
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 100 && abs(value.translation.width) < 80 {
                        dismiss()
                    }
                }
        )
    }

    // MARK: - Page

    private func page(for memory: MemoryPost) -> some View {
        ZStack(alignment: .bottom) {
            backWithFrontInset(memory: memory)
                .ignoresSafeArea(edges: .top)

            metadataPanel(memory: memory)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func backWithFrontInset(memory: MemoryPost) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                RemoteImage(imagePath: memory.backImagePath)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                RemoteImage(imagePath: memory.frontImagePath)
                    .aspectRatio(3.0 / 4.0, contentMode: .fill)
                    .frame(width: 110, height: 150)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .stroke(.white.opacity(0.7), lineWidth: 2)
                    )
                    .padding(.top, Spacing.xxl + Spacing.md)
                    .padding(.trailing, Spacing.md)
            }
        }
    }

    private func metadataPanel(memory: MemoryPost) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.chTether)
                Text(yearsAgoText(memory.yearsAgo))
                    .font(.chHeadline)
                    .foregroundStyle(.white)
            }

            HStack(spacing: Spacing.xs) {
                Text(memory.authorName.lowercased())
                    .font(.chBody.weight(.semibold))
                    .foregroundStyle(.white)
                Text("·")
                    .foregroundStyle(.white.opacity(0.6))
                Text(formatDate(memory.promptDate))
                    .font(.chCaption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let caption = memory.caption, !caption.isEmpty {
                Text(caption)
                    .font(.chBody)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }

            shareButton(memory: memory)
                .padding(.top, Spacing.sm)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.xxl)
        .background(
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @ViewBuilder
    private func shareButton(memory: MemoryPost) -> some View {
        Button {
            Task { await prepareShare(memory: memory) }
        } label: {
            HStack(spacing: Spacing.xs) {
                if isPreparingShare {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up")
                    Text("memory.share.cta")
                        .font(.chHeadline)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.lg)
            .frame(height: 44)
            .background(Capsule().fill(.chTether))
        }
        .buttonStyle(.plain)
        .disabled(isPreparingShare)
    }

    // MARK: - Sharing

    private func prepareShare(memory: MemoryPost) async {
        isPreparingShare = true
        defer { isPreparingShare = false }
        guard let image = await MemoryShareRenderer.render(memory: memory) else { return }
        sharePayload = SharePayload(image: image)
    }

    private struct SharePayload: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    // MARK: - Formatting

    private func yearsAgoText(_ years: Int) -> LocalizedStringKey {
        years == 1 ? "memory.years.one" : "memory.years.many \(years)"
    }

    private func formatDate(_ promptDate: String) -> String {
        guard let date = Self.isoFormatter.date(from: promptDate) else { return promptDate }
        return Self.displayFormatter.string(from: date).lowercased()
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}
