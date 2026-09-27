import SwiftUI
import UIKit

/// One conversation, drawn the way Messages draws one: the reader's words in
/// blue on the right, the other side's on glass on the left, a time over
/// anything that comes after a pause, and "Read" or "Delivered" under the
/// reader's last message.
///
/// Text only. The person is at the top as their own chart; the ••• has their
/// chart, Report and Block, which App Review asks of any chat between people.
struct ChatScreen: View {

    @StateObject private var model: ChatViewModel
    @ObservedObject var list: ProfileListViewModel

    /// The sky of the page the chats were opened from, for the backdrop.
    var skyState: SkyState?

    /// A person already on the list opens on their own page; the presenter
    /// turns the pager and puts the chats away.
    var onOpenSaved: ((String) -> Void)?

    /// The person was blocked from here: the presenter reloads the list,
    /// since a block takes the follows between the two with it.
    var onBlocked: (() -> Void)?

    init(
        route: ChatRoute,
        list: ProfileListViewModel,
        skyState: SkyState? = nil,
        onOpenSaved: ((String) -> Void)? = nil,
        onBlocked: (() -> Void)? = nil
    ) {
        _model = StateObject(wrappedValue: ChatViewModel(route: route))
        self.list = list
        self.skyState = skyState
        self.onOpenSaved = onOpenSaved
        self.onBlocked = onBlocked
    }

    @ObservedObject private var store = ChatStore.shared
    @ObservedObject private var strings = L10n.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = ""
    @FocusState private var isComposing: Bool
    @State private var reporting: ProfileSummary?
    @State private var blocking: ProfileSummary?
    @State private var preview: ProfileSummary?
    @State private var previewError: String?

    /// iMessage's own blue, the one colour people read as "mine" in a chat.
    static let mine = Color(red: 0.04, green: 0.52, blue: 1.0)

    /// How long a pause earns a time over the next message.
    private static let pause: TimeInterval = 60 * 60

    /// How close two messages from the same side sit to read as one run.
    private static let run: TimeInterval = 5 * 60

    private static let bottom = "bottom"

    var body: some View {
        conversation
            .background { ChatBackdrop(state: skyState) }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .hidingBarBackground()
            .task { await model.load() }
            // Every few seconds while the chat is up and the app is in front:
            // there is no socket, and a push only comes when APNs is set up.
            .task(id: model.chatId) {
                guard model.chatId != nil else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { break }
                    await model.poll()
                }
            }
            .onAppear {
                model.isActive = scenePhase == .active
                store.visibleChatId = model.chatId
            }
            .onDisappear {
                if store.visibleChatId == model.chatId { store.visibleChatId = nil }
            }
            .onChange(of: model.chatId) { _, id in store.visibleChatId = id }
            .onChange(of: scenePhase) { _, phase in
                model.isActive = phase == .active
                if phase == .active { Task { await model.poll() } }
            }
            .onChange(of: store.arrivals) { _, _ in
                Task { await model.poll() }
            }
            .sheet(item: $reporting) { profile in
                ReportSheet(profile: profile) { blocked in
                    if blocked { leaveBlocked() }
                }
            }
            .blockConfirmation($blocking) { _ in
                leaveBlocked()
            }
            .sheet(item: $preview) { profile in
                ProfilePreviewSheet(
                    profile: profile,
                    isSubscribed: list.savedProfileIds.contains(profile.profileId),
                    errorText: $previewError,
                    onSubscribe: {
                        Task {
                            if let error = await list.follow(profile, waitingForList: false) {
                                previewError = error.localizedDescription
                            } else {
                                preview = nil
                            }
                        }
                    },
                    onBlocked: {
                        preview = nil
                        leaveBlocked()
                    }
                )
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // The person reads as a title, so it skips the glass pill iOS 26 puts
        // behind toolbar items, the way the list's wordmark does.
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .principal) { header }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { header }
        }

        ToolbarItem(placement: .topBarTrailing) { menu }
    }

    /// Their Sun sign over their name, as Messages puts a face over a name.
    private var header: some View {
        Button(action: openChart) {
            VStack(spacing: 1) {
                if let peer = model.peer {
                    SocialAvatar(card: peer, size: 26)
                }
                Text(model.peer?.displayName ?? " ")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.peer?.profile == nil)
        .accessibilityHint(L("chat.viewChart"))
    }

    private var menu: some View {
        Menu {
            if let profile = model.peer?.profile {
                Button(action: openChart) {
                    Label(L("chat.viewChart"), systemImage: "person.crop.circle")
                }

                Divider()

                Button {
                    reporting = profile
                } label: {
                    Label(L("social.report"), systemImage: "exclamationmark.bubble")
                }

                // Plain, not red, as on a chart's •••: the confirmation that
                // follows is where the destructive button sits.
                Button {
                    blocking = profile
                } label: {
                    Label(L("social.block"), systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
        }
        .disabled(model.peer?.profile == nil)
        .accessibilityLabel(L("weather.profileOptions"))
    }

    /// Their page if they are on the list already, the preview otherwise.
    private func openChart() {
        guard let profile = model.peer?.profile else { return }
        if list.savedProfileIds.contains(profile.profileId), let onOpenSaved {
            onOpenSaved(profile.profileId)
        } else {
            preview = profile
        }
    }

    /// Blocked from here: the chat is gone from both sides, so this screen
    /// goes back to the list, which no longer has it.
    private func leaveBlocked() {
        if let id = model.chatId { store.forget(chatId: id) }
        onBlocked?()
        dismiss()
    }

    // MARK: - Conversation

    @ViewBuilder
    private var conversation: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .tint(Theme.spinner)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(text):
            notice(icon: "exclamationmark.triangle", title: L("chat.loadFailed"), body: text) {
                Task { await model.load() }
            }

        case .needsOwnChart:
            notice(icon: "person.crop.circle.badge.questionmark", title: L("chats.ownTitle"), body: L("chats.ownBody"))

        case .loaded:
            messagesList
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.hasOlder {
                        Button {
                            Task { await model.loadOlder() }
                        } label: {
                            Group {
                                if model.isLoadingOlder {
                                    ProgressView().controlSize(.small).tint(Theme.spinner)
                                } else {
                                    Text(L("chat.earlier"))
                                }
                            }
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 4)
                    }

                    if model.messages.isEmpty, model.outgoing.isEmpty {
                        Text(L("chat.start", model.peer?.displayName ?? L("social.someone")))
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 24)
                            .padding(.horizontal, 32)
                    }

                    ForEach(rows) { row in
                        rowView(row)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottom)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            // The newest message in view whenever one is added, sent or come in.
            .onChange(of: rows.last?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottom, anchor: .bottom)
                }
            }
            .onChange(of: isComposing) { _, composing in
                guard composing else { return }
                Task {
                    // After the keyboard has taken its room.
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(Self.bottom, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Rows

    /// One line of the conversation, as drawn: a message from the server or
    /// one on its way, with the time over it after a pause and the status
    /// under it when it is the reader's last.
    private struct Row: Identifiable {
        enum Content {
            case message(ChatMessage)
            case outgoing(ChatViewModel.Outgoing)
        }

        let id: String
        let content: Content
        let body: String
        let isMine: Bool
        let date: Date?
        var stamp: String?
        var tight = false
        var status: String?
    }

    private var rows: [Row] {
        var rows: [Row] = model.messages.map { message in
            Row(
                id: "m\(message.id)",
                content: .message(message),
                body: message.body,
                isMine: message.isMine,
                date: message.date
            )
        }
        rows += model.outgoing.map { item in
            Row(id: "o\(item.id.uuidString)", content: .outgoing(item), body: item.body, isMine: true, date: nil)
        }

        for index in rows.indices {
            let previous = index > 0 ? rows[index - 1] : nil
            let date = rows[index].date ?? Date()
            let previousDate = previous.map { $0.date ?? Date() }
            if let previousDate {
                if date.timeIntervalSince(previousDate) >= Self.pause {
                    rows[index].stamp = ChatDate.separator(date)
                } else if previous?.isMine == rows[index].isMine, date.timeIntervalSince(previousDate) < Self.run {
                    rows[index].tight = true
                }
            } else if rows[index].date != nil {
                rows[index].stamp = ChatDate.separator(date)
            }
        }

        // "Read" or "Delivered" under the reader's last message, when it is
        // the last of the conversation: under anything older it is old news.
        if let last = rows.indices.last, rows[last].isMine, case let .message(message) = rows[last].content {
            let isRead = (model.chat?.peerReadId ?? 0) >= message.id
            rows[last].status = L(isRead ? "chat.read" : "chat.delivered")
        }
        return rows
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        VStack(spacing: 3) {
            if let stamp = row.stamp {
                Text(stamp)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 14)
                    .padding(.bottom, 6)
            }

            HStack(spacing: 0) {
                if row.isMine { Spacer(minLength: 56) }
                bubble(row)
                if !row.isMine { Spacer(minLength: 56) }
            }

            switch row.content {
            case let .outgoing(item):
                if item.failed {
                    Button {
                        Task { await model.retry(item) }
                    } label: {
                        Label(L("chat.failed"), systemImage: "exclamationmark.circle")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.error)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    statusLine(L("chat.sending"))
                }
            case .message:
                if let status = row.status {
                    statusLine(status)
                }
            }
        }
        .padding(.top, row.tight || row.stamp != nil ? 2 : 8)
    }

    private func bubble(_ row: Row) -> some View {
        let isFailed: Bool = {
            if case let .outgoing(item) = row.content { return item.failed }
            return false
        }()
        return Text(row.body)
            .font(.system(size: 16, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(row.isMine ? Self.mine.opacity(isFailed ? 0.45 : 1) : Color.white.opacity(0.16))
            }
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contextMenu {
                Button {
                    UIPasteboard.general.string = row.body
                } label: {
                    Label(L("chat.copy"), systemImage: "doc.on.doc")
                }
                if case let .outgoing(item) = row.content, item.failed {
                    Button(role: .destructive) {
                        model.discard(item)
                    } label: {
                        Label(L("common.delete"), systemImage: "trash")
                    }
                }
            }
    }

    private func statusLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 4)
    }

    // MARK: - Composer

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The server takes up to 2000 characters; the button says so by
    /// staying off rather than by a refusal after the tap.
    private var canSend: Bool {
        model.canWrite && !trimmedDraft.isEmpty && trimmedDraft.count <= 2000
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(L("chat.placeholder"), text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.white)
                .focused($isComposing)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .weatherGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), tint: 0.28)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(canSend ? Self.mine : Color.white.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(L("chat.send"))
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .disabled(!model.canWrite)
    }

    private func send() {
        guard canSend else { return }
        let text = trimmedDraft
        draft = ""
        Task {
            await model.send(text)
            // Somebody who has just written will want to hear the answer:
            // the place to be asked about notifications, if nothing has asked.
            await PushNotifications.shared.offerOnce()
        }
    }

    // MARK: - States

    private func notice(
        icon: String,
        title: String,
        body: String,
        retry: (() -> Void)? = nil
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

            if let retry {
                Button(L("common.tryAgain"), action: retry)
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

/// The ground a conversation stands on: the same frosted sky as the chats
/// sheet, drawn solid so the list does not show through while the chat slides
/// in over it. No footage behind the frost, which a blur would not show.
struct ChatBackdrop: View {

    var state: SkyState?

    var body: some View {
        ZStack {
            if let state {
                WeatherSky.gradient(for: state.zone)
            } else {
                Theme.bgDeep
            }
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .ignoresSafeArea()
    }
}
