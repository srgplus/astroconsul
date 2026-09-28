import SwiftUI

/// The chats: everyone the reader has written to or heard from, the latest
/// first. Drawn the way the owner asked, after a messenger they like: black
/// in the dark and white in the light (`ChatPalette`), the title, a "+" and a
/// search in one capsule, and rows of a face, a name, a date and the last
/// message. Search takes the header's place rather than opening under it.
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
    @ObservedObject private var live = ChatLive.shared
    @ObservedObject private var activity = AppActivity.shared
    @ObservedObject private var strings = L10n.shared
    @Environment(\.dismiss) private var dismiss

    @State private var path: [ChatRoute] = []
    /// The sheet's width, which the header in the bar is stretched across.
    @State private var width: CGFloat = 0
    @State private var state: LoadState = .loading
    @State private var composing = false
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    /// Whether the list itself is on screen, rather than a chat pushed over
    /// it: only then, and with the app in front (`AppActivity`), is it worth
    /// asking the server for fresh rows. State, because the loop below reads
    /// it long after it started.
    @State private var isShowingList = false

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

    /// Sizes taken off the reference: controls 40pt tall, 19pt from the edges,
    /// 41pt faces on 64pt rows. "New Message" draws its rows with them too.
    enum Metrics {
        static let side: CGFloat = 19
        static let control: CGFloat = 40
        static let face: CGFloat = 41
        static let faceGap: CGFloat = 12
        static let row: CGFloat = 64
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .softTopEdge()
                .background {
                    GeometryReader { geometry in
                        ChatPalette.background
                            .ignoresSafeArea()
                            .onAppear { width = geometry.size.width }
                            .onChange(of: geometry.size.width) { _, value in width = value }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                // The whole header as the bar's one item rather than a hidden bar
                // and a header of its own: a chat pushed over the list has a bar,
                // and one appearing where there was none jumps as it slides in.
                .toolbar { headerItem }
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
        .tint(ChatPalette.text)
        .presentationBackground(ChatPalette.background)
        .presentationDragIndicator(.visible)
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
        // Every so often while the list is up. The live line moves the rows
        // as messages come; this is for when it is down, or missed one.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(live.isConnected ? 30 : 8))
                guard !Task.isCancelled else { break }
                if isShowingList, activity.isActive { await load() }
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
    private var headerItem: some ToolbarContent {
        // On the ground, without the glass pill iOS 26 puts behind an item.
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .principal) { header }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { header }
        }
    }

    /// The title with "+" and search beside it, or, while searching, the
    /// search field and a close button in its place: one row of the same
    /// height either way, so the list under it stays where it is.
    private var header: some View {
        ZStack {
            if searching {
                searchBar
                    .transition(.opacity)
            } else {
                titleBar
                    .transition(.opacity)
            }
        }
        .frame(width: max(width - 2 * Metrics.side, 0), height: Metrics.control)
        .animation(.easeInOut(duration: 0.2), value: searching)
    }

    private var titleBar: some View {
        HStack(spacing: 12) {
            title
            Spacer(minLength: 0)
            actions
        }
    }

    /// "+" and search in one glass capsule.
    private var actions: some View {
        HStack(spacing: 0) {
            headerButton("plus", label: L("chats.new"), disabled: needsOwnChart) {
                composing = true
            }
            headerButton("magnifyingglass", label: L("chats.searchPrompt"), disabled: needsOwnChart || chats.isEmpty) {
                toggleSearch()
            }
        }
        .padding(.horizontal, 4)
        .frame(height: Metrics.control)
        .chatGlass(in: Capsule(), interactive: true)
    }

    private func headerButton(
        _ symbol: String,
        label: String,
        disabled: Bool,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(ChatPalette.text)
                .frame(width: 44, height: Metrics.control)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(label)
    }

    private var title: some View {
        Text(L("chats.title"))
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(ChatPalette.text)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }

    private func toggleSearch() {
        searching.toggle()
        if !searching {
            query = ""
            searchFocused = false
        }
    }

    /// The field where the title was, with a round close button beside it.
    private var searchBar: some View {
        HStack(spacing: 8) {
            ChatSearchField(prompt: L("chats.searchField"), text: $query, focus: $searchFocused)

            Button(action: toggleSearch) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ChatPalette.text)
                    .frame(width: Metrics.control, height: Metrics.control)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .chatGlass(in: Circle(), interactive: true)
            .accessibilityLabel(L("common.cancel"))
        }
        .task {
            // Once the field is on screen: focusing it in the same pass as
            // the tap that adds it is dropped.
            try? await Task.sleep(for: .milliseconds(60))
            searchFocused = true
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if needsOwnChart {
            OwnChartChooser(list: list)
        } else {
            VStack(spacing: 0) {
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

    /// A plain column rather than a List: the line between rows starts under
    /// the name and runs to the edge of the screen, as in the reference.
    private var rows: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(visibleChats) { chat in
                    Button {
                        path.append(.chat(chat))
                    } label: {
                        ChatRow(chat: chat, isTyping: store.typingChats.contains(chat.chatId))
                    }
                    .buttonStyle(ChatRowButtonStyle())

                    if chat.id != visibleChats.last?.id {
                        ChatRowSeparator()
                    }
                }
            }
        }
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
                .foregroundStyle(ChatPalette.hint)

            Text(title)
                .font(.system(.title3).weight(.semibold))
                .foregroundStyle(ChatPalette.text)
                .multilineTextAlignment(.center)

            Text(body)
                .font(.system(.subheadline))
                .foregroundStyle(ChatPalette.body)
                .multilineTextAlignment(.center)

            if let action {
                Button(action, action: perform)
                    .font(.system(.body).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 42)
                    .background(Capsule().fill(ChatPalette.mine))
                    .padding(.top, 6)
            }
        }
        .padding(Theme.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One conversation in the list: the face, the name, the date with a chevron,
/// and the last message under it in grey, full strength while it is unread,
/// with the count of unread ones on the right. While the other side types,
/// "typing…" in blue stands in for the last message.
struct ChatRow: View {

    let chat: ChatSummary
    var isTyping = false

    private var isUnread: Bool { chat.unreadCount > 0 }

    private var preview: String {
        chat.lastMessage?.body.replacingOccurrences(of: "\n", with: " ") ?? ""
    }

    private typealias Metrics = ChatsScreen.Metrics

    var body: some View {
        HStack(spacing: Metrics.faceGap) {
            ChatAvatar(card: chat.peer, size: Metrics.face)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(chat.peer.displayName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(ChatPalette.text)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    if let date = chat.date {
                        Text(ChatDate.listStamp(date))
                            .font(.system(size: 15))
                            .monospacedDigit()
                            .foregroundStyle(ChatPalette.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ChatPalette.faint)
                }

                HStack(spacing: 8) {
                    Text(isTyping ? L("chat.typing") : preview)
                        .font(.system(size: 15))
                        .foregroundStyle(
                            isTyping ? ChatPalette.mine : (isUnread ? ChatPalette.text : ChatPalette.secondary)
                        )
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if isUnread {
                        Text("\(min(chat.unreadCount, 99))")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Capsule().fill(ChatPalette.mine))
                    }
                }
            }
        }
        .padding(.horizontal, Metrics.side)
        .frame(minHeight: Metrics.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnread ? L(count: chat.unreadCount, "chats.unreadCount") : "")
    }
}

/// A row greys a little under the finger, full width, as a list row would.
struct ChatRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? ChatPalette.pressed : Color.clear)
    }
}

/// The hairline between rows: from under the name to the edge of the screen.
struct ChatRowSeparator: View {

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(ChatPalette.separator)
            .frame(height: 1 / displayScale)
            .padding(.leading, ChatsScreen.Metrics.side + ChatsScreen.Metrics.face + ChatsScreen.Metrics.faceGap)
    }
}

/// The search capsule of the chats and of "New Message".
struct ChatSearchField: View {

    let prompt: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ChatPalette.body)
            TextField(prompt, text: $text)
                .font(.system(size: 17))
                .foregroundStyle(ChatPalette.text)
                .focused(focus)
                .submitLabel(.search)
                .autocorrectionDisabled()
        }
        .padding(.leading, 15)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: ChatsScreen.Metrics.control)
        .chatGlass(in: Capsule())
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
                    .foregroundStyle(ChatPalette.hint)

                Text(L("primary.title"))
                    .font(.system(.title3).weight(.semibold))
                    .foregroundStyle(ChatPalette.text)
                    .multilineTextAlignment(.center)

                Text(L(list.ownProfiles.isEmpty ? "chats.noOwnChart" : "chats.ownBody"))
                    .font(.system(.subheadline))
                    .foregroundStyle(ChatPalette.body)
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
                                        .foregroundStyle(ChatPalette.text)
                                        .lineLimit(1)
                                    Text("@\(profile.username)")
                                        .font(.system(size: 13))
                                        .foregroundStyle(ChatPalette.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                if picking == profile.profileId {
                                    ProgressView().controlSize(.small).tint(Theme.spinner)
                                } else {
                                    Text(L("primary.choose"))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(ChatPalette.mine)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 62)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(ChatPalette.card)
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
