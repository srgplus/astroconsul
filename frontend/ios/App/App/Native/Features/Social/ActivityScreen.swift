import SwiftUI

/// Who liked the reader's charts and who started following them, newest
/// first — the half of the app that comes back. Following used to go one way:
/// a chart's owner never learned anyone was there.
///
/// A row opens the person's chart in the same preview a search result opens,
/// and "Follow back" follows it without leaving the list.
struct ActivityScreen: View {

    @ObservedObject var list: ProfileListViewModel
    @StateObject private var model: ActivityViewModel

    /// The sky of the page this screen was opened from, for the glass.
    var skyState: SkyState?

    /// Where "Find people" goes when there is nothing here yet: the search
    /// screen, which the presenter owns.
    var onFindPeople: (() -> Void)?

    /// A person already on the list opens on their own page rather than in a
    /// preview: their page has today's sky, the preview only the chart.
    var onOpenSaved: ((String) -> Void)?

    init(
        list: ProfileListViewModel,
        skyState: SkyState? = nil,
        onFindPeople: (() -> Void)? = nil,
        onOpenSaved: ((String) -> Void)? = nil
    ) {
        self.list = list
        self.skyState = skyState
        self.onFindPeople = onFindPeople
        self.onOpenSaved = onOpenSaved
        _model = StateObject(wrappedValue: ActivityViewModel())
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var strings = L10n.shared
    @State private var preview: ProfileSummary?
    @State private var previewError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .tint(.white)
        .presentationBackground { WeatherGlassBackdrop(state: skyState) }
        .environment(\.colorScheme, .dark)
        .task {
            await model.load()
            // After the load, so the rows keep the "New" they arrived with;
            // the dot on the home screen goes now.
            await SocialStore.shared.markActivitySeen()
        }
        .refreshable { await model.load() }
        .sheet(item: $preview) { profile in
            ProfilePreviewSheet(
                profile: profile,
                isSubscribing: model.following.contains(profile.profileId),
                isSubscribed: list.savedProfileIds.contains(profile.profileId),
                errorText: $previewError,
                onSubscribe: {
                    Task {
                        if let error = await list.follow(profile) {
                            previewError = error.localizedDescription
                        } else {
                            preview = nil
                        }
                    }
                },
                onBlocked: {
                    preview = nil
                    Task {
                        await list.load(showSpinner: false)
                        await model.load()
                    }
                }
            )
        }
        .alert(
            L("search.followError"),
            isPresented: Binding(
                get: { model.errorText != nil && preview == nil },
                set: { if !$0 { model.errorText = nil } }
            )
        ) {
            Button(L("common.ok"), role: .cancel) { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text(L("activity.title"))
                .font(.system(size: 17, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)

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
        .padding(.bottom, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            VStack(spacing: 10) {
                ProgressView().tint(Theme.spinner)
                Text(L("common.loading"))
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(text):
            message(
                icon: "exclamationmark.triangle",
                title: L("activity.loadFailed"),
                body: text,
                action: L("common.tryAgain"),
                perform: { Task { await model.load() } }
            )

        case .loaded:
            if model.items.isEmpty {
                message(
                    icon: "heart",
                    title: L("activity.emptyTitle"),
                    body: L("activity.emptyBody"),
                    action: onFindPeople == nil ? nil : L("activity.findPeople"),
                    perform: {
                        dismiss()
                        onFindPeople?()
                    }
                )
            } else {
                rows
            }
        }
    }

    private var rows: some View {
        List {
            if !model.unread.isEmpty {
                section(L("activity.new"), items: model.unread)
            }
            if !model.earlier.isEmpty {
                section(L(model.unread.isEmpty ? "activity.recent" : "activity.earlier"), items: model.earlier)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func section(_ title: String, items: [ActivityItem]) -> some View {
        Section {
            ForEach(items) { item in
                row(item)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(.white.opacity(0.12))
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            }
        } header: {
            Text(title.uppercased())
                .font(.system(size: 12, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(0.6)
        }
    }

    /// The row opens the person's chart; the button beside it follows them
    /// back. Two buttons side by side rather than one inside the other, which
    /// a list row cannot tell apart.
    private func row(_ item: ActivityItem) -> some View {
        HStack(spacing: 12) {
            Button {
                open(item.actor)
            } label: {
                SocialPersonRow(
                    card: item.actor,
                    action: sentence(for: item),
                    date: item.date,
                    isUnread: item.isUnread
                )
            }
            .buttonStyle(.plain)
            .disabled(item.actor.profile == nil)

            if item.actor.profileId != nil {
                FollowBackButton(
                    isFollowed: model.isFollowed(item, saved: list.savedProfileIds),
                    isWorking: item.actor.profileId.map(model.following.contains) ?? false
                ) {
                    Task { await model.followBack(item.actor, using: list) }
                }
            }
        }
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

    /// "liked your chart" for the reader's own chart, "liked Mum" for another
    /// chart they keep: most accounts hold one chart, and naming it back to
    /// its owner reads oddly.
    private func sentence(for item: ActivityItem) -> String {
        let isPrimary = item.target.profileId == list.primaryProfileId
        let name = item.target.profileName ?? "@\(item.target.username ?? "")"
        switch item.kind {
        case .like:
            return isPrimary ? L("activity.likedYours") : L("activity.likedOther", name)
        case .follow:
            return isPrimary ? L("activity.followedYou") : L("activity.followedOther", name)
        }
    }

    // MARK: - States

    private func message(
        icon: String,
        title: String,
        body: String,
        action: String?,
        perform: @escaping () -> Void
    ) -> some View {
        VStack(spacing: Theme.Spacing.base) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white.opacity(0.6))

            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)

            Text(body)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)

            if let action {
                Button(action, action: perform)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .weatherGlass(in: .capsule, tint: 0.3, interactive: true)
                    .padding(.top, 4)
            }
        }
        .padding(Theme.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
