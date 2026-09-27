import Foundation

// The chats half of the API. Mirrors `app/api/v1/routes/chats.py`; the
// decoder converts snake case, so `peer_read_id` arrives as `peerReadId`.

/// One message: text only, as written.
struct ChatMessage: Codable, Hashable, Identifiable {
    let id: Int
    let body: String
    let isMine: Bool
    let createdAt: String

    var date: Date? { SocialDate.parse(createdAt) }
}

/// One conversation as the list draws it: the person on the other side, as
/// their own chart, the last message, and how far each side has read.
struct ChatSummary: Codable, Hashable, Identifiable {
    let chatId: Int
    let peer: SocialCard
    let lastMessage: ChatMessage?
    var unreadCount: Int
    /// The last of the reader's messages the other side has read, for the
    /// "Read" under the reader's last one.
    let peerReadId: Int?
    let updatedAt: String

    var id: Int { chatId }
    var date: Date? { SocialDate.parse(updatedAt) }
}

/// `GET /api/v1/chats`.
struct ChatListResponse: Codable {
    let chats: [ChatSummary]
    let unreadCount: Int
}

/// `POST /api/v1/chats`: the chat with the owner of a chart, made on first
/// asking.
struct ChatResponse: Codable {
    let chat: ChatSummary
}

/// `GET /api/v1/chats/{id}/messages`, oldest first. `hasMore` is whether
/// there is more in the direction read: older history for a page, newer
/// messages for a catch-up.
struct ChatMessagesResponse: Codable {
    let chat: ChatSummary
    let messages: [ChatMessage]
    let hasMore: Bool
}

/// `POST /api/v1/chats/{id}/messages`.
struct SentMessageResponse: Codable {
    let message: ChatMessage
}

/// `POST /api/v1/chats/{id}/read` and `GET /api/v1/chats/unread`: what is
/// left unread across every chat.
struct ChatUnreadResponse: Codable {
    let unreadCount: Int
}

/// `GET /api/v1/chats/contacts`: who a new chat can be started with.
struct ChatContactsResponse: Codable {
    let people: [SocialCard]
}

/// How a conversation screen is reached, and so what it knows before it has
/// asked the server anything.
enum ChatRoute: Hashable {
    /// A row of the list: everything but the messages.
    case chat(ChatSummary)
    /// "Message" on a chart, or a person picked for a new chat: the chat is
    /// found, or made, from the chart.
    case profile(ProfileSummary)
    /// A tapped push: only the number.
    case chatId(Int)
}
