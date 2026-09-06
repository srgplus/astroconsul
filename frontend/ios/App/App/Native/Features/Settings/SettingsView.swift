import SwiftUI

struct SettingsView: View {

    @ObservedObject private var auth = AuthStore.shared
    @AppStorage("nativeAppearance") private var appearance = Appearance.system.rawValue

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
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Settings")
        }
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
        .listRowBackground(Theme.surface)
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
        .listRowBackground(Theme.surface)
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(Self.versionString).foregroundStyle(Theme.textDim)
            }
        }
        .listRowBackground(Theme.surface)
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
