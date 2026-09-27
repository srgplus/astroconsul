import SwiftUI

/// The chats: everyone the reader has written to or heard from, the latest
/// first, the way Messages lists its conversations. A row opens the
/// conversation, the pencil starts a new one with somebody the reader follows
/// or is followed by.
///
/// A person here is their own chart, and so is the reader: until one of the
/// reader's charts is marked as theirs, the screen asks which one it is
/// instead, because nobody could see who was writing or write back.
struct ChatsScreen: View {

    @ObservedObject var list: ProfileListViewModel

    /// The sky of the page this screen was opened from, for the glass.
    var skyState: SkyState?

    /// A person already on the list opens on their own page rather than in a
    /// preview; the presenter turns the pager and puts this sheet away.
    var onOpenSaved: ((String) -> Void)?

    /// Somebody was blocked from a chat: the presenter reloads the list.
    var onBlocked: (() -> Void)?

    init(
        list: ProfileListViewModel,
        skyState: SkyState? = nil,
        onOpenSaved: ((String) -> Void)? = nil,
        onBlocked: (() -> Void)? = nil
    ) {
        self.list = list
        self.skyState = skyState
        self.onOpenSaved = onOpenSaved
        self.onBlocked = onBlocked
    }

    @ObservedObject private var store = ChatStore.shared
    @ObservedObject private var strings = L10n.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var path: [ChatRoute] = []
    @State private var state: LoadState = .loading
    @State private var composing = false
    /// Whether the list itself is on screen, rather than a chat pushed over
    /// it, and the app is in front: only then is it worth asking the server
    /// for fresh rows. State rather than the environment's `scenePhase`,
    /// because the loop below reads it long after it started.
    @State private var isShowingList = false
    @State private var isActive = true

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private var chats: [ChatSummary] { store.chats ?? [] }

    /// None of the reader's charts is marked as theirs, as far as a loaded
    /// list can tell. Not while it loads: a chat opened from a push can be up
    /// before the list is, and would flash the question for nothing.
    private var needsOwnChart: Bool {
        list.state == .loaded && list.primaryProfileId == nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(L("chats.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            composing = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .disabled(needsOwnChart)
                        .accessibilityLabel(L("chats.new"))
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(L("common.close"))
                    }
                }
                .hidingBarBackground()
                .onAppear {
                    isShowingList = true
                    Task { await load() }
                }
                .onDisappear { isShowingList = false }
                .navigationDestination(for: ChatRoute.self) { route in
                    ChatScreen(
                        route: route,
                        list: list,
                        skyState: skyState,
                        onOpenSaved: openSaved,
                        onBlocked: onBlocked
                    )
                }
        }
        .tint(.white)
        .presentationBackground { WeatherGlassBackdrop(state: skyState) }
        .environment(\.colorScheme, .dark)
        // The pages behind keep decoding their skies for a view nobody has;
        // the backdrop above draws its own.
        .onAppear {
            SkyPlayerPool.shared.setPlaying(false, variant: .screen)
            takePendingRoute()
        }
        .onDisappear { SkyPlayerPool.shared.setPlaying(true, variant: .screen) }
        .onChange(of: store.pendingRoute) { _, _ in takePendingRoute() }
        .onChange(of: store.arrivals) { _, _ in
            if isShowingList { Task { await load() } }
        }
        .onChange(of: scenePhase) { _, phase in
            isActive = phase == .active
        }
        // Every so often while the list is up, for a message that arrives
        // without a push: APNs may not be set up, or the phone may say no.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { break }
                if isShowingList, isActive { await load() }
            }
        }
        .sheet(isPresented: $composing) {
            NewChatSheet(skyState: skyState) { card in
                guard let profile = card.profile else { return }
                path.append(.profile(profile))
            }
        }
    }

    /// A chat somebody asked for from outside: a push, or "Message" on a
    /// chart. Opened over the list, so Back lands on the chats.
    private func takePendingRoute() {
        guard let route = store.pendingRoute else { return }
        store.pendingRoute = nil
        path = [route]
    }

    private func openSaved(_ profileId: String) {
        dismiss()
        onOpenSaved?(profileId)
    }

    private func load() async {
        // The rows the last fetch left: the screen opens on them and this
        // freshens them in place.
        if store.chats != nil, state == .loading { state = .loaded }
        do {
            _ = try await store.fetchChats()
            state = .loaded
        } catch {
            guard !error.isCancellation else { return }
            NSLog("[Chats] load failed: \(error.localizedDescription)")
            if state == .loading { state = .failed(error.localizedDescription) }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if needsOwnChart {
            OwnChartChooser(list: list)
        } else {
            switch state {
            case .loading:
                ProgressView()
                    .tint(Theme.spinner)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case let .failed(text):
                message(
                    icon: "exclamationmark.triangle",
                    title: L("chats.loadFailed"),
                    body: text,
                    action: L("common.tryAgain"),
                    perform: { Task { await load() } }
                )

            case .loaded:
                if chats.isEmpty {
                    message(
                        icon: "bubble.left.and.bubble.right",
                        title: L("chats.emptyTitle"),
                        body: L("chats.emptyBody"),
                        action: L("chats.new"),
                        perform: { composing = true }
                    )
                } else {
                    rows
                }
            }
        }
    }

    private var rows: some View {
        List {
            ForEach(chats) { chat in
                Button {
                    path.append(.chat(chat))
                } label: {
                    ChatRow(chat: chat)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(.white.opacity(0.12))
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 20))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

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
                .multilineTextAlignment(.center)

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

/// One conversation in the list: the person as their Sun sign and name, the
/// last message under it, the time on the right, and a blue dot while any of
/// theirs is unread.
struct ChatRow: View {

    let chat: ChatSummary

    private var isUnread: Bool { chat.unreadCount > 0 }

    /// "You: …" in front of the reader's own last message, as Messages does.
    private var preview: String {
        guard let last = chat.lastMessage else { return "" }
        let text = last.body.replacingOccurrences(of: "\n", with: " ")
        return last.isMine ? L("chats.you", text) : text
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isUnread ? ChatScreen.mine : Color.clear)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)

            SocialAvatar(card: chat.peer, size: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(chat.peer.displayName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let date = chat.date {
                        Text(ChatDate.listStamp(date))
                            .font(.system(size: 13, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

                Text(preview)
                    .font(.system(size: 14, weight: isUnread ? .medium : .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(isUnread ? 0.9 : 0.6))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnread ? L(count: chat.unreadCount, "chats.unreadCount") : "")
    }
}

/// Asked in place of the list while none of the reader's charts is marked as
/// their own: people write to someone through that chart, and see it when
/// that someone writes to them. Picking one marks it primary, the same as the
/// star in the profile list, and the chats open.
private struct OwnChartChooser: View {

    @ObservedObject var list: ProfileListViewModel
    @State private var picking: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.base) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.white.opacity(0.6))

                Text(L("chats.ownTitle"))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(L(list.ownProfiles.isEmpty ? "chats.noOwnChart" : "chats.ownBody"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    ForEach(list.ownProfiles) { profile in
                        Button {
                            picking = profile.profileId
                            Task {
                                await list.setPrimary(profile)
                                picking = nil
                            }
                        } label: {
                            HStack(spacing: 12) {
                                SocialAvatar(
                                    card: SocialCard(
                                        profileId: profile.profileId,
                                        profileName: profile.profileName,
                                        username: profile.username,
                                        natalSummary: profile.natalSummary
                                    ),
                                    size: 36
                                )

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(profile.profileName)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text("@\(profile.username)")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.55))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                if picking == profile.profileId {
                                    ProgressView().controlSize(.small).tint(Theme.spinner)
                                } else {
                                    Text(L("chats.ownPick"))
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 58)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(picking != nil)
                        .weatherGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: 0.28, interactive: true)
                    }
                }
                .padding(.top, 8)
            }
            .padding(Theme.Spacing.section)
        }
    }
}
