import SwiftUI

/// Reason picker + free-form details for reporting a member or a post.
/// Used as a modal sheet from GroupSettingsView (member-action dialog) and
/// can be used from PostDetailView (long-press author) when wired.
///
/// Submission is fire-and-forget from the user's perspective: we show a
/// confirmation alert, dismiss, and trust server-side triage to follow up.
struct ReportSheet: View {

    enum Target: Hashable, Sendable {
        case user(id: UUID, displayName: String)
        case post(id: UUID, authorName: String)
    }

    let target: Target
    let onSubmitted: () -> Void

    @State private var reason: ReportReason = .inappropriate
    @State private var details: String = ""
    @State private var submitting = false
    @State private var submitError: String?
    @Environment(\.dismiss) private var dismiss

    private let service = ReportService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chCream.ignoresSafeArea()

                Form {
                    Section {
                        Text(headlineText)
                            .font(.chBody)
                            .foregroundStyle(.chInk)
                    }
                    .listRowBackground(Color.chCream)

                    Section(header: Text("report.reason.section")) {
                        Picker(selection: $reason) {
                            ForEach(ReportReason.allCases) { r in
                                Text(LocalizedStringKey(r.labelKey))
                                    .tag(r)
                            }
                        } label: {
                            Text("report.reason.picker.label")
                        }
                        .pickerStyle(.inline)
                    }

                    Section(header: Text("report.details.section"),
                            footer: Text("report.details.footer")) {
                        TextField(
                            String(localized: "report.details.placeholder"),
                            text: $details,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                    }

                    if let submitError {
                        Section {
                            Text(submitError)
                                .font(.chCaption)
                                .foregroundStyle(.chError)
                        }
                        .listRowBackground(Color.chCream)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(Text("report.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Text("common.cancel") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if submitting {
                            ProgressView()
                        } else {
                            Text("report.submit")
                                .foregroundStyle(.chTether)
                        }
                    }
                    .disabled(submitting)
                }
            }
        }
    }

    private var headlineText: LocalizedStringKey {
        switch target {
        case .user(_, let name):
            return "report.target.user \(name.lowercased())"
        case .post(_, let author):
            return "report.target.post \(author.lowercased())"
        }
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }

        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch target {
            case .user(let id, _):
                try await service.reportUser(
                    targetId: id,
                    reason: reason,
                    details: trimmed.isEmpty ? nil : trimmed
                )
            case .post(let id, _):
                try await service.reportPost(
                    postId: id,
                    reason: reason,
                    details: trimmed.isEmpty ? nil : trimmed
                )
            }
            onSubmitted()
            dismiss()
        } catch {
            submitError = String(localized: "report.error.submit")
        }
    }
}
