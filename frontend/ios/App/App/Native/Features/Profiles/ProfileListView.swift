import SwiftUI

struct ProfileListView: View {

    @StateObject private var model = ProfileListViewModel()
    @ObservedObject private var auth = AuthStore.shared

    /// Sends the user to the WebView tab, which still owns sign-in and the
    /// profile detail screens.
    var onOpenWeb: () -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Profiles")
                .navigationBarTitleDisplayMode(.large)
                .background(Theme.bg.ignoresSafeArea())
        }
        .task { await model.load() }
        .onChange(of: auth.session) { _, _ in
            Task { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            loadingView
        case .signedOut:
            signedOutView
        case let .failed(message):
            errorView(message)
        case .loaded:
            if model.profiles.isEmpty {
                emptyView
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            if !model.ownProfiles.isEmpty {
                Section {
                    ForEach(model.ownProfiles) { profile in
                        row(profile)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if profile.profileId != model.primaryProfileId {
                                    Button {
                                        Task { await model.setPrimary(profile) }
                                    } label: {
                                        Label("Primary", systemImage: "star.fill")
                                    }
                                    .tint(Theme.zoneColor(.active))
                                }
                            }
                    }
                } header: {
                    sectionHeader("Mine")
                }
            }

            if !model.followedProfiles.isEmpty {
                Section {
                    ForEach(model.followedProfiles) { profile in
                        row(profile)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await model.unfollow(profile) }
                                } label: {
                                    Label("Unfollow", systemImage: "person.badge.minus")
                                }
                            }
                    }
                } header: {
                    sectionHeader("Following")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .refreshable { await model.load(showSpinner: false) }
    }

    private func row(_ profile: ProfileSummary) -> some View {
        Button(action: onOpenWeb) {
            ProfileRowView(profile: profile, isPrimary: profile.profileId == model.primaryProfileId)
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.surface)
        .listRowSeparatorTint(Theme.line)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.textDim)
            .tracking(0.6)
    }

    // MARK: - States

    private var loadingView: some View {
        ProgressView()
            .controlSize(.large)
            .tint(Theme.spinner)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg.ignoresSafeArea())
    }

    private var signedOutView: some View {
        placeholder(
            icon: "person.crop.circle.badge.questionmark",
            title: "Not signed in",
            message: "Sign in to see your profiles.",
            actionTitle: "Open sign in",
            action: onOpenWeb
        )
    }

    private var emptyView: some View {
        placeholder(
            icon: "person.2",
            title: "No profiles yet",
            message: "Create your first profile to get started.",
            actionTitle: "Create profile",
            action: onOpenWeb
        )
    }

    private func errorView(_ message: String) -> some View {
        placeholder(
            icon: "exclamationmark.triangle",
            title: "Could not load profiles",
            message: message,
            actionTitle: "Try again",
            action: { Task { await model.load() } }
        )
    }

    private func placeholder(
        icon: String,
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: Theme.Spacing.base) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.textDim)

            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.text)

            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)

            Button(actionTitle, action: action)
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.top, 4)
        }
        .padding(Theme.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }
}
