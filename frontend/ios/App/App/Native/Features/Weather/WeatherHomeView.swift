import SwiftUI

/// The app's home screen: cosmic weather for one profile at a time, swiped
/// like Weather's cities. There is no tab bar — the bottom bar's two buttons
/// reach the chart (web) and the profile list.
struct WeatherHomeView: View {

    @StateObject private var model = ProfileListViewModel()
    @ObservedObject private var auth = AuthStore.shared

    @State private var selection = ""
    @State private var showsList = false
    @State private var showsWeb = false
    @State private var showsSettings = false

    private var profiles: [ProfileSummary] {
        model.ownProfiles + model.followedProfiles
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                placeholder { ProgressView().controlSize(.large).tint(Theme.spinner) }

            case .signedOut:
                placeholder {
                    message(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "Not signed in",
                        body: "Sign in to see your cosmic weather.",
                        action: "Open sign in",
                        perform: { showsWeb = true }
                    )
                }

            case let .failed(text):
                placeholder {
                    message(
                        icon: "exclamationmark.triangle",
                        title: "Could not load profiles",
                        body: text,
                        action: "Try again",
                        perform: { Task { await model.load() } }
                    )
                }

            case .loaded:
                if profiles.isEmpty {
                    placeholder {
                        message(
                            icon: "person.2",
                            title: "No profiles yet",
                            body: "Create your first profile to get a reading.",
                            action: "Create profile",
                            perform: { showsWeb = true }
                        )
                    }
                } else {
                    pager
                }
            }
        }
        .task { await model.load() }
        .onChange(of: auth.session) { _, _ in
            Task { await model.load() }
        }
        .onChange(of: model.profiles) { _, _ in syncSelection() }
        .fullScreenCover(isPresented: $showsList) { listScreen }
        .fullScreenCover(isPresented: $showsWeb) { WebScreen() }
        .sheet(isPresented: $showsSettings) {
            SettingsView(onOpenWeb: {
                showsSettings = false
                showsWeb = true
            })
        }
    }

    private var pager: some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top

            WeatherPager(
                profiles: profiles,
                selection: $selection,
                primaryProfileId: model.primaryProfileId,
                onOpenChart: { showsWeb = true },
                onOpenList: { showsList = true }
            ) { profile in
                CosmicWeatherView(profile: profile, topInset: topInset)
            }
        }
    }

    private var listScreen: some View {
        ProfileListScreen(
            model: model,
            onSelect: { profile in
                selection = profile.profileId
                showsList = false
            },
            onOpenSettings: {
                showsList = false
                showsSettings = true
            },
            onOpenWeb: {
                showsList = false
                showsWeb = true
            }
        )
    }

    /// Keeps the visible page pointed at a profile that still exists, falling
    /// back to the primary one.
    private func syncSelection() {
        guard !profiles.isEmpty else {
            selection = ""
            return
        }
        if profiles.contains(where: { $0.profileId == selection }) { return }
        selection = model.primaryProfileId ?? profiles[0].profileId
    }

    // MARK: - States

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            content()
        }
    }

    private func message(
        icon: String,
        title: String,
        body: String,
        action: String,
        perform: @escaping () -> Void
    ) -> some View {
        VStack(spacing: Theme.Spacing.base) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.textDim)

            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.text)

            Text(body)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)

            Button(action, action: perform)
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.top, 4)
        }
        .padding(Theme.Spacing.section)
    }
}
