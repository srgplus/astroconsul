"""The chats' live line: what one side does, on the other side's screen as
it happens.

A phone with the app open keeps one WebSocket to `/api/v1/chats/live`
(`routes/chats.py`). Down it the server says:

* `ready`: the line is up. Whatever happened while it was down is fetched
  once, by the app, the ordinary way;
* `message`: a new message in one of the account's chats, with the chat's
  row as the account sees it (unread, how far the other side has read) and
  the unread count across every chat, for the badge. The sender's other
  phones hear it too, as their own;
* `read`: the other side has read the chat up to a message, which is the
  "Seen" under the last one you sent;
* `typing`: the other side is typing, or has stopped;
* `unread`: the account's unread count moved because it read a chat on
  another phone.

Up it the server hears one thing, `typing` from this phone, and passes it to
the other side of the chat once the phone is known to be in it, the two are
not across a block, and it has not said so in the last couple of seconds.

The hub is a dict in memory. That holds because one uvicorn process serves
the app (`start.sh`): a second process or replica would need a relay between
them (Postgres LISTEN/NOTIFY is the natural one), and until then a phone on
one would hear nothing that happened on the other. The app would not break,
only fall back on polling.

Nothing here is kept and nothing is retried. The messages are in the
database; an event that does not arrive is caught up by the next fetch.
Publishing never raises into the request that caused it.
"""

from __future__ import annotations

import asyncio
import logging
import threading
import time
from typing import Any

from app.infrastructure.repositories.factory import RepositoryBundle

logger = logging.getLogger(__name__)

# Events a phone can fall behind by before the newest are dropped. A phone
# that slow is on a dead line, which the socket's own pings will close.
QUEUE_LIMIT = 200

# How often "typing" is passed on while someone goes on typing. The app says
# it every few seconds; the other side's dots last longer than this.
TYPING_INTERVAL = 2.0

# How long a connection trusts what it learned about a chat (who is on the
# other side, and that no block stands between them) before asking again.
PEER_TTL = 60.0


class LiveConnection:
    """One open socket: the account it belongs to, the loop it lives on, and
    the events waiting to go down it."""

    def __init__(self, user_id: str, loop: asyncio.AbstractEventLoop):
        self.user_id = user_id
        self.loop = loop
        self.queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=QUEUE_LIMIT)
        # chat id -> (the other side, or None when it may not be told
        # anything, and when that was learned)
        self.peers: dict[int, tuple[str | None, float]] = {}
        # chat id -> when "typing" was last passed on from here
        self.typing_sent: dict[int, float] = {}

    def offer(self, event: dict[str, Any]) -> None:
        """Queues an event. Runs on the connection's loop."""
        try:
            self.queue.put_nowait(event)
        except asyncio.QueueFull:
            logger.warning("Live chat queue full for %s, dropping a %s event", self.user_id, event.get("type"))


class ChatHub:
    """Who is connected, and a way to reach them from any thread: the chat
    routes are plain functions and run in the threadpool, the sockets on the
    event loop."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._connections: dict[str, set[LiveConnection]] = {}

    def register(self, user_id: str) -> LiveConnection:
        """A socket that has just opened. Called on the event loop."""
        connection = LiveConnection(user_id, asyncio.get_running_loop())
        with self._lock:
            self._connections.setdefault(user_id, set()).add(connection)
        return connection

    def unregister(self, connection: LiveConnection) -> None:
        with self._lock:
            connections = self._connections.get(connection.user_id)
            if connections is None:
                return
            connections.discard(connection)
            if not connections:
                del self._connections[connection.user_id]

    def is_connected(self, user_id: str) -> bool:
        with self._lock:
            return bool(self._connections.get(user_id))

    def publish(self, user_id: str, event: dict[str, Any], *, skip: LiveConnection | None = None) -> int:
        """Sends an event to every socket the account has open, less `skip`.
        Answers how many it went to."""
        with self._lock:
            targets = [c for c in self._connections.get(user_id, ()) if c is not skip]
        for connection in targets:
            try:
                connection.loop.call_soon_threadsafe(connection.offer, event)
            except RuntimeError:
                # The loop closed under a socket that had not unregistered
                # yet: the process is going down.
                logger.warning("Live chat event for %s lost: its loop is closed", user_id)
        return len(targets)

    def clear(self) -> None:
        """Forgets every connection. For tests."""
        with self._lock:
            self._connections.clear()


hub = ChatHub()


def announce_message(
    repos: RepositoryBundle,
    sender_id: str,
    recipient_id: str,
    chat_id: int,
    message: dict[str, Any],
) -> None:
    """A message has been stored: on the recipient's screens at once, and on
    the sender's other phones. Each side hears it as its own row sees it.
    Runs after the response, before the push; never raises."""
    try:
        for user_id, is_mine in ((recipient_id, False), (sender_id, True)):
            if not hub.is_connected(user_id):
                continue
            hub.publish(
                user_id,
                {
                    "type": "message",
                    "chat_id": chat_id,
                    "message": {**message, "is_mine": is_mine},
                    **_row(repos, user_id, chat_id),
                },
            )
    except Exception:
        logger.exception("Live message event for chat %s failed", chat_id)


def announce_read(repos: RepositoryBundle, reader_id: str, chat_id: int, unread_count: int) -> None:
    """The reader has read a chat: the "Seen" on the other side, and the
    count on the reader's other phones. Never raises."""
    try:
        chats = repos.chats
        if chats is None:
            return
        peer = chats.peer_of(reader_id, chat_id)
        if hub.is_connected(peer):
            hub.publish(
                peer,
                {"type": "read", "chat_id": chat_id, "peer_read_id": chats.read_marker(reader_id, chat_id)},
            )
        hub.publish(reader_id, {"type": "unread", "chat_id": chat_id, "unread_count": unread_count})
    except Exception:
        logger.exception("Live read event for chat %s failed", chat_id)


def _row(repos: RepositoryBundle, user_id: str, chat_id: int) -> dict[str, Any]:
    """The chat's row as this account sees it, and its unread in all."""
    chats = repos.chats
    if chats is None:
        return {}
    return {"chat": chats.chat_summary(user_id, chat_id), "unread_count": chats.unread_count(user_id)}


def typing_peer(repos: RepositoryBundle, user_id: str, chat_id: int) -> str | None:
    """Who is told that this account is typing in a chat: the other side,
    while the account is in the chat and neither has blocked the other.
    None otherwise. Reads the database; the socket runs it in the
    threadpool and keeps the answer for a while (`PEER_TTL`)."""
    chats, social = repos.chats, repos.social
    if chats is None or social is None:
        return None
    try:
        peer = chats.peer_of(user_id, chat_id)
    except LookupError:
        return None
    if social.blocker_of(user_id, peer) is not None:
        return None
    return peer


def should_pass_typing(connection: LiveConnection, chat_id: int, typing: bool) -> bool:
    """Whether a "typing" from this socket is worth passing on: a start at
    most every `TYPING_INTERVAL`, a stop only after a start."""
    now = time.monotonic()
    last = connection.typing_sent.get(chat_id)
    if typing:
        if last is not None and now - last < TYPING_INTERVAL:
            return False
        connection.typing_sent[chat_id] = now
        return True
    if last is None:
        return False
    del connection.typing_sent[chat_id]
    return True
