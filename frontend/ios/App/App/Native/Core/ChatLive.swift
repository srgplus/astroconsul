import Combine
import Foundation

/// One event down the chats' live line. Mirrors
/// `app/application/services/chat_live.py`; the decoder converts snake case.
struct ChatLiveEvent: Decodable {
    /// `ready`, `message`, `read`, `typing` or `unread`. Anything else is a
    /// newer server's and is passed over.
    let type: String
    let chatId: Int?
    /// `message`: the new message, as this account reads it.
    let message: ChatMessage?
    /// `message`: the chat's row as this account's list draws it.
    let chat: ChatSummary?
    /// `message` and `unread`: what is unread across every chat.
    let unreadCount: Int?
    /// `read`: the last of the reader's messages the other side has read.
    let peerReadId: Int?
    /// `typing`: started, or stopped.
    let typing: Bool?
}

/// The chats' live line: one WebSocket to `/api/v1/chats/live` while the
/// reader is signed in and the app is in front.
///
/// Down it come the messages written to the reader, "Seen" when theirs are
/// read, and the dots while someone types, as it happens. The list and the
/// badge are kept by `ChatStore` from here; a conversation on screen takes
/// its own events from `events`. Up it goes one thing, the reader typing.
///
/// Nothing depends on it. Every message and every read still goes through
/// the REST routes; the screens poll, slower while the line is up. When it
/// comes back after a drop, `ChatStore.lineOpened` has the screens on show
/// fetch whatever they missed.
@MainActor
final class ChatLive: ObservableObject {

    static let shared = ChatLive()

    /// The server has said `ready` on the line that is open now.
    @Published private(set) var isConnected = false

    /// Every event, after the list and the badge have taken theirs.
    let events = PassthroughSubject<ChatLiveEvent, Never>()

    /// How often the phone checks the line is still there. Under Cloudflare's
    /// 100 seconds of quiet, and soon enough to notice a dead line.
    private static let heartbeat: Duration = .seconds(25)

    /// The longest wait between two tries at a line that keeps failing.
    private static let longestRetry: TimeInterval = 60

    private let session: URLSession
    private let decoder: JSONDecoder

    private var socket: URLSessionWebSocketTask?
    private var isOpening = false
    private var wanted = false
    private var started = false
    private var retryDelay: TimeInterval = 1
    private var retry: Task<Void, Never>?
    private var pings: Task<Void, Never>?
    private var observers: Set<AnyCancellable> = []

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    /// From here on the line is kept open whenever the reader is signed in
    /// and the app is in front, and closed otherwise. Safe to call again.
    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
        // The harness has no account and no server.
        if WeatherPreviewHarness.isEnabled { return }
        #endif
        AppActivity.shared.$isActive
            .combineLatest(AuthStore.shared.$session.map { $0 != nil }.removeDuplicates())
            .sink { [weak self] active, signedIn in
                self?.want(active && signedIn)
            }
            .store(in: &observers)
    }

    /// Tells the other side of a chat that the reader is typing, or stopped.
    /// Dropped while the line is down: the dots are a nicety, not a message.
    func sendTyping(chatId: Int, typing: Bool) {
        guard isConnected, let socket else { return }
        let text = "{\"type\":\"typing\",\"chat_id\":\(chatId),\"typing\":\(typing)}"
        socket.send(.string(text)) { error in
            if let error {
                NSLog("[ChatLive] typing not sent: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - The line

    private func want(_ wanted: Bool) {
        guard wanted != self.wanted else { return }
        self.wanted = wanted
        if wanted {
            retryDelay = 1
            // A turn later: `$session` says so before the session is stored,
            // and the token is read from it.
            Task { self.connect() }
        } else {
            disconnect()
        }
    }

    private func connect() {
        guard wanted, socket == nil, !isOpening else { return }
        isOpening = true
        Task { await open() }
    }

    private func open() async {
        defer { isOpening = false }
        guard let url = Self.url else {
            NSLog("[ChatLive] no URL for the live line")
            return
        }
        guard let token = await AuthStore.shared.validAccessToken() else {
            // A refresh that failed off the network is tried again; signed
            // out, there is nothing to open.
            if AuthStore.shared.isSignedIn { scheduleRetry() }
            return
        }
        guard wanted else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(LanguageStore.code, forHTTPHeaderField: "Accept-Language")
        let task = session.webSocketTask(with: request)
        socket = task
        task.resume()
        listen(on: task)
        keepAlive(task)
    }

    private func listen(on task: URLSessionWebSocketTask) {
        Task { [weak self] in
            while true {
                let message: URLSessionWebSocketTask.Message
                do {
                    message = try await task.receive()
                } catch {
                    self?.lost(task, error)
                    return
                }
                guard let self, task === self.socket else { return }
                self.handle(message)
            }
        }
    }

    /// A ping now and then: a line that no longer answers is dropped and
    /// tried again, rather than sitting there looking open.
    private func keepAlive(_ task: URLSessionWebSocketTask) {
        pings?.cancel()
        pings = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeat)
                guard !Task.isCancelled else { return }
                task.sendPing { error in
                    guard let error else { return }
                    Task { @MainActor in ChatLive.shared.lost(task, error) }
                }
            }
        }
    }

    /// The line went: logged, and tried again after a wait that doubles
    /// with each failure in a row.
    private func lost(_ task: URLSessionWebSocketTask, _ error: Error) {
        guard task === socket else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode
        NSLog("[ChatLive] line lost\(status.map { " (HTTP \($0))" } ?? ""): \(error.localizedDescription)")
        socket = nil
        pings?.cancel()
        pings = nil
        isConnected = false
        task.cancel(with: .goingAway, reason: nil)
        scheduleRetry()
    }

    private func scheduleRetry() {
        guard wanted, retry == nil else { return }
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, Self.longestRetry)
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.retry = nil
            self.connect()
        }
    }

    private func disconnect() {
        retry?.cancel()
        retry = nil
        pings?.cancel()
        pings = nil
        let task = socket
        socket = nil
        isConnected = false
        task?.cancel(with: .goingAway, reason: nil)
    }

    private static var url: URL? {
        guard var components = URLComponents(
            url: AppConfig.apiBaseURL.appendingPathComponent("/api/v1/chats/live"),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        let secure = components.scheme != "http"
        components.scheme = secure ? "wss" : "ws"
        return components.url
    }

    // MARK: - Events

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case let .string(text):
            data = Data(text.utf8)
        case let .data(bytes):
            data = bytes
        @unknown default:
            return
        }
        do {
            let event = try decoder.decode(ChatLiveEvent.self, from: data)
            dispatch(event)
        } catch {
            NSLog("[ChatLive] unreadable event: \(error)")
        }
    }

    private func dispatch(_ event: ChatLiveEvent) {
        let store = ChatStore.shared
        switch event.type {
        case "ready":
            isConnected = true
            retryDelay = 1
            // Whatever happened while the line was down.
            Task { await store.lineOpened() }
        case "message":
            if let chat = event.chat { store.update(chat) }
            if let count = event.unreadCount { store.setUnread(count) }
            // A message from them ends their typing.
            if let chatId = event.chatId, event.message?.isMine == false {
                store.peerTyping(chatId, false)
            }
        case "read":
            if let chatId = event.chatId, let upTo = event.peerReadId {
                store.peerRead(chatId: chatId, upTo: upTo)
            }
        case "unread":
            if let count = event.unreadCount { store.setUnread(count) }
            if let chatId = event.chatId { store.readElsewhere(chatId: chatId) }
        case "typing":
            if let chatId = event.chatId { store.peerTyping(chatId, event.typing ?? true) }
        default:
            break
        }
        events.send(event)
    }
}
