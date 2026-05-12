import Foundation

/// Builds and parses ConnectHS invite URLs.
///
/// Two surface forms exist intentionally:
///   - Custom scheme `connecths://invite/{code}` — works on Personal Team
///     today, what the iOS share sheet hands to recipients with the app
///     installed.
///   - Universal link `https://connecths.app/i/{code}` — degrades gracefully
///     to a web page for recipients who don't have the app yet (the page
///     deep-links into the App Store + opens the app post-install). Wired
///     end-to-end after paid Apple Developer enrollment lands the
///     Associated Domains entitlement on 2026-06-16.
enum InviteURL {

    static let webHost = "connecths.app"
    static let scheme = "connecths"

    static func deepLink(code: String) -> URL? {
        URL(string: "\(scheme)://invite/\(code)")
    }

    static func universalLink(code: String) -> URL? {
        URL(string: "https://\(webHost)/i/\(code)")
    }

    /// Friendly share copy per spec/04-groups.md. Uses the universal link in
    /// the body so non-installers get the web fallback instead of a broken
    /// custom-scheme URL.
    static func shareText(code: String) -> String {
        let url = universalLink(code: code)?.absoluteString
            ?? "https://\(webHost)/i/\(code)"
        return String(localized: "group.invite.share.text \(url)")
    }

    /// Extracts an invite code from any of:
    ///   - bare code: `"ABCD1234"`
    ///   - custom scheme: `connecths://invite/ABCD1234`
    ///   - universal link: `https://connecths.app/i/ABCD1234`
    /// Returns `nil` if input is empty or has no path segment.
    static func extractCode(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme?.isEmpty == false {
            let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            // For connecths://invite/CODE, host == "invite" and pathComponents == ["/", "CODE"]
            // For https://connecths.app/i/CODE, host == "connecths.app" and pathComponents == ["/", "i", "CODE"]
            if let last = segments.last, !last.isEmpty {
                return last
            }
            return nil
        }

        return trimmed
    }

    /// True when `url` is a ConnectHS invite link that the app should redeem.
    static func isInvite(_ url: URL) -> Bool {
        if url.scheme == scheme && url.host == "invite" {
            return true
        }
        if url.scheme == "https" && url.host == webHost && url.pathComponents.contains("i") {
            return true
        }
        return false
    }
}
