import AuthenticationServices
import CryptoKit
import UIKit

/// Native Sign in with Apple.
///
/// Apple receives the SHA256 hash of the nonce and embeds it in the identity
/// token; Supabase is given the raw nonce and checks it against that hash.
@MainActor
final class AppleSignInController: NSObject {

    enum AppleSignInError: LocalizedError {
        case cancelled
        case noIdentityToken
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return nil  // User backed out: not worth showing an error.
            case .noIdentityToken:
                return L("error.appleNoToken")
            case let .failed(message):
                return message
            }
        }
    }

    private var continuation: CheckedContinuation<AuthSession, Error>?
    private var rawNonce: String?
    /// Held so ARC does not release the controller mid-flow.
    private var authController: ASAuthorizationController?

    func signIn() async throws -> AuthSession {
        let nonce = Self.randomNonce()
        rawNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        authController = controller

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<AuthSession, Error>) {
        let pending = continuation
        continuation = nil
        authController = nil
        rawNonce = nil
        switch result {
        case let .success(session): pending?.resume(returning: session)
        case let .failure(error): pending?.resume(throwing: error)
        }
    }

    // MARK: - Nonce

    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status != errSecSuccess {
            // Fall back to UUIDs rather than proceeding with predictable bytes.
            return UUID().uuidString + UUID().uuidString
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInController: ASAuthorizationControllerDelegate {

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            finish(.failure(AppleSignInError.noIdentityToken))
            return
        }

        let nonce = rawNonce
        Task {
            do {
                let session = try await SupabaseAuthAPI.signInWithApple(idToken: idToken, nonce: nonce)
                finish(.success(session))
            } catch {
                NSLog("[Auth] Apple exchange failed: \(error.localizedDescription)")
                finish(.failure(error))
            }
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        NSLog("[Auth] Apple sign-in error: \(error.localizedDescription)")
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            finish(.failure(AppleSignInError.cancelled))
        } else {
            finish(.failure(AppleSignInError.failed(error.localizedDescription)))
        }
    }
}

// MARK: - Presentation anchor

extension AppleSignInController: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        PresentationAnchor.current()
    }
}

/// Finds the active window for system sheets presented from SwiftUI.
enum PresentationAnchor {
    static func current() -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes
            .first(where: { $0.activationState == .foregroundActive })?
            .keyWindow
            ?? scenes.first?.windows.first
        return window ?? ASPresentationAnchor()
    }
}
