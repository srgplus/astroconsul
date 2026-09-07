import SwiftUI

/// Weather's saved-cities screen: every profile as a card, tap one to make it
/// the visible page. Reached from the bottom bar, not from a tab.
struct ProfileListScreen: View {

    @ObservedObject var model: ProfileListViewModel
    var onSelect: (ProfileSummary) -> Void

    /// The sky of the page this screen was opened from, so the glass behind it
    /// carries that colour.
    var skyState: SkyState?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var strings = L10n.shared
    @State private var query = ""
    @State private var showsSettings = false
    @State private var showsNewProfile = false

    /// The profile the create sheet just made. Held rather than acted on at
    /// once: the pager is turned to it after that sheet has closed, so the
    /// two dismissals do not land in the same frame.
    @State private var createdProfile: ProfileSummary?

    private var own: [ProfileSummary] { filter(model.ownProfiles) }
    private var followed: [ProfileSummary] { filter(model.followedProfiles) }

    var body: some View {
        content
            // Settings is presented from out here, outside the dark override
            // below, so it opens in the appearance the app is actually set to
            // rather than inheriting this screen's night sky.
            .sheet(isPresented: $showsSettings) {
                SettingsView(skyState: skyState)
            }
            // Out here for the same reason as Settings: the form is made of
            // system controls drawn for the appearance the app is set to, not
            // for this screen's night sky.
            .sheet(isPresented: $showsNewProfile, onDismiss: openCreatedProfile) {
                ProfileEditSheet(skyState: skyState) { createdProfile = $0 }
            }
            // Glass instead of a slab of grey: the weather page underneath
            // stays visible through it, the way Weather's own sheets read on
            // iOS 26.
            .presentationBackground { WeatherGlassBackdrop(state: skyState) }
            // The pages behind this sheet keep decoding their full-screen skies
            // for a view nobody has — the backdrop above draws its own. Handing
            // those decoders back leaves them for the cards being scrolled.
            .onAppear { SkyPlayerPool.shared.setPlaying(false, variant: .screen) }
            .onDisappear { SkyPlayerPool.shared.setPlaying(true, variant: .screen) }
    }

    private var content: some View {
        NavigationStack {
            list
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: L("profiles.searchPrompt"))
                .toolbar {
                    // A new profile of your own, opposite Settings. The group
                    // names used to sit here; they are headers in the list
                    // now, where they scroll with the cards they name.
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showsNewProfile = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(L("profiles.new"))
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
                        .accessibilityLabel(L("settings.title"))
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
                                        Label(L("profiles.primary"), systemImage: "star.fill")
                                    }
                                    .tint(Theme.zoneColor(.active))
                                }
                            }
                    }
                } header: {
                    sectionHeader(L("profiles.mine"))
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
                                    Label(L("weather.unfollow"), systemImage: "person.badge.minus")
                                }
                            }
                    }
                } header: {
                    sectionHeader(L("profiles.following"))
                }
            }

            if own.isEmpty && followed.isEmpty {
                Text(query.isEmpty ? L("profiles.none") : L("profiles.noMatch", query))
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

    /// What holds the wordmark, the buttons and the pinned group name legible
    /// over whatever card happens to be sliding under them. It sits in the
    /// content, below the bar's own items, and fades to nothing rather than
    /// ending in a line.
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

    /// The group's name over its own cards, flush with their left edge. A
    /// plain list pins these as they reach the top, so the name stays with
    /// the group you are scrolling through without holding a line of the bar.
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, design: .rounded).weight(.semibold))
            .foregroundStyle(.white.opacity(0.75))
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
    }

    /// The pager's page comes from the list model, so the new profile has to
    /// be in it before the pager is pointed at it.
    private func openCreatedProfile() {
        guard let created = createdProfile else { return }
        createdProfile = nil

        Task {
            await model.load(showSpinner: false)
            onSelect(created)
        }
    }

    /// The same test the search screen applies, so a term that finds a profile
    /// there finds it here too.
    private func filter(_ profiles: [ProfileSummary]) -> [ProfileSummary] {
        profiles.filter { $0.matches(query) }
    }
}
