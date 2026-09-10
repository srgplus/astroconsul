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

    /// The model's groups narrowed to the search term. A group with nothing
    /// left in it drops out, so a search does not leave its name behind over
    /// an empty stretch of sky.
    private var groups: [ProfileGroup] {
        model.listGroups.compactMap { group in
            let matches = filter(group.profiles)
            let keepsPinned = group.kind == .favorites && pinned != nil
            guard !matches.isEmpty || keepsPinned else { return nil }
            return ProfileGroup(kind: group.kind, profiles: matches)
        }
    }

    /// The primary profile, which heads Favourites and is not draggable.
    private var pinned: ProfileSummary? {
        guard let primary = model.primaryProfile, primary.matches(query) else { return nil }
        return primary
    }

    /// Cards can only be dragged into a new order while the whole list is on
    /// screen. Under a search term the row above the one you drop onto is not
    /// the row that will be there when the term clears, so there is no honest
    /// answer to what a move means.
    private var canReorder: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Which profiles this account owns. Asked of the model rather than of
    /// each profile's `is_own` flag, which the API has been known to get wrong
    /// for the owner's own primary profile.
    private var owned: Set<String> { model.ownedProfileIds }

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
            ForEach(groups) { group in
                section(group)
            }

            if groups.isEmpty {
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

    /// One group of cards under its own name.
    ///
    /// The rows carry `onMove`, which is what lets a card be picked up with a
    /// press and dropped somewhere else in its own group; a press that stays
    /// put opens the menu instead. Moves are scoped to the group, so a card
    /// cannot be dragged out of Following and into Mine — being followed is
    /// not something a drag decides.
    private func section(_ group: ProfileGroup) -> some View {
        Section {
            if group.kind == .favorites, let pinned {
                // The primary profile, held at the top. It is page one of the
                // pager, so the list has nowhere else to put it and the drag
                // has nothing to take hold of.
                row(pinned)
            }

            ForEach(group.profiles) { profile in
                row(profile)
                    .contextMenu { menu(for: profile) }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if owned.contains(profile.profileId), profile.profileId != model.primaryProfileId {
                            Button {
                                Task { await model.setPrimary(profile) }
                            } label: {
                                Label(L("profiles.primary"), systemImage: "star.fill")
                            }
                            .tint(Theme.zoneColor(.active))
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if !owned.contains(profile.profileId) {
                            Button(role: .destructive) {
                                Task { await model.unfollow(profile) }
                            } label: {
                                Label(L("weather.unfollow"), systemImage: "person.badge.minus")
                            }
                        }
                    }
            }
            .onMove(perform: canReorder ? { model.move(in: group.kind, from: $0, to: $1) } : nil)
        } header: {
            sectionHeader(title(of: group.kind))
        }
    }

    /// What a press that stays put offers. The same three things the swipes
    /// do, plus the star, which has no swipe of its own: a card already has
    /// one action per edge.
    @ViewBuilder
    private func menu(for profile: ProfileSummary) -> some View {
        let isOwn = owned.contains(profile.profileId)

        if model.canToggleFavorite(profile) {
            Button {
                model.toggleFavorite(profile)
            } label: {
                if model.isFavorite(profile) {
                    Label(L("profiles.removeFavorite"), systemImage: "star.slash")
                } else {
                    Label(L("profiles.addFavorite"), systemImage: "star")
                }
            }
        }

        if isOwn, profile.profileId != model.primaryProfileId {
            Button {
                Task { await model.setPrimary(profile) }
            } label: {
                Label(L("profiles.primary"), systemImage: "star.fill")
            }
        }

        if !isOwn {
            Button(role: .destructive) {
                Task { await model.unfollow(profile) }
            } label: {
                Label(L("weather.unfollow"), systemImage: "person.badge.minus")
            }
        }
    }

    private func title(of kind: ProfileGroup.Kind) -> String {
        switch kind {
        case .favorites: return L("profiles.favorites")
        case .mine: return L("profiles.mine")
        case .following: return L("profiles.following")
        }
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
