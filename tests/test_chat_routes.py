"""Chats end to end: who can write to whom, messages and unread, blocks, the
people a chat can be started with, and the push a message sends.

The cast is the social tests': Anna and Boris own a chart each, marked as
their own, and Clara owns none. Anna also keeps a chart of her mother's,
which is nobody's own and so is no way to anyone.
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from test_social_push import RecordingSender
from test_social_routes import ANNA, BORIS, CLARA, SocialTestCase, _profile_body

from app.api.dependencies import get_repositories
from app.application.services import chat_push
from app.application.services.chat_push import PREVIEW_LENGTH, preview
from app.infrastructure.repositories.chat_repositories import ChatNotFound, FileChatRepository

ANNA_PHONE = "a" * 64


class ChatTestCase(SocialTestCase):
    def setUp(self) -> None:
        super().setUp()
        # Made without marking it primary: Anna's own chart stays hers.
        response = self.as_user(ANNA).post("/api/v1/profiles", json=_profile_body("Mum", "anna_mum", "1962-07-09"))
        self.assertEqual(response.status_code, 200, response.text)
        self.mum_profile: str = response.json()["profile"]["profile_id"]

    def open_chat(self, user_id: str, profile_id: str) -> dict[str, Any]:
        response = self.as_user(user_id).post("/api/v1/chats", json={"profile_id": profile_id})
        self.assertEqual(response.status_code, 200, response.text)
        chat: dict[str, Any] = response.json()["chat"]
        return chat

    def send(self, user_id: str, chat_id: int, body: str) -> dict[str, Any]:
        response = self.as_user(user_id).post(f"/api/v1/chats/{chat_id}/messages", json={"body": body})
        self.assertEqual(response.status_code, 200, response.text)
        message: dict[str, Any] = response.json()["message"]
        return message

    def chats(self, user_id: str) -> dict[str, Any]:
        response = self.as_user(user_id).get("/api/v1/chats")
        self.assertEqual(response.status_code, 200, response.text)
        listing: dict[str, Any] = response.json()
        return listing

    def unread(self, user_id: str) -> int:
        count: int = self.as_user(user_id).get("/api/v1/chats/unread").json()["unread_count"]
        return count


class WhoCanWriteTests(ChatTestCase):
    def test_a_persons_own_chart_opens_one_chat_whoever_starts_it(self) -> None:
        chat = self.open_chat(BORIS, self.anna_profile)
        again = self.open_chat(BORIS, self.anna_profile)
        from_anna = self.open_chat(ANNA, self.boris_profile)

        self.assertEqual(chat["peer"]["username"], "anna_p")
        self.assertIsNone(chat["last_message"])
        self.assertEqual(again["chat_id"], chat["chat_id"])
        self.assertEqual(from_anna["chat_id"], chat["chat_id"])
        self.assertEqual(from_anna["peer"]["username"], "boris_i")

    def test_a_chart_kept_for_someone_else_cannot_be_written_to(self) -> None:
        response = self.as_user(BORIS).post("/api/v1/chats", json={"profile_id": self.mum_profile})

        self.assertEqual(response.status_code, 400, response.text)

    def test_an_account_without_a_chart_of_its_own_cannot_write(self) -> None:
        response = self.as_user(CLARA).post("/api/v1/chats", json={"profile_id": self.anna_profile})

        self.assertEqual(response.status_code, 409, response.text)

    def test_your_own_chart_is_not_someone_to_write_to(self) -> None:
        response = self.as_user(ANNA).post("/api/v1/chats", json={"profile_id": self.anna_profile})

        self.assertEqual(response.status_code, 400, response.text)

    def test_a_missing_chart_is_a_404(self) -> None:
        response = self.as_user(BORIS).post("/api/v1/chats", json={"profile_id": "nobody"})

        self.assertEqual(response.status_code, 404, response.text)

    def test_charts_say_whether_they_can_be_written_to(self) -> None:
        def can_message(user_id: str, profile_id: str) -> bool:
            response = self.as_user(user_id).get(f"/api/v1/profiles/{profile_id}")
            self.assertEqual(response.status_code, 200, response.text)
            value: bool = response.json()["profile"]["can_message"]
            return value

        self.assertTrue(can_message(BORIS, self.anna_profile))
        self.assertFalse(can_message(BORIS, self.mum_profile))
        self.assertFalse(can_message(ANNA, self.anna_profile))

    def test_the_saved_list_says_it_too(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.mum_profile}/follow")

        profiles = self.as_user(BORIS).get("/api/v1/profiles").json()["profiles"]
        by_id = {profile["profile_id"]: profile for profile in profiles}

        self.assertTrue(by_id[self.anna_profile]["can_message"])
        self.assertFalse(by_id[self.mum_profile]["can_message"])
        self.assertFalse(by_id[self.boris_profile]["can_message"])


class MessageTests(ChatTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.chat_id: int = self.open_chat(BORIS, self.anna_profile)["chat_id"]

    def test_a_chat_with_nothing_in_it_lists_nowhere(self) -> None:
        self.assertEqual(self.chats(BORIS)["chats"], [])
        self.assertEqual(self.chats(ANNA)["chats"], [])

    def test_messages_arrive_in_order_and_count_as_unread(self) -> None:
        self.send(BORIS, self.chat_id, "Hi")
        self.send(BORIS, self.chat_id, "  How are you?  ")

        annas = self.chats(ANNA)
        boris = self.chats(BORIS)
        messages = self.as_user(ANNA).get(f"/api/v1/chats/{self.chat_id}/messages").json()

        self.assertEqual(len(annas["chats"]), 1)
        self.assertEqual(annas["chats"][0]["peer"]["username"], "boris_i")
        self.assertEqual(annas["chats"][0]["last_message"]["body"], "How are you?")
        self.assertFalse(annas["chats"][0]["last_message"]["is_mine"])
        self.assertEqual(annas["chats"][0]["unread_count"], 2)
        self.assertEqual(annas["unread_count"], 2)
        self.assertEqual(self.unread(ANNA), 2)
        self.assertTrue(boris["chats"][0]["last_message"]["is_mine"])
        self.assertEqual(boris["unread_count"], 0)
        self.assertEqual([m["body"] for m in messages["messages"]], ["Hi", "How are you?"])
        self.assertFalse(messages["has_more"])

    def test_reading_clears_unread_and_shows_as_read_to_the_sender(self) -> None:
        first = self.send(BORIS, self.chat_id, "Hi")
        second = self.send(BORIS, self.chat_id, "Still there?")

        partly = self.as_user(ANNA).post(f"/api/v1/chats/{self.chat_id}/read", json={"message_id": first["id"]})
        before = self.as_user(BORIS).get(f"/api/v1/chats/{self.chat_id}/messages").json()["chat"]
        fully = self.as_user(ANNA).post(f"/api/v1/chats/{self.chat_id}/read")
        backwards = self.as_user(ANNA).post(f"/api/v1/chats/{self.chat_id}/read", json={"message_id": first["id"]})
        after = self.as_user(BORIS).get(f"/api/v1/chats/{self.chat_id}/messages").json()["chat"]

        self.assertEqual(partly.json()["unread_count"], 1)
        self.assertEqual(before["peer_read_id"], first["id"])
        self.assertEqual(fully.json()["unread_count"], 0)
        self.assertEqual(backwards.json()["unread_count"], 0)
        self.assertEqual(after["peer_read_id"], second["id"])

    def test_answering_reads_what_is_answered(self) -> None:
        self.send(BORIS, self.chat_id, "Hi")
        self.send(ANNA, self.chat_id, "Hello!")

        self.assertEqual(self.unread(ANNA), 0)
        self.assertEqual(self.unread(BORIS), 1)

    def test_catching_up_brings_only_what_came_after(self) -> None:
        first = self.send(BORIS, self.chat_id, "One")
        self.send(ANNA, self.chat_id, "Two")
        self.send(BORIS, self.chat_id, "Three")

        newer = self.as_user(ANNA).get(f"/api/v1/chats/{self.chat_id}/messages", params={"after": first["id"]}).json()

        self.assertEqual([m["body"] for m in newer["messages"]], ["Two", "Three"])
        self.assertEqual([m["is_mine"] for m in newer["messages"]], [True, False])
        self.assertFalse(newer["has_more"])

    def test_older_messages_come_a_page_at_a_time(self) -> None:
        for number in range(53):
            self.send(BORIS if number % 2 else ANNA, self.chat_id, f"Message {number}")

        page = self.as_user(ANNA).get(f"/api/v1/chats/{self.chat_id}/messages").json()
        oldest = page["messages"][0]["id"]
        earlier = self.as_user(ANNA).get(f"/api/v1/chats/{self.chat_id}/messages", params={"before": oldest}).json()

        self.assertEqual(len(page["messages"]), 50)
        self.assertTrue(page["has_more"])
        self.assertEqual(page["messages"][-1]["body"], "Message 52")
        self.assertEqual([m["body"] for m in earlier["messages"]], ["Message 0", "Message 1", "Message 2"])
        self.assertFalse(earlier["has_more"])

    def test_the_latest_chat_is_first(self) -> None:
        clara_profile = self._create_profile(CLARA, "Clara Weiss", "clara_w", "1995-01-15")
        with_clara = self.open_chat(ANNA, clara_profile)["chat_id"]
        self.send(ANNA, with_clara, "Hi Clara")
        self.send(BORIS, self.chat_id, "Hi Anna")

        order = [chat["peer"]["username"] for chat in self.chats(ANNA)["chats"]]

        self.assertEqual(order, ["boris_i", "clara_w"])

    def test_nobody_else_can_read_or_write(self) -> None:
        self.send(BORIS, self.chat_id, "Just between us")
        client = self.as_user(CLARA)

        self.assertEqual(client.get(f"/api/v1/chats/{self.chat_id}/messages").status_code, 404)
        self.assertEqual(client.post(f"/api/v1/chats/{self.chat_id}/messages", json={"body": "Hi"}).status_code, 404)
        self.assertEqual(client.post(f"/api/v1/chats/{self.chat_id}/read").status_code, 404)

    def test_an_empty_or_endless_message_is_refused(self) -> None:
        client = self.as_user(BORIS)

        blank = client.post(f"/api/v1/chats/{self.chat_id}/messages", json={"body": "   \n "})
        endless = client.post(f"/api/v1/chats/{self.chat_id}/messages", json={"body": "a" * 2001})

        self.assertEqual(blank.status_code, 422)
        self.assertEqual(endless.status_code, 422)
        self.assertEqual(self.chats(ANNA)["chats"], [])

    def test_nobody_can_write_to_someone_who_no_longer_has_a_chart(self) -> None:
        self.send(BORIS, self.chat_id, "Hi")
        self.as_user(ANNA).delete(f"/api/v1/profiles/{self.anna_profile}")

        response = self.as_user(BORIS).post(f"/api/v1/chats/{self.chat_id}/messages", json={"body": "Hello?"})

        self.assertEqual(response.status_code, 400, response.text)


class BlockTests(ChatTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.chat_id: int = self.open_chat(BORIS, self.anna_profile)["chat_id"]
        self.send(BORIS, self.chat_id, "Hi")

    def test_a_block_hides_the_chat_on_both_sides_and_stops_it(self) -> None:
        self.as_user(ANNA).post("/api/v1/blocks", json={"profile_id": self.boris_profile})

        blocker = self.as_user(ANNA).post(f"/api/v1/chats/{self.chat_id}/messages", json={"body": "Go away"})
        blocked = self.as_user(BORIS).post(f"/api/v1/chats/{self.chat_id}/messages", json={"body": "Why?"})
        reading = self.as_user(BORIS).get(f"/api/v1/chats/{self.chat_id}/messages")
        reopening = self.as_user(BORIS).post("/api/v1/chats", json={"profile_id": self.anna_profile})

        self.assertEqual(self.chats(ANNA)["chats"], [])
        self.assertEqual(self.chats(BORIS)["chats"], [])
        self.assertEqual(self.unread(ANNA), 0)
        self.assertEqual(blocker.status_code, 403)
        self.assertEqual(blocked.status_code, 404)
        self.assertEqual(reading.status_code, 404)
        self.assertEqual(reopening.status_code, 404)

    def test_unblocking_brings_the_chat_back_as_it_was(self) -> None:
        self.as_user(ANNA).post("/api/v1/blocks", json={"profile_id": self.boris_profile})
        block_id = self.as_user(ANNA).get("/api/v1/blocks").json()["blocks"][0]["block_id"]
        self.as_user(ANNA).delete(f"/api/v1/blocks/{block_id}")

        listing = self.chats(ANNA)

        self.assertEqual([chat["last_message"]["body"] for chat in listing["chats"]], ["Hi"])
        self.assertEqual(listing["unread_count"], 1)

    def test_deleting_an_account_takes_its_chats(self) -> None:
        response = self.as_user(BORIS).delete("/api/v1/auth/account")

        self.assertEqual(response.status_code, 204, response.text)
        self.assertEqual(self.chats(ANNA)["chats"], [])
        self.assertEqual(self.unread(ANNA), 0)


class ContactTests(ChatTestCase):
    def contacts(self, user_id: str) -> list[str]:
        people = self.as_user(user_id).get("/api/v1/chats/contacts").json()["people"]
        return [person["username"] for person in people]

    def test_the_people_on_either_side_of_a_follow(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")

        self.assertEqual(self.contacts(BORIS), ["anna_p"])
        self.assertEqual(self.contacts(ANNA), ["boris_i"])

    def test_a_person_is_shown_as_their_own_chart(self) -> None:
        # Mum was touched last, and still Anna is drawn as herself.
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")
        self.as_user(ANNA).post(f"/api/v1/profiles/{self.mum_profile}/like")

        people = self.as_user(BORIS).get("/api/v1/chats/contacts").json()["people"]

        self.assertEqual([person["profile_id"] for person in people], [self.anna_profile])

    def test_following_a_chart_kept_for_someone_else_finds_nobody(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.mum_profile}/follow")

        self.assertEqual(self.contacts(BORIS), [])

    def test_followers_without_a_chart_of_their_own_are_left_out(self) -> None:
        self.as_user(CLARA).post(f"/api/v1/profiles/{self.anna_profile}/follow")

        self.assertEqual(self.contacts(ANNA), [])

    def test_nobody_across_a_block(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")
        self.as_user(ANNA).post("/api/v1/blocks", json={"profile_id": self.boris_profile})

        self.assertEqual(self.contacts(ANNA), [])
        self.assertEqual(self.contacts(BORIS), [])


class MessagePushTests(ChatTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.sender = RecordingSender()
        patcher = patch.object(chat_push, "get_sender", lambda: self.sender)
        patcher.start()
        self.addCleanup(patcher.stop)
        response = self.as_user(ANNA).post(
            "/api/v1/devices",
            json={"token": ANNA_PHONE, "environment": "production", "lang": "en"},
        )
        self.assertEqual(response.status_code, 200, response.text)
        self.chat_id: int = self.open_chat(BORIS, self.anna_profile)["chat_id"]

    def test_a_message_is_pushed_with_the_senders_name(self) -> None:
        self.send(BORIS, self.chat_id, "Are you free tonight?")

        self.assertEqual(len(self.sender.sent), 1)
        sent = self.sender.sent[0]
        self.assertEqual(sent["token"], ANNA_PHONE)
        self.assertEqual(sent["payload"]["aps"]["alert"], {"title": "Boris Ivanov", "body": "Are you free tonight?"})
        self.assertEqual(sent["payload"]["aps"]["thread-id"], f"chat-{self.chat_id}")
        self.assertEqual(sent["payload"]["aps"]["badge"], 1)
        self.assertEqual(sent["payload"]["kind"], "message")
        self.assertEqual(sent["payload"]["chat_id"], self.chat_id)

    def test_the_badge_counts_activity_and_messages_together(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like", json={"feels_like": "Flowing"})
        self.send(BORIS, self.chat_id, "Hi")
        self.send(BORIS, self.chat_id, "Liked your sky")

        self.assertEqual([item["payload"]["aps"]["badge"] for item in self.sender.sent], [2, 3])

    def test_your_own_messages_do_not_ring_your_phone(self) -> None:
        self.send(ANNA, self.chat_id, "Hi Boris")

        self.assertEqual(self.sender.sent, [])

    def test_switched_off_messages_stay_quiet(self) -> None:
        settings = self.as_user(ANNA).put("/api/v1/social/settings", json={"push_messages": False}).json()

        self.send(BORIS, self.chat_id, "Hi")

        self.assertFalse(settings["push_messages"])
        self.assertTrue(settings["push_likes"])
        self.assertEqual(self.sender.sent, [])

    def test_a_token_apns_no_longer_takes_is_forgotten(self) -> None:
        self.sender.gone = {ANNA_PHONE}

        self.send(BORIS, self.chat_id, "Hi")

        repos = get_repositories()
        assert repos.social is not None
        self.assertEqual(repos.social.devices_for(ANNA), [])

    def test_a_long_message_is_cut_for_the_banner(self) -> None:
        text = "word " * 100

        cut = preview(text)

        self.assertEqual(len(cut), PREVIEW_LENGTH)
        self.assertTrue(cut.endswith("…"))
        self.assertEqual(preview("  short  "), "short")


class FakeProfiles:
    """What the file chats read of the file profiles: who follows what, and
    whose each chart is."""

    def __init__(self, owners: dict[str, str], follows: dict[str, list[str]]):
        self.owners = owners
        self.follows = follows

    def list_followed(self, user_id: str) -> list[dict[str, Any]]:
        return [{"profile_id": profile_id} for profile_id in self.follows.get(user_id, [])]

    def get_owner_user_id(self, profile_id: str) -> str | None:
        return self.owners.get(profile_id)


class FakeSocial:
    """The file social layer's cards (an account's first chart) and blocks."""

    def __init__(self, first_charts: dict[str, str]):
        self.first_charts = first_charts
        self.blocked: dict[str, set[str]] = {}

    def card_for(self, user_id: str) -> dict[str, Any]:
        profile_id = self.first_charts.get(user_id)
        return {"profile_id": profile_id, "profile_name": user_id.title() if profile_id else None, "username": None}

    def blocked_user_ids(self, user_id: str) -> set[str]:
        return self.blocked.get(user_id, set())


class FileChatRepositoryTests(unittest.TestCase):
    """Local development's chats, which keep everything in one JSON file."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.social = FakeSocial({"anna": "anna-chart", "boris": "boris-chart"})
        profiles = FakeProfiles(
            owners={"anna-chart": "anna", "mum-chart": "anna", "boris-chart": "boris"},
            follows={"boris": ["anna-chart", "mum-chart"]},
        )
        self.repo = FileChatRepository(profiles, self.social, Path(self.temp_dir.name) / "_chats.json")  # type: ignore[arg-type]

    def test_a_conversation_round_trip(self) -> None:
        chat = self.repo.open_chat("boris", "anna")
        first = self.repo.send_message("boris", chat["chat_id"], "Hi")
        self.repo.send_message("boris", chat["chat_id"], "Hello?")

        self.assertEqual(self.repo.open_chat("anna", "boris")["chat_id"], chat["chat_id"])
        self.assertEqual(self.repo.unread_count("anna"), 2)
        self.assertEqual(self.repo.mark_read("anna", chat["chat_id"], first["id"]), 1)
        listing = self.repo.list_chats("anna")
        self.assertEqual(listing["chats"][0]["last_message"]["body"], "Hello?")
        self.assertEqual(listing["chats"][0]["unread_count"], 1)
        page = self.repo.list_messages("anna", chat["chat_id"], after=first["id"])
        self.assertEqual([m["body"] for m in page["messages"]], ["Hello?"])
        with self.assertRaises(ChatNotFound):
            self.repo.list_messages("clara", chat["chat_id"])

    def test_contacts_are_the_owners_of_followed_charts_that_are_their_own(self) -> None:
        self.assertEqual([card["profile_id"] for card in self.repo.contacts("boris")], ["anna-chart"])
        self.assertEqual(self.repo.primary_profile_of("anna"), "anna-chart")
        self.assertIsNone(self.repo.primary_profile_of("clara"))

    def test_a_block_hides_the_chat(self) -> None:
        chat = self.repo.open_chat("boris", "anna")
        self.repo.send_message("boris", chat["chat_id"], "Hi")
        self.social.blocked["anna"] = {"boris"}

        self.assertEqual(self.repo.list_chats("anna")["chats"], [])
        self.assertEqual(self.repo.unread_count("anna"), 0)


if __name__ == "__main__":
    unittest.main()
