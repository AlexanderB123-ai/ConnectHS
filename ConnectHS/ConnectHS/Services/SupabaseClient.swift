import Foundation
import Supabase

/// Resolves the Supabase URL + anon key from `Info.plist` keys that are
/// substituted at build time from `Config.xcconfig`. The xcconfig template
/// lives at `ConnectHS/Config.example.xcconfig`; the real-values file
/// (`Config.xcconfig`) is gitignored. The anon key is safe to ship — RLS
/// protects data — but living in xcconfig means swapping projects (dev /
/// staging / prod) doesn't require a code change or a recompile of source.
///
/// Missing or blank values are treated as a build misconfiguration (not a
/// runtime condition) and trip a `fatalError` with a remediation message
/// at first launch — explicitly preferring fail-fast over the original
/// force-unwrap on `URL(string:)`.
enum AppConfig {

    private static let infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]

    static let supabaseURL: URL = {
        guard let host = infoDictionary["SUPABASE_URL"] as? String,
              !host.isEmpty,
              host != "YOUR_PROJECT_REF.supabase.co",
              let url = URL(string: "https://\(host)") else {
            fatalError(
                "SUPABASE_URL missing or unset in Info.plist. " +
                "Did you copy ConnectHS/Config.example.xcconfig to " +
                "ConnectHS/Config.xcconfig and fill it in?"
            )
        }
        return url
    }()

    static let supabaseAnonKey: String = {
        guard let key = infoDictionary["SUPABASE_ANON_KEY"] as? String,
              !key.isEmpty,
              key != "YOUR_ANON_PUBLISHABLE_KEY" else {
            fatalError(
                "SUPABASE_ANON_KEY missing or unset in Info.plist. " +
                "Did you copy ConnectHS/Config.example.xcconfig to " +
                "ConnectHS/Config.xcconfig and fill it in?"
            )
        }
        return key
    }()
}

let supabase = SupabaseClient(
    supabaseURL: AppConfig.supabaseURL,
    supabaseKey: AppConfig.supabaseAnonKey
)
