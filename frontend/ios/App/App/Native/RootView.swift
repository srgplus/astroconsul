import SwiftUI

/// Native shell of the app.
///
/// Migration shape: every tab here is native except `.web`, which hosts the
/// Capacitor WebView for screens that have not been ported yet (birth chart,
/// transits, compatibility, sign-in). Ported screens move out of that tab one
/// at a time until it can be removed.
struct RootView: View {

    enum Tab: Hashable {
        case profiles
        case web
        case settings
    }

    @State private var selection: Tab = .profiles
    @AppStorage("nativeAppearance") private var appearance = SettingsView.Appearance.system.rawValue

    var body: some View {
        TabView(selection: $selection) {
            ProfileListView(onOpenWeb: { selection = .web })
                .tabItem { Label("Profiles", systemImage: "person.2.fill") }
                .tag(Tab.profiles)

            WebContainerView()
                .ignoresSafeArea(edges: .top)
                .tabItem { Label("Chart", systemImage: "circle.hexagongrid.fill") }
                .tag(Tab.web)

            SettingsView(onOpenWeb: { selection = .web })
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(Theme.text)
        .preferredColorScheme(SettingsView.Appearance(rawValue: appearance)?.colorScheme)
    }
}
