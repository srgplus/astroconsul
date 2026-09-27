import Foundation

/// Feeds one conversation: its messages, what is on its way out, and how far
/// the other side has read.
///
/// There is no socket. While the screen is up it asks for whatever came after
/// the newest message every few seconds, and a push that lands with the app
/// open makes it ask at once. A message is drawn the moment it is sent and
/// sits there as "Sending" until the server has it.
@MainActor
final class ChatViewModel: ObservableObject {

    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
        /// The reader has no chart marked as their own, so there is no one
        /// for the other side to see or answer.
        case needsOwnChart
    }

    /// A message written here that the server does not have yet.
    struct Outgoing: Identifiable, Equatable {
        let id: UUID
        let body: String
        var failed: Bool
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var chat: ChatSummary?
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var outgoing: [Outgoing] = []
    /// Older history the screen has not asked for yet.
    @Published private(set) var hasOlder = false
    @Published private(set) var isLoadingOlder = false

    /// Whether the app is in front with this screen on it. Polling stops
    /// while it is not, and a message is only read when it could be seen.
    var isActive = true

    let route: ChatRoute
    private let api: APIClient

    init(route: ChatRoute, api: APIClient = .shared) {
        self.route = route
        self.api = api
        if case let .chat(summary) = route {
            chat = summary
        }
    }

    /// Who the chat is with: the server's card once it has answered, what the
    /// route carried until then.
    var peer: SocialCard? {
        if let chat { return chat.peer }
        guard case let .profile(profile) = route else { return nil }
        return SocialCard(
            profileId: profile.profileId,
            profileName: profile.profileName,
            username: profile.username,
            natalSummary: profile.natalSummary,
            latestTransit: profile.latestTransit
        )
    }

    var chatId: Int? {
        if let chat { return chat.chatId }
        if case let .chatId(id) = route { return id }
        return nil
    }

    var canWrite: Bool { state == .loaded }

    // MARK: - Loading

    func load() async {
        #if DEBUG
        if WeatherPreviewHarness.isEnabled {
            loadPreview()
            return
        }
        #endif
        do {
            let id = try await resolveChatId()
            let page = try await api.fetchMessages(chatId: id)
            adopt(page.chat)
            messages = page.messages
            hasOlder = page.hasMore
            state = .loaded
            await markRead()
        } catch {
            guard !error.isCancellation else { return }
            if Self.isMissingOwnChart(error) {
                state = .needsOwnChart
                return
            }
            NSLog("[Chat] load failed: \(error.localizedDescription)")
            // Only over a spinner: messages already on screen stay up.
            if messages.isEmpty { state = .failed(error.localizedDescription) }
        }
    }

    /// Asks for whatever came after the newest message on screen.
    func poll() async {
        #if DEBUG
        if WeatherPreviewHarness.isEnabled { return }
        #endif
        guard state == .loaded, isActive, let id = chatId else { return }
        do {
            let page = try await api.fetchMessages(chatId: id, after: messages.last?.id ?? 0)
            adopt(page.chat)
            absorb(page.messages, matchingOutgoing: true)
            await markRead()
        } catch {
            if !error.isCancellation {
                NSLog("[Chat] poll failed: \(error.localizedDescription)")
            }
        }
    }

    /// The page before the oldest message on screen.
    func loadOlder() async {
        #if DEBUG
        if WeatherPreviewHarness.isEnabled { return }
        #endif
        guard hasOlder, !isLoadingOlder, let id = chatId, let oldest = messages.first?.id else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await api.fetchMessages(chatId: id, before: oldest)
            let known = Set(messages.map(\.id))
            messages = page.messages.filter { !known.contains($0.id) } + messages
            hasOlder = page.hasMore
        } catch {
            if !error.isCancellation {
                NSLog("[Chat] older messages failed: \(error.localizedDescription)")
            }
        }
    }

    /// The chat's number: the route's, or the one the server gives the chart
    /// the route came from, made on first asking.
    private func resolveChatId() async throws -> Int {
        if let chatId { return chatId }
        guard case let .profile(profile) = route else { throw APIError.http(status: 404, detail: nil) }
        let opened = try await api.openChat(profileId: profile.profileId)
        adopt(opened)
        return opened.chatId
    }

    /// Takes the server's summary, and tells the kept list about it. Only
    /// when it changed: every poll brings one, and each assignment redraws
    /// the whole conversation.
    private func adopt(_ summary: ChatSummary) {
        if summary != chat { chat = summary }
        ChatStore.shared.update(summary)
    }

    /// Merges messages from the server into the ones on screen, in order.
    ///
    /// From a poll, a message of the reader's own can come back before its
    /// send has answered; the bubble waiting for it is that message, and goes.
    private func absorb(_ incoming: [ChatMessage], matchingOutgoing: Bool) {
        guard !incoming.isEmpty else { return }
        var known = Set(messages.map(\.id))
        var merged = messages
        for message in incoming where !known.contains(message.id) {
            merged.append(message)
            known.insert(message.id)
            if matchingOutgoing, message.isMine,
               let waiting = outgoing.firstIndex(where: { !$0.failed && $0.body == message.body }) {
                outgoing.remove(at: waiting)
            }
        }
        merged.sort { $0.id < $1.id }
        if merged != messages { messages = merged }
    }

    /// Tells the server the screen has shown everything the other side wrote,
    /// when there is anything unread to tell it about.
    private func markRead() async {
        guard isActive, let id = chatId, let newest = messages.last?.id, (chat?.unreadCount ?? 0) > 0 else { return }
        do {
            let left = try await api.markChatRead(chatId: id, upTo: newest)
            ChatStore.shared.setUnread(left)
            if var read = chat {
                read.unreadCount = 0
                adopt(read)
            }
        } catch {
            if !error.isCancellation {
                NSLog("[Chat] mark read failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Sending

    /// Draws the message at once and sends it behind.
    func send(_ text: String) async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let item = Outgoing(id: UUID(), body: body, failed: false)
        outgoing.append(item)
        await deliver(item)
    }

    /// Tries a message that did not go again.
    func retry(_ item: Outgoing) async {
        guard let index = outgoing.firstIndex(where: { $0.id == item.id }) else { return }
        outgoing[index].failed = false
        await deliver(outgoing[index])
    }

    /// Gives up on a message that did not go.
    func discard(_ item: Outgoing) {
        outgoing.removeAll { $0.id == item.id }
    }

    private func deliver(_ item: Outgoing) async {
        #if DEBUG
        if WeatherPreviewHarness.isEnabled {
            outgoing.removeAll { $0.id == item.id }
            messages.append(
                ChatMessage(
                    id: (messages.last?.id ?? 0) + 1,
                    body: item.body,
                    isMine: true,
                    createdAt: ISO8601DateFormatter().string(from: Date())
                )
            )
            return
        }
        #endif
        do {
            let id = try await resolveChatId()
            let message = try await api.sendMessage(chatId: id, body: item.body)
            outgoing.removeAll { $0.id == item.id }
            absorb([message], matchingOutgoing: false)
            if let chat {
                // The list's row for this chat: this message on top of it.
                ChatStore.shared.update(
                    ChatSummary(
                        chatId: chat.chatId,
                        peer: chat.peer,
                        lastMessage: message,
                        unreadCount: 0,
                        peerReadId: chat.peerReadId,
                        updatedAt: message.createdAt
                    )
                )
            }
        } catch {
            guard !error.isCancellation else { return }
            NSLog("[Chat] send failed: \(error.localizedDescription)")
            if Self.isMissingOwnChart(error) { state = .needsOwnChart }
            if let index = outgoing.firstIndex(where: { $0.id == item.id }) {
                outgoing[index].failed = true
            }
        }
    }

    private static func isMissingOwnChart(_ error: Error) -> Bool {
        if case let .http(status, _) = error as? APIError { return status == 409 }
        return false
    }

    // MARK: - Harness

    #if DEBUG
    private func loadPreview() {
        switch route {
        case let .chat(summary):
            chat = summary
        case let .chatId(id):
            chat = WeatherPreviewData.chats.first { $0.chatId == id }
        case .profile:
            break
        }
        messages = chat.map { WeatherPreviewData.chatMessages(for: $0.chatId) } ?? []
        state = .loaded
    }
    #endif
}
