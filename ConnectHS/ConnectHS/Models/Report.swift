import Foundation

/// Closed set of report reasons; matches the CHECK in `report_user` /
/// `report_post`. Add new cases here AND in the SQL CHECK in lockstep.
enum ReportReason: String, Codable, Sendable, CaseIterable, Identifiable {
    case spam
    case harassment
    case inappropriate
    case impersonation
    case other

    var id: String { rawValue }

    /// Localized label for the reason picker UI. Resolved via the catalog
    /// keys in `Localizable.xcstrings`.
    var labelKey: String { "report.reason.\(rawValue)" }
}
