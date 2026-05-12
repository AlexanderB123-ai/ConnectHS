import SwiftUI

/// Horizontal "X year(s) ago today" ribbon shown above the feed grid when the
/// `get_memories` RPC returns at least one row. Tapping a card opens
/// `MemoryDetailView`.
struct MemoryRibbonView: View {

    let memories: [MemoryPost]
    let currentUserId: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.chTether)
                Text(headlineText)
                    .font(.chHeadline)
                    .foregroundStyle(.chInk)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(memories) { memory in
                        NavigationLink(value: MemoryCarousel(memories: memories, initialId: memory.id)) {
                            MemoryThumbnail(memory: memory)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(.chPeach.opacity(0.25))
        )
    }

    private var headlineText: LocalizedStringKey {
        guard let first = memories.first else { return "memory.years.one" }
        if first.yearsAgo == 1 { return "memory.years.one" }
        return "memory.years.many \(first.yearsAgo)"
    }
}

private struct MemoryThumbnail: View {
    let memory: MemoryPost

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ZStack(alignment: .topTrailing) {
                RemoteImage(imagePath: memory.backImagePath)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 110, height: 110)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))

                RemoteImage(imagePath: memory.frontImagePath)
                    .aspectRatio(3.0 / 4.0, contentMode: .fill)
                    .frame(width: 32, height: 42)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.7), lineWidth: 1)
                    )
                    .padding(4)
            }
            Text(memory.authorName.lowercased())
                .font(.chMicro)
                .foregroundStyle(.chInkSoft)
                .lineLimit(1)
        }
        .frame(width: 110)
    }
}
