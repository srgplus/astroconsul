"""The chats' live line: a message on the other side's screen as it is sent,
"Seen" as it is read, and the dots while someone types.

The cast is the chat tests': Anna and Boris follow each other and so may
write to each other; Clara is in no chat with them. Each test opens the
sockets it listens on, as the account it names, and reads what arrives in
order. Something that must not arrive is shown by what arrives next, and
every read gives up after a few seconds rather than hang the suite.
"""

from __future__ import annotations

import json
import time
import unittest
from typing import Any

import anyio
from starlette.testclient import WebSocketTestSession
from test_chat_routes import ChatTestCase
from test_social_routes import ANNA, BORIS, CLARA

from app.application.services import chat_live
from app.application.services.chat_live import ChatHub, LiveConnection, should_pass_typing

LIVE = "/api/v1/chats/live"

# How long a test waits for an event, or for a socket to have read what it
# was sent, before calling it lost.
PATIENCE = 5.0


class LiveTestCase(ChatTestCase):
    def setUp(self) -> None:
        super().setUp()
        chat_live.hub.clear()
        self.addCleanup(chat_live.hub.clear)
        self.chat_id: int = self.open_chat(BORIS, self.anna_profile)["chat_id"]

    def connect(self, user_id: str) -> WebSocketTestSession:
        """A socket signed in as the account, past its "ready"."""
        socket = self.as_user(user_id).websocket_connect(LIVE)
        socket.__enter__()
        self.addCleanup(socket.__exit__, None, None, None)
        self.assertEqual(self.next_event(socket), {"type": "ready"})
        return socket

    def settle(self, user_id: str, chat_id: int | None = None) -> None:
        """Waits until the account's sockets have looked up who is on the
        other side of the chat: whatever their "typing" led to has been
        published by then."""
        chat_id = chat_id or self.chat_id
        deadline = time.monotonic() + PATIENCE
        while time.monotonic() < deadline:
            connections = chat_live.hub._connections.get(user_id, set())
            if connections and all(chat_id in connection.peers for connection in connections):
                return
            time.sleep(0.01)
        self.fail(f"{user_id}'s socket never read its typing in chat {chat_id}")

    def typing(self, socket: WebSocketTestSession, typing: bool = True, chat_id: int | None = None) -> None:
        socket.send_json({"type": "typing", "chat_id": chat_id or self.chat_id, "typing": typing})

    def next_event(self, socket: WebSocketTestSession) -> dict[str, Any]:
        async def receive() -> dict[str, Any]:
            with anyio.fail_after(PATIENCE):
                message: dict[str, Any] = await socket._send_rx.receive()
                return message

        message = socket.portal.call(receive)
        self.assertEqual(message["type"], "websocket.send", message)
        event: dict[str, Any] = json.loads(message["text"])
        return event


class MessageEventTests(LiveTestCase):
    def test_a_message_reaches_the_recipient_as_theirs_to_read(self) -> None:
        anna = self.connect(ANNA)

        sent = self.send(BORIS, self.chat_id, "Hello")
        event = self.next_event(anna)

        self.assertEqual(event["type"], "message")
        self.assertEqual(event["chat_id"], self.chat_id)
        self.assertEqual(event["message"]["id"], sent["id"])
        self.assertEqual(event["message"]["body"], "Hello")
        self.assertFalse(event["message"]["is_mine"])
        # The row as Anna's list draws it, and her badge.
        self.assertEqual(event["chat"]["peer"]["username"], "boris_i")
        self.assertEqual(event["chat"]["unread_count"], 1)
        self.assertEqual(event["unread_count"], 1)

    def test_the_senders_other_phones_hear_it_as_their_own(self) -> None:
        boris = self.connect(BORIS)

        self.send(BORIS, self.chat_id, "Hello")
        event = self.next_event(boris)

        self.assertEqual(event["type"], "message")
        self.assertTrue(event["message"]["is_mine"])
        self.assertEqual(event["chat"]["unread_count"], 0)
        self.assertEqual(event["chat"]["peer"]["username"], "anna_p")

    def test_writing_back_reads_what_was_answered(self) -> None:
        # Answering reads the chat: the "Seen" under Boris's message comes
        # with Anna's answer, in the row it carries.
        first = self.send(BORIS, self.chat_id, "Hello")
        boris = self.connect(BORIS)

        self.send(ANNA, self.chat_id, "Hi")
        event = self.next_event(boris)

        self.assertEqual(event["message"]["body"], "Hi")
        self.assertGreaterEqual(event["chat"]["peer_read_id"], first["id"])

    def test_nobody_else_hears_it(self) -> None:
        clara = self.connect(CLARA)
        anna = self.connect(ANNA)

        self.send(BORIS, self.chat_id, "Hello")
        self.assertEqual(self.next_event(anna)["type"], "message")

        # What Clara hears next is the probe, not Boris's message.
        chat_live.hub.publish(CLARA, {"type": "probe"})
        self.assertEqual(self.next_event(clara), {"type": "probe"})


class ReadEventTests(LiveTestCase):
    def test_reading_puts_seen_under_the_senders_message(self) -> None:
        sent = self.send(BORIS, self.chat_id, "Hello")
        boris = self.connect(BORIS)

        response = self.as_user(ANNA).post(f"/api/v1/chats/{self.chat_id}/read", json={"message_id": sent["id"]})
        self.assertEqual(response.status_code, 200, response.text)
        event = self.next_event(boris)

        self.assertEqual(event, {"type": "read", "chat_id": self.chat_id, "peer_read_id": sent["id"]})

    def test_the_readers_other_phones_clear_their_badge(self) -> None:
        self.send(BORIS, self.chat_id, "Hello")
        anna = self.connect(ANNA)

        self.as_user(ANNA).post(f"/api/v1/chats/{self.chat_id}/read")
        event = self.next_event(anna)

        self.assertEqual(event, {"type": "unread", "chat_id": self.chat_id, "unread_count": 0})


class TypingTests(LiveTestCase):
    def test_typing_shows_on_the_other_side_and_stops(self) -> None:
        anna = self.connect(ANNA)
        boris = self.connect(BORIS)

        self.typing(boris)
        self.assertEqual(self.next_event(anna), {"type": "typing", "chat_id": self.chat_id, "typing": True})

        self.typing(boris, False)
        self.assertEqual(self.next_event(anna), {"type": "typing", "chat_id": self.chat_id, "typing": False})

    def test_typing_on_and_on_is_passed_on_once_in_a_while(self) -> None:
        anna = self.connect(ANNA)
        boris = self.connect(BORIS)

        self.typing(boris)
        self.typing(boris)
        self.typing(boris)
        self.typing(boris, False)
        self.send(BORIS, self.chat_id, "Hello")

        self.assertEqual(self.next_event(anna)["typing"], True)
        self.assertEqual(self.next_event(anna)["typing"], False)
        self.assertEqual(self.next_event(anna)["type"], "message")

    def test_a_stranger_cannot_type_into_a_chat(self) -> None:
        anna = self.connect(ANNA)
        clara = self.connect(CLARA)

        self.typing(clara)
        self.settle(CLARA)
        self.send(BORIS, self.chat_id, "Hello")

        self.assertEqual(self.next_event(anna)["type"], "message")

    def test_nobody_types_across_a_block(self) -> None:
        anna = self.connect(ANNA)
        boris = self.connect(BORIS)
        self.as_user(ANNA).post("/api/v1/blocks", json={"profile_id": self.boris_profile})

        self.typing(boris)
        self.settle(BORIS)
        chat_live.hub.publish(ANNA, {"type": "probe"})

        self.assertEqual(self.next_event(anna), {"type": "probe"})

    def test_what_the_line_does_not_understand_is_ignored(self) -> None:
        anna = self.connect(ANNA)
        boris = self.connect(BORIS)

        boris.send_text("not json")
        boris.send_json(["typing"])
        boris.send_json({"type": "wave", "chat_id": self.chat_id})
        boris.send_json({"type": "typing", "chat_id": "12"})
        boris.send_bytes(b"\x00")
        self.typing(boris)

        self.assertEqual(self.next_event(anna)["type"], "typing")


class HubTests(unittest.TestCase):
    def test_publishing_to_nobody_reaches_nobody(self) -> None:
        self.assertEqual(ChatHub().publish("user_nobody", {"type": "ready"}), 0)

    def test_a_start_is_passed_on_at_most_every_interval_and_a_stop_only_after_a_start(self) -> None:
        connection = LiveConnection.__new__(LiveConnection)
        connection.typing_sent = {}

        self.assertFalse(should_pass_typing(connection, 1, False))
        self.assertTrue(should_pass_typing(connection, 1, True))
        self.assertFalse(should_pass_typing(connection, 1, True))
        self.assertTrue(should_pass_typing(connection, 2, True))
        self.assertTrue(should_pass_typing(connection, 1, False))
        self.assertFalse(should_pass_typing(connection, 1, False))
        self.assertTrue(should_pass_typing(connection, 1, True))


if __name__ == "__main__":
    unittest.main()
