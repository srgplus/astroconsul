import SwiftUI

/// Who likes one of the reader's charts, and who follows it. Opened from the
/// counts under that chart's reading, so a number is always one tap from the
/// people it counts.
struct PeopleSheet: View {

    enum Tab: String, CaseIterable, Identifiable {
        case likes
        case followers

        var id: String { rawValue }

        var label: String { L(self == .likes ? "people.likes" : "people.followers") }
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
    @State private var people: [Tab: [SocialPerson]] = [:]
    @State private var failures: [Tab: String] = [:]
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

            content
        }
        .tint(.white)
        .presentationBackground { WeatherGlassBackdrop(state: skyState) }
        .environment(\.colorScheme, .dark)
        .task(id: tab) { await load(tab) }
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
                    people = [:]
                    Task {
                        await list.load(showSpinner: false)
                        await load(tab)
                    }
                }
            )
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

    @ViewBuilder
    private var content: some View {
        if let rows = people[tab] {
            if rows.isEmpty {
                Text(L(tab == .likes ? "people.noLikes" : "people.noFollowers"))
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                List {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, person in
                        row(person)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(.white.opacity(0.12))
                            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        } else if let failure = failures[tab] {
            VStack(spacing: 10) {
                Text(failure)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button(L("common.tryAgain")) { Task { await load(tab) } }
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

    private func row(_ person: SocialPerson) -> some View {
        HStack(spacing: 12) {
            Button {
                if let id = person.actor.profileId, list.savedProfileIds.contains(id), let onOpenSaved {
                    dismiss()
                    onOpenSaved(id)
                } else {
                    preview = person.actor.profile
                }
            } label: {
                SocialPersonRow(
                    card: person.actor,
                    action: nil,
                    date: person.date
                )
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

    private func load(_ tab: Tab) async {
        #if DEBUG
        if WeatherPreviewHarness.isEnabled {
            people[tab] = WeatherPreviewData.people(for: tab)
            return
        }
        #endif
        failures[tab] = nil
        do {
            let rows = tab == .likes
                ? try await APIClient.shared.fetchLikers(profileId: profile.profileId)
                : try await APIClient.shared.fetchFollowers(profileId: profile.profileId)
            people[tab] = rows
        } catch {
            guard !error.isCancellation else { return }
            NSLog("[People] \(tab.rawValue) load failed: \(error.localizedDescription)")
            failures[tab] = error.localizedDescription
        }
    }

    private func follow(_ person: ProfileSummary) async {
        guard !following.contains(person.profileId) else { return }
        #if DEBUG
        if WeatherPreviewHarness.isEnabled {
            followedHere.insert(person.profileId)
            preview = nil
            return
        }
        #endif
        following.insert(person.profileId)
        defer { following.remove(person.profileId) }
        if let error = await list.follow(person) {
            errorText = error.localizedDescription
        } else {
            followedHere.insert(person.profileId)
            preview = nil
        }
    }
}
