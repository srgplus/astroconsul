import AuthenticationServices
import SwiftUI

/// Native sign-in.
///
/// Email code is the primary path: nothing to remember, and no deep link back
/// into the app, unlike a magic link. Password is kept behind a disclosure for
/// accounts that already have one.
struct SignInView: View {

    private enum Step: Equatable {
        case email
        case code
        case password
    }

    @ObservedObject private var auth = AuthStore.shared

    @State private var step: Step = .email
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var isError = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case email, code, password }

    private var emailLooksValid: Bool {
        let value = email.trimmed
        guard let at = value.firstIndex(of: "@"), at != value.startIndex else { return false }
        let domain = value[value.index(after: at)...]
        return domain.contains(".") && !domain.hasSuffix(".")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.loose) {
                header

                switch step {
                case .email: emailStep
                case .code: codeStep
                case .password: passwordStep
                }

                if let message {
                    Text(message)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(isError ? Theme.error : Theme.textDim)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                if step != .code {
                    divider
                    providerButtons
                    passwordToggle
                }
            }
            .padding(Theme.Spacing.section)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: step)
        .disabled(busy)
        // Nothing to wait for here: the form is the content.
        .onAppear { AppLaunch.shared.markContentReady() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            // The mark the splash just faded out of, not a system-font
            // approximation of it — same asset, same two appearances.
            Image("B3Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 160)
                .accessibilityLabel("big3.me")

            Text(subtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.section)
        .padding(.bottom, Theme.Spacing.tight)
    }

    private var subtitle: String {
        switch step {
        case .email: return "Sign in with your email"
        case .code: return "We sent a code to \(email.trimmed)"
        case .password: return "Sign in with your password"
        }
    }

    // MARK: - Steps

    private var emailStep: some View {
        VStack(spacing: Theme.Spacing.base) {
            field(placeholder: "Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .onSubmit(sendCode)

            primaryButton("Send code", enabled: emailLooksValid, action: sendCode)
        }
    }

    private var codeStep: some View {
        VStack(spacing: Theme.Spacing.base) {
            field(placeholder: "6-digit code", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .font(.system(.title3, design: .monospaced))
                .multilineTextAlignment(.center)
                .focused($focus, equals: .code)

            primaryButton("Sign in", enabled: code.count >= 6, action: verifyCode)

            HStack(spacing: Theme.Spacing.loose) {
                Button("Resend", action: sendCode)
                Button("Change email") {
                    code = ""
                    message = nil
                    step = .email
                    focus = .email
                }
            }
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(Theme.textDim)
        }
    }

    private var passwordStep: some View {
        VStack(spacing: Theme.Spacing.base) {
            field(placeholder: "Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)

            secureField(placeholder: "Password", text: $password)
                .focused($focus, equals: .password)
                .onSubmit(signInWithPassword)

            primaryButton(
                "Sign in",
                enabled: emailLooksValid && !password.isEmpty,
                action: signInWithPassword
            )
        }
    }

    // MARK: - Providers

    private var divider: some View {
        HStack(spacing: Theme.Spacing.base) {
            Rectangle().fill(Theme.line).frame(height: 1)
            Text("or")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textDim)
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    private var providerButtons: some View {
        VStack(spacing: Theme.Spacing.base) {
            // Not SignInWithAppleButton: that view builds its own request, and
            // the nonce Supabase verifies has to be the one
            // AppleSignInController generated. Same look, our own trigger.
            Button(action: signInWithApple) {
                HStack(spacing: Theme.Spacing.tight) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 17, weight: .medium))
                    Text("Continue with Apple")
                        .font(.system(.body, design: .rounded).weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(Theme.bg)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.text)
                )
            }

            // The mark, the surface and the border are Google's, not ours:
            // their branding guidelines forbid redrawing or recolouring the G.
            Button(action: signInWithGoogle) {
                HStack(spacing: Theme.Spacing.tight) {
                    Image("GoogleLogo")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                    Text("Continue with Google")
                        .font(.system(.body, design: .rounded).weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(GoogleBrand.label)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(GoogleBrand.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(GoogleBrand.border, lineWidth: 1)
                )
            }
        }
    }

    private var passwordToggle: some View {
        Button(step == .password ? "Sign in with a code instead" : "Sign in with password") {
            message = nil
            code = ""
            password = ""
            step = step == .password ? .email : .password
        }
        .font(.system(.footnote, design: .rounded))
        .foregroundStyle(Theme.textDim)
        .padding(.top, Theme.Spacing.tight)
    }

    // MARK: - Controls

    private func field(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(.horizontal, Theme.Spacing.loose)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.surfaceSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
            .foregroundStyle(Theme.text)
    }

    private func secureField(placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textContentType(.password)
            .padding(.horizontal, Theme.Spacing.loose)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.surfaceSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
            .foregroundStyle(Theme.text)
    }

    private func primaryButton(
        _ title: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                if busy {
                    ProgressView().tint(Theme.bg)
                } else {
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(Theme.bg)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.text.opacity(enabled ? 1 : 0.4))
            )
        }
        .disabled(!enabled || busy)
    }

    // MARK: - Actions

    private func sendCode() {
        guard emailLooksValid else { return }
        run {
            try await auth.sendEmailCode(to: email)
            code = ""
            step = .code
            focus = .code
            show("Check your inbox for the code.", error: false)
        }
    }

    private func verifyCode() {
        run {
            try await auth.signIn(email: email, code: code)
        }
    }

    private func signInWithPassword() {
        run {
            try await auth.signIn(email: email, password: password)
        }
    }

    private func signInWithApple() {
        run { try await auth.signInWithApple() }
    }

    private func signInWithGoogle() {
        run { try await auth.signInWithGoogle() }
    }

    /// Shared busy-state and error handling for every sign-in action.
    private func run(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        message = nil
        focus = nil

        Task {
            do {
                try await work()
            } catch {
                // Backing out of a system sheet is not a failure to report.
                if !Self.isCancellation(error) {
                    show(error.localizedDescription, error: true)
                }
            }
            busy = false
        }
    }

    private func show(_ text: String, error: Bool) {
        isError = error
        message = text
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if case AppleSignInController.AppleSignInError.cancelled = error { return true }
        if case GoogleSignInController.GoogleSignInError.cancelled = error { return true }
        return false
    }
}

/// Google's button palette, taken from their sign-in branding guidelines.
/// Deliberately outside Theme: these colours are Google's to set, not ours.
private enum GoogleBrand {
    static let surface = dynamic(dark: 0x131314, light: 0xFFFFFF)
    static let border = dynamic(dark: 0x8E918F, light: 0x747775)
    static let label = dynamic(dark: 0xE3E3E3, light: 0x1F1F1F)

    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}
