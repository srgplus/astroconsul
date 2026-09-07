import SwiftUI

struct SettingsView: View {

    @ObservedObject private var auth = AuthStore.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nativeAppearance") private var appearance = Appearance.system.rawValue

    /// The sky behind the glass, passed down from the screen that presented
    /// this one.
    var skyZone: TiiZone?

    /// Opens the WebView tab. Account deletion still lives there: that flow is
    /// what Apple reviewed under 5.1.1(v), so it is not reimplemented until
    /// the rest of the account screen is native.
    var onOpenWeb: () -> Void

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                appearanceSection
                aboutSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(.body, design: .rounded).weight(.medium))
                }
            }
        }
        // Filled, not frosted. Settings is a form of system controls — a
        // segmented picker, a destructive button, labelled rows — and every
        // one of them is drawn for a background of a known colour. Over a
        // blurred sky they were all being propped up by hand.
        .presentationBackground(Theme.sheetBg)
    }

    private var accountSection: some View {
        Section {
            LabeledContent("Email") {
                Text(auth.email ?? "Not signed in")
                    .foregroundStyle(Theme.textDim)
            }

            Button("Sign out", role: .destructive) {
                auth.signOut()
            }

            Button("Manage account") { onOpenWeb() }
        } header: {
            Text("Account")
        } footer: {
            Text("Account deletion and subscription management open in the app's web view.")
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(Self.versionString).foregroundStyle(Theme.textDim)
            }
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
