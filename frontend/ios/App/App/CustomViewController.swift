import UIKit
import WebKit
import AuthenticationServices
import Capacitor

class CustomViewController: CAPBridgeViewController {

    private var splashView: UIView?
    private var originalDelegate: WKNavigationDelegate?
    private var authSession: ASWebAuthenticationSession?

    override func viewDidLoad() {
        super.viewDidLoad()

        let bgColor = UIColor(red: 28.0/255.0, green: 28.0/255.0, blue: 30.0/255.0, alpha: 1)
        view.backgroundColor = bgColor
        webView?.backgroundColor = bgColor
        webView?.scrollView.backgroundColor = bgColor

        webView?.scrollView.bounces = false
        webView?.scrollView.alwaysBounceVertical = false
        webView?.scrollView.alwaysBounceHorizontal = false
        webView?.scrollView.contentInsetAdjustmentBehavior = .never
        webView?.isOpaque = true

        // Splash overlay
        let splash = UIView(frame: view.bounds)
        splash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        splash.backgroundColor = bgColor

        if let logoImage = UIImage(named: "Splash") {
            let logoView = UIImageView(image: logoImage)
            logoView.contentMode = .scaleAspectFit
            logoView.translatesAutoresizingMaskIntoConstraints = false
            splash.addSubview(logoView)
            NSLayoutConstraint.activate([
                logoView.centerXAnchor.constraint(equalTo: splash.centerXAnchor),
                logoView.centerYAnchor.constraint(equalTo: splash.centerYAnchor),
                logoView.widthAnchor.constraint(equalToConstant: 280),
                logoView.heightAnchor.constraint(equalToConstant: 280)
            ])
        }

        view.addSubview(splash)
        splashView = splash
        webView?.addObserver(self, forKeyPath: "loading", options: .new, context: nil)

        // Custom user agent for iOS app detection
        webView?.evaluateJavaScript("navigator.userAgent") { [weak self] result, _ in
            if let ua = result as? String {
                self?.webView?.customUserAgent = ua + " big3me/ios"
            }
        }

        // Wrap navigation delegate
        originalDelegate = webView?.navigationDelegate
        webView?.navigationDelegate = self
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "loading", let isLoading = change?[.newKey] as? Bool, !isLoading {
            dismissSplash()
        }
    }

    private func dismissSplash() {
        guard let splash = splashView else { return }
        UIView.animate(withDuration: 0.3, animations: {
            splash.alpha = 0
        }) { _ in
            splash.removeFromSuperview()
            self.splashView = nil
        }
        webView?.removeObserver(self, forKeyPath: "loading")
    }

    // MARK: - Google OAuth via ASWebAuthenticationSession
    private func startGoogleOAuth(url: URL) {
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "big3me") { [weak self] callbackURL, error in
            self?.authSession = nil

            if let callbackURL = callbackURL {
                let fragment = callbackURL.fragment ?? ""
                if !fragment.isEmpty {
                    let js = """
                    window.location.hash = '\(fragment)';
                    window.location.reload();
                    """
                    DispatchQueue.main.async {
                        self?.webView?.evaluateJavaScript(js, completionHandler: nil)
                    }
                } else {
                    self?.webView?.reload()
                }
            } else {
                self?.webView?.reload()
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    // MARK: - Apple Sign In (native)
    private func startNativeAppleSignIn() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    deinit {
        if splashView != nil {
            webView?.removeObserver(self, forKeyPath: "loading")
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
extension CustomViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return view.window!
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension CustomViewController: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return view.window!
    }
}

// MARK: - ASAuthorizationControllerDelegate (Apple Sign In)
extension CustomViewController: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let idToken = String(data: identityTokenData, encoding: .utf8) else {
            return
        }

        // Pass the Apple ID token to Supabase via JS
        let js = """
        (async () => {
            try {
                const { createClient } = await import('https://esm.sh/@supabase/supabase-js@2');
                // Use existing Supabase client from the app
                const supabaseUrl = document.querySelector('meta[name="supabase-url"]')?.content;
                const supabaseKey = document.querySelector('meta[name="supabase-key"]')?.content;

                // Try using the global supabase instance
                if (window.__supabase) {
                    await window.__supabase.auth.signInWithIdToken({
                        provider: 'apple',
                        token: '\(idToken)'
                    });
                    window.location.reload();
                    return;
                }

                // Fallback: post message for the React app to handle
                window.postMessage({
                    type: 'APPLE_SIGN_IN',
                    idToken: '\(idToken)'
                }, '*');
            } catch(e) {
                console.error('[Apple Sign In] Error:', e);
            }
        })();
        """
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("[Apple Sign In] Error: \(error.localizedDescription)")
    }
}

// MARK: - WKNavigationDelegate
extension CustomViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            let host = url.host ?? ""
            let path = url.path
            let query = url.query ?? ""

            // Apple OAuth → use native Sign in with Apple
            if host.contains("supabase.co") && path.contains("/auth/") && query.contains("provider=apple") {
                startNativeAppleSignIn()
                decisionHandler(.cancel)
                return
            }

            // Google/other OAuth → ASWebAuthenticationSession
            if host.contains("supabase.co") && path.contains("/auth/") {
                startGoogleOAuth(url: url)
                decisionHandler(.cancel)
                return
            }

            // Direct Google OAuth (fallback)
            if host.contains("accounts.google.com") {
                startGoogleOAuth(url: url)
                decisionHandler(.cancel)
                return
            }
        }

        if let original = originalDelegate {
            original.webView?(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        originalDelegate?.webView?(webView, didStartProvisionalNavigation: navigation)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        originalDelegate?.webView?(webView, didFinish: navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        originalDelegate?.webView?(webView, didFail: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        originalDelegate?.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
    }
}
