import SwiftUI

/// The chats: everyone the reader has written to or heard from, the latest
/// first. Drawn the way the owner asked, after a messenger they like: black,
/// the title with the reader's own face beside it, a "+" and a search in one
/// capsule, and rows of a face, a name, a date and the last message.
///
/// A person here is their own chart, and so is the reader: until one of the
/// reader's charts is marked as theirs, the screen asks which one it is
/// instead, because nobody could see who was writing or write back.
struct ChatsScreen: View {

    @ObservedObject var list: ProfileListViewModel

    /// A person already on the list opens on their own page rather than in a
    /// preview; the presenter turns the pager and puts this sheet away.
    var onOpenSaved: ((String) -> Void)?

    /// Somebody was blocked from a chat: the presenter reloads the list.
    var onBlocked: (() -> Void)?

    init(
        list: ProfileListViewModel,
        onOpenSaved: ((String) -> Void)? = nil,
        onBlocked: (() -> Void)? = nil
    ) {
        self.list = list
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
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
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

    /// The chats a search leaves: by name, or by the last thing said.
    private var visibleChats: [ChatSummary] {
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return chats }
        return chats.filter { chat in
            chat.peer.displayName.lowercased().contains(term)
                || (chat.lastMessage?.body.lowercased().contains(term) ?? false)
        }
    }

    /// None of the reader's charts is marked as theirs, as far as a loaded
    /// list can tell, or they have none of their own at all. Not while it
    /// loads: a chat opened from a push can be up before the list is, and
    /// would flash the question for nothing.
    private var needsOwnChart: Bool {
        list.state == .loaded && list.primaryProfile == nil
    }

    /// The reader as the people they write to see them.
    private var ownCard: SocialCard? {
        guard let own = list.primaryProfile else { return nil }
        return SocialCard(
            profileId: own.profileId,
            profileName: own.profileName,
            username: own.username,
            natalSummary: own.natalSummary
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { listToolbar }
                .onAppear {
                    isShowingList = true
                    Task { await load() }
                }
                .onDisappear { isShowingList = false }
                .navigationDestination(for: ChatRoute.self) { route in
                    ChatScreen(
                        route: route,
                        list: list,
                        onOpenSaved: openSaved,
                        onBlocked: onBlocked
                    )
                }
        }
        .tint(.white)
        .presentationBackground(Color.black)
        .presentationDragIndicator(.visible)
        .environment(\.colorScheme, .dark)
        // The pages behind keep decoding their skies for a view nobody has.
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
            NewChatSheet { card in
                guard let profile = card.profile else { return }
                path.append(.profile(profile))
            }
        }
    }

    // MARK: - Header

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        // The title with the reader's face stands on the black, without the
        // glass pill iOS 26 puts behind a toolbar item.
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { title }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { title }
        }

        // One capsule on iOS 26, which groups neighbouring toolbar buttons.
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                composing = true
            } label: {
                Image(systemName: "plus")
            }
            .disabled(needsOwnChart)
            .accessibilityLabel(L("chats.new"))

            Button {
                toggleSearch()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .disabled(needsOwnChart || chats.isEmpty)
            .accessibilityLabel(L("chats.searchPrompt"))
        }
    }

    private var title: some View {
        HStack(spacing: 10) {
            if let ownCard {
                ChatAvatar(card: ownCard, size: 34)
            }
            Text(L("chats.title"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func toggleSearch() {
        searching.toggle()
        if searching {
            searchFocused = true
        } else {
            query = ""
            searchFocused = false
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
                TextField(L("chats.searchPrompt"), text: $query)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Capsule().fill(Color(white: 0.12)))

            Button(L("common.cancel")) { toggleSearch() }
                .font(.system(size: 17))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if needsOwnChart {
            OwnChartChooser(list: list)
        } else {
            VStack(spacing: 0) {
                if searching {
                    searchField
                }

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
    }

    private var rows: some View {
        List {
            ForEach(visibleChats) { chat in
                Button {
                    path.append(.chat(chat))
                } label: {
                    ChatRow(chat: chat)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.black)
                .listRowSeparatorTint(Color(white: 0.2))
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await load() }
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
                .foregroundStyle(Color(white: 0.5))

            Text(title)
                .font(.system(.title3).weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(body)
                .font(.system(.subheadline))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)

            if let action {
                Button(action, action: perform)
                    .font(.system(.body).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 42)
                    .background(Capsule().fill(ChatScreen.mine))
                    .padding(.top, 6)
            }
        }
        .padding(Theme.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One conversation in the list: the face, the name, the date with a chevron,
/// and the last message under it in grey, white while it is unread, with the
/// count of unread ones on the right.
struct ChatRow: View {

    let chat: ChatSummary

    private var isUnread: Bool { chat.unreadCount > 0 }

    private var preview: String {
        chat.lastMessage?.body.replacingOccurrences(of: "\n", with: " ") ?? ""
    }

    var body: some View {
        HStack(spacing: 12) {
            ChatAvatar(card: chat.peer, size: 52)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(chat.peer.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    if let date = chat.date {
                        Text(ChatDate.listStamp(date))
                            .font(.system(size: 15))
                            .monospacedDigit()
                            .foregroundStyle(Color(white: 0.55))
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.4))
                }

                HStack(spacing: 8) {
                    Text(preview)
                        .font(.system(size: 15))
                        .foregroundStyle(isUnread ? .white : Color(white: 0.55))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if isUnread {
                        Text("\(min(chat.unreadCount, 99))")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Capsule().fill(ChatScreen.mine))
                    }
                }
            }
            // The line between rows starts under the text, not under the face.
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in dimensions[.leading] }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnread ? L(count: chat.unreadCount, "chats.unreadCount") : "")
    }
}

/// Asked in place of the list while none of the reader's charts is marked as
/// their own: people write to someone through that chart, and see it when
/// that someone writes to them. The same question as "Which chart is yours?"
/// on the home screen, in its words, inline because the chats are a sheet
/// already. Picking one marks it primary and the chats open.
private struct OwnChartChooser: View {

    @ObservedObject var list: ProfileListViewModel
    @State private var picking: String?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.base) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color(white: 0.5))

                Text(L("primary.title"))
                    .font(.system(.title3).weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(L(list.ownProfiles.isEmpty ? "chats.noOwnChart" : "chats.ownBody"))
                    .font(.system(.subheadline))
                    .foregroundStyle(Color(white: 0.6))
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    ForEach(list.ownProfiles) { profile in
                        Button {
                            picking = profile.profileId
                            failed = false
                            Task {
                                // A refusal is said here, under the charts,
                                // rather than over the pager behind.
                                failed = await list.claimPrimary(profile) != nil
                                picking = nil
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ChatAvatar(
                                    card: SocialCard(
                                        profileId: profile.profileId,
                                        profileName: profile.profileName,
                                        username: profile.username,
                                        natalSummary: profile.natalSummary
                                    ),
                                    size: 40
                                )

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(profile.profileName)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text("@\(profile.username)")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color(white: 0.55))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                if picking == profile.profileId {
                                    ProgressView().controlSize(.small).tint(Theme.spinner)
                                } else {
                                    Text(L("primary.choose"))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(ChatScreen.mine)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 62)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(white: 0.1))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(picking != nil)
                    }
                }
                .padding(.top, 8)

                if failed {
                    Text(L("primary.failed"))
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.error)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(Theme.Spacing.section)
        }
    }
}
