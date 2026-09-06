import AuthenticationServices
import UIKit

/// Google sign-in through `ASWebAuthenticationSession`.
///
/// Google refuses OAuth inside embedded WebViews, so the flow runs in the
/// system browser sheet and returns via the `big3me://` scheme. This replaces
/// the `@capacitor/browser` path used by the web bundle, which is not linked
/// into the iOS binary.
@MainActor
final class GoogleSignInController: NSObject {

    enum GoogleSignInError: LocalizedError {
        case cancelled
        case noSession
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return nil
            case .noSession:
                return "Google sign-in returned without a session."
            case let .failed(message):
                return message
            }
        }
    }

    private static let callbackURL = "big3me://auth-callback"

    /// Held for the lifetime of the sheet.
    private var session: ASWebAuthenticationSession?

    func signIn() async throws -> AuthSession {
        let url = SupabaseAuthAPI.authorizeURL(provider: "google", redirectTo: Self.callbackURL)

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AppConfig.urlScheme
            ) { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: GoogleSignInError.cancelled)
                    } else {
                        NSLog("[Auth] Google sheet error: \(error.localizedDescription)")
                        continuation.resume(throwing: GoogleSignInError.failed(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GoogleSignInError.noSession)
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            // Reuse the browser's Google cookies so the user does not retype
            // credentials on every sign-in.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }

        self.session = nil

        guard let authSession = try await SupabaseAuthAPI.session(fromCallback: callback) else {
            throw GoogleSignInError.noSession
        }
        return authSession
    }
}

extension GoogleSignInController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        PresentationAnchor.current()
    }
}
