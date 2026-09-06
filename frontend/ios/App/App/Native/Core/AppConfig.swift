import Foundation

/// Static configuration for the native layer.
///
/// The Supabase anon key is a public client key by design: it already ships
/// inside the web bundle served from big3.me, so keeping it in Info.plist adds
/// no exposure. Row-level security on the database is what protects the data.
enum AppConfig {

    /// Backend origin. Native screens talk to this REST API directly; the
    /// WebView loads the same origin for screens that are not native yet.
    static let apiBaseURL = URL(string: "https://big3.me")!

    static let supabaseURL: URL = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: raw), url.host != nil else {
            fatalError("SUPABASE_URL missing from Info.plist")
        }
        return url
    }()

    static let supabaseAnonKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty else {
            fatalError("SUPABASE_ANON_KEY missing from Info.plist")
        }
        return key
    }()

    /// Custom URL scheme registered in Info.plist, used for the OAuth return.
    static let urlScheme = "big3me"
}
