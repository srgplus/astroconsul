import SwiftUI

/// Weather's saved-cities screen: every profile as a card, tap one to make it
/// the visible page. Reached from the bottom bar, not from a tab.
struct ProfileListScreen: View {

    @ObservedObject var model: ProfileListViewModel
    var onSelect: (ProfileSummary) -> Void

    /// The sky of the page this screen was opened from, so the glass behind it
    /// carries that colour.
    var skyZone: TiiZone?

    var onOpenWeb: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showsSettings = false
    /// Which cards are on screen, by profile id. A `List` recycles its rows,
    /// so this is maintained from their own appear and disappear rather than
    /// measured: a list's rows are hosted separately and their preferences do
    /// not reach back out here, which is the obvious way to do this and does
    /// not work.
    @State private var visibleRows: Set<String> = []

    private var own: [ProfileSummary] { filter(model.ownProfiles) }
    private var followed: [ProfileSummary] { filter(model.followedProfiles) }

    var body: some View {
        content
            // Settings is presented from out here, outside the dark override
            // below, so it opens in the appearance the app is actually set to
            // rather than inheriting this screen's night sky.
            .sheet(isPresented: $showsSettings) {
                SettingsView(skyZone: skyZone, onOpenWeb: {
                    showsSettings = false
                    onOpenWeb()
                })
            }
            // Glass instead of a slab of grey: the weather page underneath
            // stays visible through it, the way Weather's own sheets read on
            // iOS 26.
            .presentationBackground { WeatherGlassBackdrop(zone: skyZone) }
    }

    private var content: some View {
        NavigationStack {
            list
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Search profiles")
                .toolbar {
                    // Which group the list is currently in, on the same line
                    // as the wordmark. As a row of its own it cost a whole
                    // line of a screen made of full-width cards, and it is one
                    // word.
                    if let section = pinnedSection {
                        // A label, not a control, so it skips the glass pill
                        // iOS 26 puts behind toolbar items — the same reason
                        // the wordmark does.
                        if #available(iOS 26.0, *) {
                            ToolbarItem(placement: .topBarLeading) {
                                sectionLabel(section)
                            }
                            .sharedBackgroundVisibility(.hidden)
                        } else {
                            ToolbarItem(placement: .topBarLeading) {
                                sectionLabel(section)
                            }
                        }
                    }

                    // The wordmark reads as a title, so it keeps its own
                    // width and skips the glass pill iOS 26 puts behind
                    // toolbar items; the Settings button keeps its pill.
                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .principal) {
                            B3Wordmark(size: 24).fixedSize()
                        }
                        .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .principal) {
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
                // The system bar draws a material that stops dead in a line
                // across the cards. Hidden, and replaced by a wash that fades
                // out instead — the cards pass under the bar rather than
                // being cut off by it.
                .hidingBarBackground()
                .overlay(alignment: .top) { topWash }
        }
        .tint(Theme.text)
        // This screen stands on a frosted night sky, not on a system
        // background, so its chrome is told which of the two it is. Left to
        // the device's appearance the search field, the group name and the
        // Settings button all resolve for a white page and land as dark ink
        // and light pills on top of the dark wash.
        .environment(\.colorScheme, .dark)
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
        .onAppear { visibleRows.insert(profile.profileId) }
        .onDisappear { visibleRows.remove(profile.profileId) }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }

    /// What holds the wordmark and the group name legible over whatever card
    /// happens to be sliding under them. It sits in the content, below the
    /// bar's own items, and fades to nothing rather than ending in a line.
    private var topWash: some View {
        LinearGradient(
            colors: [.black.opacity(0.42), .black.opacity(0.24), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 140)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, design: .rounded).weight(.semibold))
            .foregroundStyle(.white.opacity(0.75))
            .tracking(0.6)
            .fixedSize()
    }

    /// The group the topmost card on screen belongs to.
    ///
    /// Nil until the list has actually scrolled, on purpose: at rest the first
    /// group's name over its own first card is a caption on something already
    /// in view. It appears once cards start going up under the bar and the
    /// name is the only thing still saying which group you are in.
    private var pinnedSection: String? {
        guard let first = (own.first ?? followed.first)?.profileId,
              !visibleRows.contains(first)
        else { return nil }

        if own.contains(where: { visibleRows.contains($0.profileId) }) { return "Mine" }
        if followed.contains(where: { visibleRows.contains($0.profileId) }) { return "Following" }
        return nil
    }

    /// Name, handle, birthplace and current location all match, so typing a
    /// city finds a profile whichever of the two the card happens to show.
    private func filter(_ profiles: [ProfileSummary]) -> [ProfileSummary] {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return profiles }

        return profiles.filter { profile in
            [
                profile.profileName,
                profile.username,
                profile.locationName ?? "",
                profile.currentLocationName ?? "",
            ]
            .contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }
}
