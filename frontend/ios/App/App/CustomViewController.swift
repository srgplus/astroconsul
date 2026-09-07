import UIKit
import WebKit
import AuthenticationServices
import StoreKit
import Capacitor

class CustomViewController: CAPBridgeViewController {

    private var splashView: UIView?
    private var originalDelegate: WKNavigationDelegate?
    private var authSession: ASWebAuthenticationSession?
    private var storeKitManager: Any?  // StoreKit2Manager (iOS 15+)

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

        // The web half posts here when its own language switch is used, so
        // the two settings stay one setting.
        webView?.configuration.userContentController.add(self, name: "language")

        // Register StoreKit2 JS bridge (iOS 15+)
        if #available(iOS 15.0, *), let wv = webView {
            let manager = StoreKit2Manager(webView: wv)
            wv.configuration.userContentController.add(manager, name: "storekit")
            storeKitManager = manager
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

    // MARK: - Navigation

    /// Points the WebView at one of the web app's screens.
    ///
    /// A no-op when it is already there and settled: this WebView is shared and
    /// long-lived, so reloading it would throw away the SPA's state and scroll
    /// position for nothing. A load in flight is not "already there" — that is
    /// the first open, where Capacitor has just started on the home URL and
    /// this is what redirects it.
    func navigate(to destination: WebDestination) {
        guard let webView, let url = destination.url else {
            NSLog("[WebScreen] no WebView to open \(destination.rawValue) in")
            return
        }

        // `path` is empty for a bare origin, and the SPA rewrites it with
        // `replaceState` as screens open and close, so it is read live rather
        // than remembered.
        let currentPath = webView.url.map { $0.path.isEmpty ? "/" : $0.path }
        if currentPath == destination.rawValue, !webView.isLoading { return }

        webView.load(URLRequest(url: url))
    }

    // MARK: - Session bridge to the native layer

    /// Pushes a session obtained by the native sign-in screen into the WebView,
    /// so both halves of the app are signed in as the same account.
    ///
    /// Goes through supabase-js `setSession` rather than writing localStorage
    /// directly: the library then fetches the user, sets up refresh timers and
    /// notifies its own listeners, which a raw localStorage write would skip.
    func applyNativeSession(_ session: AuthSession) {
        let payload: [String: Any] = [
            "access_token": session.accessToken,
            "refresh_token": session.refreshToken,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            NSLog("[Session bridge] could not serialise native session")
            return
        }

        let js = """
        (async () => {
            try {
                if (!window.__supabase) { return 'no-client'; }
                const { error } = await window.__supabase.auth.setSession(\(json));
                if (error) { return 'error: ' + error.message; }
                return 'ok';
            } catch (e) {
                return 'threw: ' + (e && e.message ? e.message : e);
            }
        })()
        """

        webView?.evaluateJavaScript(js) { result, error in
            if let error {
                NSLog("[Session bridge] push failed: \(error.localizedDescription)")
            } else if let outcome = result as? String, outcome != "ok" {
                NSLog("[Session bridge] push rejected: \(outcome)")
            }
        }
    }

    // MARK: - Language bridge to the web half

    /// Copies the native language setting into the WebView's localStorage,
    /// which is where the React app reads it from, and reloads the page if it
    /// was showing the other language.
    ///
    /// The store is the WebView's own and survives relaunches, so this only
    /// ever has to correct a page: a fresh install has never been told, and
    /// falls back to `navigator.language` — which is the device's language,
    /// the same default the native side starts on.
    ///
    /// At most one reload: after this the stored value matches, so the call
    /// made on the next `didFinish` answers "same" and stops.
    func syncLanguage() {
        let language = LanguageStore.code
        let js = """
        (() => {
            try {
                if (localStorage.getItem('lang') === '\(language)') { return 'same'; }
                localStorage.setItem('lang', '\(language)');
                return 'changed';
            } catch (e) {
                return 'threw: ' + (e && e.message ? e.message : e);
            }
        })()
        """

        webView?.evaluateJavaScript(js) { [weak self] result, error in
            if let error {
                NSLog("[Language bridge] could not set lang: \(error.localizedDescription)")
                return
            }
            guard let outcome = result as? String else { return }
            switch outcome {
            case "same":
                break
            case "changed":
                self?.webView?.reload()
            default:
                NSLog("[Language bridge] rejected: \(outcome)")
            }
        }
    }

    /// Signs the WebView out, so a native sign-out clears both halves.
    func clearWebSession() {
        let js = """
        (async () => {
            try {
                if (window.__supabase) { await window.__supabase.auth.signOut(); }
                for (let i = localStorage.length - 1; i >= 0; i--) {
                    const k = localStorage.key(i);
                    if (k && k.startsWith('sb-') && k.endsWith('-auth-token')) {
                        localStorage.removeItem(k);
                    }
                }
                return 'ok';
            } catch (e) {
                return 'threw: ' + (e && e.message ? e.message : e);
            }
        })()
        """

        webView?.evaluateJavaScript(js) { result, error in
            if let error {
                NSLog("[Session bridge] web sign-out failed: \(error.localizedDescription)")
            } else if let outcome = result as? String, outcome != "ok" {
                NSLog("[Session bridge] web sign-out rejected: \(outcome)")
            }
        }
    }

    /// Copies the supabase-js session out of the WebView's localStorage into
    /// `AuthStore`, so native screens can call the API with the same account.
    ///
    /// Runs after every page load. If the WebView has no session but the
    /// native side does, the session is pushed the other way instead.
    private func importSupabaseSession() {
        let js = """
        (() => {
            try {
                for (let i = 0; i < localStorage.length; i++) {
                    const k = localStorage.key(i);
                    if (k && k.startsWith('sb-') && k.endsWith('-auth-token')) {
                        return localStorage.getItem(k);
                    }
                }
            } catch (e) {
                return null;
            }
            return null;
        })()
        """

        webView?.evaluateJavaScript(js) { [weak self] result, error in
            if let error = error {
                NSLog("[Session bridge] read failed: \(error.localizedDescription)")
                return
            }

            guard let raw = result as? String,
                  let data = raw.data(using: .utf8),
                  let session = Self.parseWebSession(data) else {
                // The WebView is signed out. If the native side is signed in,
                // hand it the session so the two stay in step.
                Task { @MainActor in
                    if let native = AuthStore.shared.session {
                        self?.applyNativeSession(native)
                    }
                }
                return
            }

            Task { @MainActor in
                AuthStore.shared.adopt(fromWebSession: session)
            }
        }
    }

    private static func parseWebSession(_ data: Data) -> AuthSession? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = object["access_token"] as? String,
              let refreshToken = object["refresh_token"] as? String else {
            return nil
        }

        let expiresAt: Double
        if let value = object["expires_at"] as? Double {
            expiresAt = value
        } else if let value = object["expires_in"] as? Double {
            expiresAt = Date().timeIntervalSince1970 + value
        } else {
            expiresAt = Date().timeIntervalSince1970 + 3600
        }

        let email = (object["user"] as? [String: Any])?["email"] as? String

        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            email: email
        )
    }
}

// MARK: - WKScriptMessageHandler (language)

extension CustomViewController: WKScriptMessageHandler {

    /// The web app's own language switch, adopted into the native setting.
    ///
    /// The page has already written its localStorage by the time it posts, so
    /// the `syncLanguage` that follows a native change answers "same" and no
    /// reload comes back at it.
    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "language",
              let code = message.body as? String,
              let language = Language(identifier: code) else { return }

        Task { @MainActor in
            L10n.shared.language = AppLanguage(rawValue: language.rawValue) ?? .system
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
              let identityTokenData = credential.identityToken else {
            return
        }

        // Base64-encode the token to avoid JS string escaping issues
        let tokenBase64 = identityTokenData.base64EncodedString()
        let js = """
        (async () => {
            try {
                const token = atob('\(tokenBase64)');
                console.log('[Apple Sign In] Token received, length:', token.length);

                // Try using the global supabase instance first
                if (window.__supabase) {
                    console.log('[Apple Sign In] Using window.__supabase');
                    const { data, error } = await window.__supabase.auth.signInWithIdToken({
                        provider: 'apple',
                        token: token
                    });
                    if (error) {
                        console.error('[Apple Sign In] signInWithIdToken error:', error.message);
                    } else {
                        console.log('[Apple Sign In] Success, reloading...');
                        window.location.reload();
                        return;
                    }
                }

                // Fallback: post message for the React app to handle
                console.log('[Apple Sign In] Falling back to postMessage');
                window.postMessage({
                    type: 'APPLE_SIGN_IN',
                    idToken: token
                }, '*');
            } catch(e) {
                console.error('[Apple Sign In] Error:', e.message || e);
            }
        })();
        """
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("[Apple Sign In] JS evaluation error: \(error.localizedDescription)")
                }
            }
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
        importSupabaseSession()
        syncLanguage()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        originalDelegate?.webView?(webView, didFail: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        originalDelegate?.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
    }
}
