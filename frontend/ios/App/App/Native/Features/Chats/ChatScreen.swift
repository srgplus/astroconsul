import SwiftUI
import UIKit

/// One conversation, drawn the way the owner asked, after a messenger they
/// like: black, the person's face at the top with their name in a capsule
/// under it, the reader's words in blue on the right and the other side's in
/// grey on the left, a tail on the last bubble of each run, a date over
/// anything that comes after a pause, and "Seen" under the reader's last
/// message.
///
/// Text only. The name capsule is the menu: their chart, Report and Block,
/// which App Review asks of any chat between people.
struct ChatScreen: View {

    @StateObject private var model: ChatViewModel
    @ObservedObject var list: ProfileListViewModel

    /// A person already on the list opens on their own page; the presenter
    /// turns the pager and puts the chats away.
    var onOpenSaved: ((String) -> Void)?

    /// The person was blocked from here: the presenter reloads the list,
    /// since a block takes the follows between the two with it.
    var onBlocked: (() -> Void)?

    init(
        route: ChatRoute,
        list: ProfileListViewModel,
        onOpenSaved: ((String) -> Void)? = nil,
        onBlocked: (() -> Void)? = nil
    ) {
        _model = StateObject(wrappedValue: ChatViewModel(route: route))
        self.list = list
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

    /// The reader's bubbles: the blue people read as "mine" in a chat.
    static let mine = Color(red: 0.21, green: 0.47, blue: 0.96)

    /// The other side's bubbles.
    static let theirs = Color(red: 0.17, green: 0.17, blue: 0.18)

    /// How long a pause earns a date over the next message.
    private static let pause: TimeInterval = 60 * 60

    /// How close two messages from the same side sit to read as one run.
    private static let run: TimeInterval = 5 * 60

    /// Room at the top of the conversation for the name capsule floating
    /// over it.
    private static let capsuleRoom: CGFloat = 52

    private static let bottom = "bottom"

    var body: some View {
        conversation
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { nameCapsule }
            .background(Color.black.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
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
                // The chat goes with the report: its latest messages are
                // what the moderator reads.
                ReportSheet(profile: profile, chatId: model.chatId) { blocked in
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

    // MARK: - Header

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // The face in the middle of the bar, level with the back button, on
        // the black rather than in the glass pill iOS 26 puts behind items.
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .principal) { face }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { face }
        }
    }

    private var face: some View {
        Group {
            if let peer = model.peer {
                ChatAvatar(card: peer, size: 40)
            }
        }
    }

    /// The name under the face, with a chevron that says it opens something:
    /// their chart, Report and Block.
    private var nameCapsule: some View {
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
            HStack(spacing: 5) {
                Text(model.peer?.displayName ?? " ")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(
                Capsule()
                    .fill(Color(white: 0.12))
                    .overlay(Capsule().stroke(Color(white: 0.24), lineWidth: 0.5))
            )
        }
        .disabled(model.peer?.profile == nil)
        .accessibilityHint(L("chat.viewChart"))
        .padding(.top, 2)
        .frame(maxWidth: .infinity)
        // Messages scroll up under it and fade out rather than meeting it head on.
        .background(alignment: .top) {
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.capsuleRoom + 12)
                .allowsHitTesting(false)
        }
        .opacity(model.peer == nil ? 0 : 1)
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

        case let .failed(text):
            notice(icon: "exclamationmark.triangle", title: L("chat.loadFailed"), body: text) {
                Task { await model.load() }
            }

        case .needsOwnChart:
            notice(icon: "person.crop.circle.badge.questionmark", title: L("primary.title"), body: L("chats.ownBody"))

        case let .refused(text):
            notice(icon: "exclamationmark.bubble", title: L("chat.refusedTitle"), body: text)

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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(white: 0.55))
                            .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                    }

                    if model.messages.isEmpty, model.outgoing.isEmpty {
                        Text(L("chat.start", model.peer?.displayName ?? L("social.someone")))
                            .font(.system(size: 13))
                            .foregroundStyle(Color(white: 0.5))
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
                .padding(.horizontal, 14)
                .padding(.top, Self.capsuleRoom)
                .padding(.bottom, 6)
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
    /// one on its way, with the date over it after a pause, a tail when it
    /// ends a run, and the status under it when it is the reader's last.
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
        /// Follows a message from the same side closely: drawn tight to it.
        var continuesRun = false
        /// The last of its run: carries the tail.
        var endsRun = true
        var status: String?

        var isFailed: Bool {
            if case let .outgoing(item) = content { return item.failed }
            return false
        }
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
            let date = rows[index].date ?? Date()
            guard index > 0 else {
                if rows[index].date != nil { rows[index].stamp = ChatDate.separator(date) }
                continue
            }
            let previous = rows[index - 1]
            let gap = date.timeIntervalSince(previous.date ?? Date())
            if gap >= Self.pause {
                rows[index].stamp = ChatDate.separator(date)
            } else if previous.isMine == rows[index].isMine, gap < Self.run {
                rows[index].continuesRun = true
                rows[index - 1].endsRun = false
            }
        }

        // "Seen" or "Delivered" under the reader's last message, when it is
        // the last of the conversation: under anything older it is old news.
        if let last = rows.indices.last, rows[last].isMine, case let .message(message) = rows[last].content {
            let isRead = (model.chat?.peerReadId ?? 0) >= message.id
            rows[last].status = L(isRead ? "chat.read" : "chat.delivered")
        }
        return rows
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        VStack(spacing: 4) {
            if let stamp = row.stamp {
                Text(stamp)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
            }

            HStack(spacing: 0) {
                if row.isMine { Spacer(minLength: 64) }
                bubble(row)
                if !row.isMine { Spacer(minLength: 64) }
            }

            switch row.content {
            case let .outgoing(item):
                if let refusal = item.refusal {
                    refusalLine(item, refusal)
                } else if item.failed {
                    Button {
                        Task { await model.retry(item) }
                    } label: {
                        Label(L("chat.failed"), systemImage: "exclamationmark.circle")
                            .font(.system(size: 12, weight: .medium))
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
        .padding(.top, row.stamp != nil ? 0 : (row.continuesRun ? 3 : 12))
    }

    private func bubble(_ row: Row) -> some View {
        let fill = row.isMine ? Self.mine.opacity(row.isFailed ? 0.45 : 1) : Self.theirs
        return Text(row.body)
            .font(.system(size: 17))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(fill)
            }
            .overlay(alignment: row.isMine ? .bottomTrailing : .bottomLeading) {
                if row.endsRun {
                    BubbleTail(isMine: row.isMine, color: fill)
                }
            }
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
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

    /// Why the server would not take a message, in its words, under the
    /// bubble: no "try again", since the same text would be refused again.
    /// A limit passes, so that one can be tapped once the wait is over.
    @ViewBuilder
    private func refusalLine(_ item: ChatViewModel.Outgoing, _ text: String) -> some View {
        let label = Label(text, systemImage: "exclamationmark.circle")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.error)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 64)
        if item.canRetry {
            Button {
                Task { await model.retry(item) }
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    private func statusLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color(white: 0.55))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 6)
            .padding(.top, 2)
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

    /// One capsule, the send button inside it on the right: grey while
    /// there is nothing to send, blue once there is.
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField(L("chat.placeholder"), text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .tint(Self.mine)
                .focused($isComposing)
                .padding(.leading, 16)
                .padding(.vertical, 11)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSend ? Color.white : Color(white: 0.45))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(canSend ? Self.mine : Color(white: 0.2)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .padding(.trailing, 6)
            .padding(.bottom, 6)
            .accessibilityLabel(L("chat.send"))
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(white: 0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color(white: 0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.black.ignoresSafeArea())
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
                .foregroundStyle(Color(white: 0.5))

            Text(title)
                .font(.system(.title3).weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(body)
                .font(.system(.subheadline))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)

            if let retry {
                Button(L("common.tryAgain"), action: retry)
                    .font(.system(.body).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 42)
                    .background(Capsule().fill(Self.mine))
                    .padding(.top, 6)
            }
        }
        .padding(Theme.Spacing.section)
    }
}

/// The tail on the last bubble of a run: a round one tucked into the bottom
/// corner and a small one beyond it, the way the reference draws it.
private struct BubbleTail: View {

    let isMine: Bool
    let color: Color

    var body: some View {
        ZStack(alignment: isMine ? .bottomTrailing : .bottomLeading) {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
                .offset(x: isMine ? 3 : -3, y: 2)

            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .offset(x: isMine ? 10 : -10, y: 8)
        }
        .frame(width: 14, height: 14, alignment: isMine ? .bottomTrailing : .bottomLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
