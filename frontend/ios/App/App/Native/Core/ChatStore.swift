import Foundation

/// What the chats have to agree on across screens: how many messages are
/// unread, for the button beside the bell and the app icon; the list as last
/// fetched, so the screen opens on rows rather than a spinner; who is typing,
/// as the live line last said; which chat is on screen, so a push about it
/// does not put a banner over the conversation it is about; and where to go
/// next, when a push or a chart asks for a chat.
@MainActor
final class ChatStore: ObservableObject {

    static let shared = ChatStore()

    /// Messages to the reader not read yet, in every chat. Drives the count
    /// on the chats button.
    @Published private(set) var unreadCount = 0

    /// The list the server last sent. Nil until the first fetch.
    @Published private(set) var chats: [ChatSummary]?

    /// A chat to open as soon as the chats screen is up: a tapped push, or
    /// "Message" on somebody's chart. The screen takes it and clears it.
    @Published var pendingRoute: ChatRoute?

    /// Bumped by every push about a message that lands while the app is open,
    /// and by the live line coming back, so the screens on show fetch at once
    /// instead of on their next tick.
    @Published private(set) var arrivals = 0

    /// The chats whose other side is typing now. The live line says when
    /// someone starts and stops; a start it never hears the end of lapses
    /// on its own (`typingLasts`), since a phone can go quiet mid-word.
    @Published private(set) var typingChats: Set<Int> = []

    /// Longer than the few seconds between two "typing" from the same phone.
    private static let typingLasts: Duration = .seconds(6)

    private var typingLapses: [Int: Task<Void, Never>] = [:]

    /// The chat on screen, if any.
    var visibleChatId: Int?

    /// Moved on by every `reset`, so a request that set out for the last
    /// account cannot leave its rows behind for the next one.
    private var generation = 0

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    #if DEBUG
    /// The harness has no account: the list is the sample one, and what is
    /// sent stays on the screen it was sent from.
    private var isOffline: Bool { WeatherPreviewHarness.isEnabled }
    #endif

    /// Asks for the unread count. Quiet on failure: a badge that misses one
    /// refresh is not worth a message over the weather.
    func refreshUnread() async {
        #if DEBUG
        if isOffline {
            setUnread((chats ?? WeatherPreviewData.chats).reduce(0) { $0 + $1.unreadCount })
            return
        }
        #endif
        guard AuthStore.shared.isSignedIn else {
            unreadCount = 0
            return
        }
        let account = generation
        do {
            let count = try await api.fetchUnreadChatCount()
            guard account == generation else { return }
            setUnread(count)
        } catch {
            if !error.isCancellation {
                NSLog("[Chats] unread count failed: \(error.localizedDescription)")
            }
        }
    }

    /// Fetches the list and keeps it for the next open.
    func fetchChats() async throws -> [ChatSummary] {
        #if DEBUG
        if isOffline {
            let sample = chats ?? WeatherPreviewData.chats
            chats = sample
            return sample
        }
        #endif
        let account = generation
        let response = try await api.fetchChats()
        // Signed out while it was out: these rows are the last account's.
        guard account == generation else { throw CancellationError() }
        chats = response.chats
        setUnread(response.unreadCount)
        return response.chats
    }

    /// What a conversation learned, folded into the kept list: its newest
    /// message and how much of it is read. A chat that was not listed yet
    /// (the first message of a new one) goes to the top.
    func update(_ summary: ChatSummary) {
        guard var list = chats else { return }
        list.removeAll { $0.chatId == summary.chatId }
        if summary.lastMessage != nil {
            list.insert(summary, at: 0)
            list.sort { ($0.lastMessage?.id ?? 0) > ($1.lastMessage?.id ?? 0) }
        }
        if list != chats { chats = list }
    }

    /// A chat that is gone from the reader's side: blocked from its screen.
    func forget(chatId: Int) {
        chats?.removeAll { $0.chatId == chatId }
        peerTyping(chatId, false)
    }

    /// The other side read the chat up to a message: the "Seen" under the
    /// reader's last one, on the kept row.
    func peerRead(chatId: Int, upTo messageId: Int) {
        guard var list = chats,
              let index = list.firstIndex(where: { $0.chatId == chatId }),
              (list[index].peerReadId ?? 0) < messageId else { return }
        list[index].peerReadId = messageId
        chats = list
    }

    /// The reader read a chat on another phone.
    func readElsewhere(chatId: Int) {
        guard var list = chats,
              let index = list.firstIndex(where: { $0.chatId == chatId }),
              list[index].unreadCount > 0 else { return }
        list[index].unreadCount = 0
        chats = list
    }

    /// The other side of a chat started or stopped typing.
    func peerTyping(_ chatId: Int, _ typing: Bool) {
        typingLapses[chatId]?.cancel()
        typingLapses[chatId] = nil
        guard typing else {
            if typingChats.contains(chatId) { typingChats.remove(chatId) }
            return
        }
        if !typingChats.contains(chatId) { typingChats.insert(chatId) }
        typingLapses[chatId] = Task { [weak self] in
            try? await Task.sleep(for: Self.typingLasts)
            guard !Task.isCancelled else { return }
            self?.typingLapses[chatId] = nil
            self?.typingChats.remove(chatId)
        }
    }

    /// The server's count after a chat was read, or the harness's own.
    func setUnread(_ count: Int) {
        unreadCount = count
        // The app icon says what the bell and this button say, added up.
        Task { await PushNotifications.shared.syncBadge() }
    }

    /// A push about a message arrived with the app open.
    func pushArrived() async {
        await catchUp()
    }

    /// The live line is up again: what came while it was down is fetched by
    /// whatever is on screen, and the badge asks too.
    func lineOpened() async {
        await catchUp()
    }

    private func catchUp() async {
        arrivals += 1
        await refreshUnread()
    }

    /// Everything here belongs to the account that was signed in.
    func reset() {
        generation += 1
        unreadCount = 0
        chats = nil
        pendingRoute = nil
        visibleChatId = nil
        typingLapses.values.forEach { $0.cancel() }
        typingLapses = [:]
        typingChats = []
    }
}

/// The times a chat prints, in the app's language rather than the device's.
@MainActor
enum ChatDate {

    /// The stamp on a row of the list: the time today, "Yesterday", the
    /// weekday within the week, and a date before that.
    static func listStamp(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return formatter("time") { $0.timeStyle = .short }.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return formatter("relativeDay") {
                $0.dateStyle = .medium
                $0.doesRelativeDateFormatting = true
            }.string(from: date)
        }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return formatter("weekday") { $0.setLocalizedDateFormatFromTemplate("EEEE") }.string(from: date)
        }
        return formatter("shortDate") { $0.dateStyle = .short }.string(from: date)
    }

    /// The line over a message that comes after a pause: "Today 14:05",
    /// "Yesterday 09:12", "12 Sep 2026 18:00".
    static func separator(_ date: Date) -> String {
        formatter("separator") {
            $0.dateStyle = .medium
            $0.timeStyle = .short
            $0.doesRelativeDateFormatting = true
        }.string(from: date)
    }

    /// Formatters are slow to make and a chat redraws often, so one is kept
    /// per style and language.
    private static var cache: [String: DateFormatter] = [:]

    private static func formatter(_ style: String, configure: (DateFormatter) -> Void) -> DateFormatter {
        let key = "\(LanguageStore.code)|\(style)"
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = LanguageStore.locale
        configure(formatter)
        cache[key] = formatter
        return formatter
    }
}
