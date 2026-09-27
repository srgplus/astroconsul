import Foundation

/// Static configuration for the native layer.
///
/// The Supabase anon key is a public client key by design: it already ships
/// inside the web bundle served from big3.me, so keeping it in Info.plist adds
/// no exposure. Row-level security on the database is what protects the data.
enum AppConfig {

    /// Backend origin. Native screens talk to this REST API directly; the
    /// WebView loads the same origin for screens that are not native yet.
    static let apiBaseURL: URL = {
        #if DEBUG
        // `-apiBaseURL http://127.0.0.1:8001` points a debug build at a
        // backend running on this Mac, so a change that spans the API and the
        // app can be tried end to end before either ships. Launch arguments
        // land in UserDefaults' argument domain, which is what reads it here.
        if let raw = UserDefaults.standard.string(forKey: "apiBaseURL"),
           let url = URL(string: raw), url.host != nil {
            return url
        }
        #endif
        return URL(string: "https://big3.me")!
    }()

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

/// The pages and the inbox a person is pointed at from inside the app: the
/// Terms they agree to at sign-in, which carry the community rules, the
/// privacy policy, and where reports and questions reach a person.
enum Legal {

    static let termsURL = URL(string: "https://big3.me/legal#community", relativeTo: nil)!
    static let privacyURL = URL(string: "https://big3.me/privacy")!

    /// The address the support and legal pages publish.
    static let supportEmail = "big3meapp@gmail.com"
    static let supportMail = URL(string: "mailto:\(supportEmail)")!
}
