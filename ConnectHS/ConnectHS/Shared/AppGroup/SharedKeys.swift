import Foundation

/// Identifiers shared between the app and `ConnectHSWidget` extension. The
/// App Group entitlement on both targets must include `appGroupID` for the
/// widget to read the payload the app writes.
nonisolated enum SharedKeys {
    static let appGroupID = "group.com.alexander.connecths.shared"
    static let latestPostKey = "latestPost"
    static let widgetKind = "ConnectHSWidget"
}
