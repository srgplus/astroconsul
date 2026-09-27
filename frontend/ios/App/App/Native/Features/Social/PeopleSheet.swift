import SwiftUI

/// Who follows one of the reader's charts, and whom the reader follows.
/// Opened from the followers count under that chart's reading, so the number
/// is one tap from the people it counts. Likes are not here: they live in
/// Activity, next to the state of the sky each one was for.
struct PeopleSheet: View {

    enum Tab: String, CaseIterable, Identifiable {
        case followers
        case following

        var id: String { rawValue }

        var label: String { L(self == .followers ? "people.followers" : "people.following") }
    }

    /// One chart and one list on it: what the presenter hands in.
    struct Target: Identifiable, Equatable {
        let profile: ProfileSummary
        let tab: Tab

        var id: String { profile.profileId }
    }

    let profile: ProfileSummary
    @ObservedObject var list: ProfileListViewModel
    var skyState: SkyState?
    /// A person already on the list opens on their own page, as in Activity.
    var onOpenSaved: ((String) -> Void)?

    @State private var tab: Tab
    @State private var followers: [SocialPerson]?
    @State private var failure: String?
    @State private var following: Set<String> = []
    @State private var followedHere: Set<String> = []
    @State private var preview: ProfileSummary?
    @State private var errorText: String?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var strings = L10n.shared

    init(
        target: Target,
        list: ProfileListViewModel,
        skyState: SkyState? = nil,
        onOpenSaved: ((String) -> Void)? = nil
    ) {
        self.profile = target.profile
        self.list = list
        self.skyState = skyState
        self.onOpenSaved = onOpenSaved
        _tab = State(initialValue: target.tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            switch tab {
            case .followers: followersList
            case .following: followingList
            }
        }
        .tint(.white)
        .presentationBackground { WeatherGlassBackdrop(state: skyState) }
        .environment(\.colorScheme, .dark)
        .task { await loadFollowers() }
        .sheet(item: $preview) { person in
            ProfilePreviewSheet(
                profile: person,
                isSubscribing: following.contains(person.profileId),
                isSubscribed: list.savedProfileIds.contains(person.profileId),
                errorText: $errorText,
                onSubscribe: {
                    Task { await follow(person) }
                },
                onBlocked: {
                    preview = nil
                    followers = nil
                    SocialStore.shared.forgetFollowers(of: profile.profileId)
                    Task {
                        await list.load(showSpinner: false)
                        await loadFollowers()
                    }
                }
            )
        }
        // A follow back from a row that the server refused: the row has gone
        // back to "Follow back", and this says why. The preview shows its own.
        .alert(
            L("search.followError"),
            isPresented: Binding(
                get: { errorText != nil && preview == nil },
                set: { if !$0 { errorText = nil } }
            )
        ) {
            Button(L("common.ok"), role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(profile.profileName)
                    .font(.system(size: 17, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                Text("@\(profile.username)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 50)

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .weatherGlass(in: .circle, interactive: true)
                .accessibilityLabel(L("common.close"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Followers

    @ViewBuilder
    private var followersList: some View {
        if let rows = followers {
            if rows.isEmpty {
                empty(L("people.noFollowers"))
            } else {
                rowsList(Array(rows.enumerated()), id: \.offset) { _, person in
                    followerRow(person)
                }
            }
        } else if let failure {
            VStack(spacing: 10) {
                Text(failure)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button(L("common.tryAgain")) { Task { await loadFollowers() } }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ProgressView()
                .tint(Theme.spinner)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func followerRow(_ person: SocialPerson) -> some View {
        HStack(spacing: 12) {
            Button {
                open(person.actor)
            } label: {
                SocialPersonRow(card: person.actor, action: nil, date: person.date)
            }
            .buttonStyle(.plain)
            .disabled(person.actor.profile == nil)

            if let id = person.actor.profileId {
                FollowBackButton(
                    isFollowed: person.actorFollowed || followedHere.contains(id) || list.savedProfileIds.contains(id),
                    isWorking: following.contains(id)
                ) {
                    if let profile = person.actor.profile {
                        Task { await follow(profile) }
                    }
                }
            }
        }
    }

    // MARK: - Following

    /// Every chart the account follows, from the list already loaded: the
    /// same cards the pager swipes through, each opening its own page.
    @ViewBuilder
    private var followingList: some View {
        let followed = list.followedProfiles
        if followed.isEmpty {
            empty(L("people.noFollowing"))
        } else {
            rowsList(followed, id: \.profileId) { profile in
                Button {
                    dismiss()
                    onOpenSaved?(profile.profileId)
                } label: {
                    SocialPersonRow(
                        card: SocialCard(
                            profileId: profile.profileId,
                            profileName: profile.profileName,
                            username: profile.username,
                            natalSummary: profile.natalSummary,
                            latestTransit: profile.latestTransit
                        ),
                        action: nil,
                        detail: "@\(profile.username)"
                    ) {
                        if profile.followsYou == true {
                            Text(L("social.followsYou"))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Pieces

    private func rowsList<Data: RandomAccessCollection, ID: Hashable, Row: View>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder row: @escaping (Data.Element) -> Row
    ) -> some View {
        List {
            ForEach(data, id: id) { element in
                row(element)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(.white.opacity(0.12))
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, design: .rounded))
            .foregroundStyle(.white.opacity(0.65))
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Their page if they are already on the list, the preview otherwise.
    private func open(_ card: SocialCard) {
        if let id = card.profileId, list.savedProfileIds.contains(id), let onOpenSaved {
            dismiss()
            onOpenSaved(id)
        } else {
            preview = card.profile
        }
    }

    private func loadFollowers() async {
        #if DEBUG
        if WeatherPreviewHarness.isEnabled {
            followers = WeatherPreviewData.followers
            return
        }
        #endif
        failure = nil
        // The list from the last open, drawn at once and freshened in place.
        if followers == nil {
            followers = SocialStore.shared.followers[profile.profileId]
        }
        do {
            followers = try await SocialStore.shared.fetchFollowers(of: profile.profileId)
        } catch {
            guard !error.isCancellation else { return }
            NSLog("[People] followers load failed: \(error.localizedDescription)")
            // A kept list stays up rather than turning into an error over one
            // refresh that did not arrive.
            if followers == nil { failure = error.localizedDescription }
        }
    }

    /// Follows from a row or from the preview. The row says "Following" at
    /// once, the way the heart does, and the request catches up; a refusal
    /// takes it back and says why. The preview waits for the server before
    /// it closes, and neither waits for the list to reload behind them.
    private func follow(_ person: ProfileSummary) async {
        let id = person.profileId
        guard !following.contains(id) else { return }
        followedHere.insert(id)
        #if DEBUG
        if WeatherPreviewHarness.isEnabled {
            preview = nil
            return
        }
        #endif
        following.insert(id)
        defer { following.remove(id) }
        if let error = await list.follow(person, waitingForList: false) {
            followedHere.remove(id)
            errorText = error.isCancellation ? nil : error.localizedDescription
        } else {
            preview = nil
        }
    }
}
