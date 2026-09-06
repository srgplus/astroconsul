import SwiftUI

/// Weather's saved-cities screen: every profile as a card, tap one to make it
/// the visible page. Reached from the bottom bar, not from a tab.
struct ProfileListScreen: View {

    @ObservedObject var model: ProfileListViewModel
    var onSelect: (ProfileSummary) -> Void
    var onOpenSettings: () -> Void
    var onOpenWeb: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var own: [ProfileSummary] { filter(model.ownProfiles) }
    private var followed: [ProfileSummary] { filter(model.followedProfiles) }

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Profiles")
                .navigationBarTitleDisplayMode(.large)
                .searchable(text: $query, prompt: "Search profiles")
                .background(Theme.bg.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                            .font(.system(.body, design: .rounded).weight(.medium))
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                onOpenSettings()
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }

                            Button {
                                onOpenWeb()
                            } label: {
                                Label("Chart, transits, profiles", systemImage: "safari")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More")
                    }
                }
        }
        .tint(Theme.text)
    }

    private var list: some View {
        List {
            if !own.isEmpty {
                Section {
                    ForEach(own) { profile in
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
                    header("Mine")
                }
            }

            if !followed.isEmpty {
                Section {
                    ForEach(followed) { profile in
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
                    header("Following")
                }
            }

            if own.isEmpty && followed.isEmpty {
                Text(query.isEmpty ? "No profiles yet." : "Nothing matches “\(query)”.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load(showSpinner: false) }
    }

    private func row(_ profile: ProfileSummary) -> some View {
        Button {
            onSelect(profile)
        } label: {
            ProfileWeatherCard(profile: profile, isPrimary: profile.profileId == model.primaryProfileId)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.textDim)
            .tracking(0.6)
    }

    /// Name, handle and birthplace all match, so typing a city finds a profile.
    private func filter(_ profiles: [ProfileSummary]) -> [ProfileSummary] {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return profiles }

        return profiles.filter { profile in
            [profile.profileName, profile.username, profile.locationName ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }
}
