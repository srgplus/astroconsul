import SwiftUI

/// Weather's saved-cities screen: every profile as a card, tap one to make it
/// the visible page. Reached from the bottom bar, not from a tab.
struct ProfileListScreen: View {

    @ObservedObject var model: ProfileListViewModel
    var onSelect: (ProfileSummary) -> Void
    var onOpenWeb: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showsSettings = false

    private var own: [ProfileSummary] { filter(model.ownProfiles) }
    private var followed: [ProfileSummary] { filter(model.followedProfiles) }

    var body: some View {
        NavigationStack {
            list
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Search profiles")
                .toolbar {
                    // The wordmark reads as a title, so it keeps its own
                    // width and skips the glass pill iOS 26 puts behind
                    // toolbar items; the Settings button keeps its pill.
                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .topBarLeading) {
                            B3Wordmark(size: 24).fixedSize()
                        }
                        .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .topBarLeading) {
                            B3Wordmark(size: 24).fixedSize()
                        }
                    }

                    // Straight to Settings, no menu in between. The web
                    // screens are still reachable from there, and the screen
                    // is dismissed by picking a profile or swiping down.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
        }
        .tint(Theme.text)
        // Settings is presented from here rather than from the pager: a sheet
        // asking its parent to swap one presentation for another can drop the
        // second one on the floor.
        .sheet(isPresented: $showsSettings) {
            SettingsView(onOpenWeb: {
                showsSettings = false
                onOpenWeb()
            })
        }
        // Glass instead of a slab of grey: the weather page underneath stays
        // visible through it, the way Weather's own sheets read on iOS 26.
        .presentationBackground(.ultraThinMaterial)
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
