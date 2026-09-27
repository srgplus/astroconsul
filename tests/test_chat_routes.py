"""Chats end to end: who can write to whom, messages and unread, blocks, the
people a chat can be started with, the word filter, the anti-spam limits,
reports from a chat, and the push a message sends.

The cast is the social tests': Anna and Boris own a chart each, marked as
their own, and follow each other. What lets one write to the other is being
followed by them; whoever has been written to may always answer. Clara owns
none. Anna also keeps a chart of her mother's, which is nobody's own and so
is no way to anyone.
"""

from __future__ import annotations

import os
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from unittest.mock import patch

from test_social_push import RecordingSender
from test_social_routes import ANNA, BORIS, CLARA, SocialTestCase, _profile_body

from app.api.dependencies import get_repositories
from app.api.v1.routes import social as social_routes
from app.application.services import chat_push
from app.application.services.chat_push import PREVIEW_LENGTH, preview
from app.application.services.email_service import report_email
from app.domain.chat_rules import MESSAGES_PER_DAY, MESSAGES_PER_MINUTE, NEW_CHATS_PER_DAY
from app.infrastructure.persistence.models import ChatMessageModel, ChatModel
from app.infrastructure.persistence.session import get_session_factory
from app.infrastructure.repositories.chat_repositories import ChatNotFound, FileChatRepository, ordered_pair
from app.infrastructure.repositories.sqlalchemy_repositories import ensure_user

ANNA_PHONE = "a" * 64

NOT_FOLLOWING = "You can write to someone once they follow you."


class ChatTestCase(SocialTestCase):
    def setUp(self) -> None:
        super().setUp()
        # Made without marking it primary: Anna's own chart stays hers.
        response = self.as_user(ANNA).post("/api/v1/profiles", json=_profile_body("Mum", "anna_mum", "1962-07-09"))
        self.assertEqual(response.status_code, 200, response.text)
        self.mum_profile: str = response.json()["profile"]["profile_id"]
        self.follow(BORIS, self.anna_profile)
        self.follow(ANNA, self.boris_profile)

    def follow(self, user_id: str, profile_id: str) -> None:
        response = self.as_user(user_id).post(f"/api/v1/profiles/{profile_id}/follow")
        self.assertLess(response.status_code, 300, response.text)

    def unfollow(self, user_id: str, profile_id: str) -> None:
        response = self.as_user(user_id).delete(f"/api/v1/profiles/{profile_id}/follow")
        self.assertLess(response.status_code, 300, response.text)

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


class FollowRuleTests(ChatTestCase):
    """The owner's rule: you may write to someone who follows at least one
    of your charts, and whoever has been written to may always answer."""

    def can_message(self, user_id: str, profile_id: str) -> bool:
        response = self.as_user(user_id).get(f"/api/v1/profiles/{profile_id}")
        self.assertEqual(response.status_code, 200, response.text)
        value: bool = response.json()["profile"]["can_message"]
        return value

    def test_you_may_write_to_someone_who_follows_you(self) -> None:
        # Boris stops following Anna; Anna still follows Boris. So Boris may
        # write to Anna, and Anna may not write first to Boris.
        self.unfollow(BORIS, self.anna_profile)

        allowed = self.as_user(BORIS).post("/api/v1/chats", json={"profile_id": self.anna_profile})
        refused = self.as_user(ANNA).post("/api/v1/chats", json={"profile_id": self.boris_profile})

        self.assertEqual(allowed.status_code, 200, allowed.text)
        self.assertEqual(refused.status_code, 403, refused.text)
        self.assertEqual(refused.json()["detail"], NOT_FOLLOWING)
        self.assertTrue(self.can_message(BORIS, self.anna_profile))
        self.assertFalse(self.can_message(ANNA, self.boris_profile))

    def test_a_follow_back_is_welcome_but_not_needed(self) -> None:
        self.unfollow(ANNA, self.boris_profile)

        chat = self.open_chat(ANNA, self.boris_profile)

        self.assertEqual(chat["peer"]["profile_id"], self.boris_profile)

    def test_strangers_cannot_write(self) -> None:
        self.unfollow(ANNA, self.boris_profile)
        self.unfollow(BORIS, self.anna_profile)

        response = self.as_user(BORIS).post("/api/v1/chats", json={"profile_id": self.anna_profile})

        self.assertEqual(response.status_code, 403, response.text)
        self.assertFalse(self.can_message(BORIS, self.anna_profile))

    def test_a_follow_on_any_chart_of_the_account_counts(self) -> None:
        # Boris follows Anna's mother's chart, not Anna's own: it is still
        # Anna he follows, so Anna may write to him.
        self.unfollow(BORIS, self.anna_profile)
        self.follow(BORIS, self.mum_profile)

        chat = self.open_chat(ANNA, self.boris_profile)

        self.assertEqual(chat["peer"]["profile_id"], self.boris_profile)
        self.assertTrue(self.can_message(ANNA, self.boris_profile))
        self.assertFalse(self.can_message(BORIS, self.mum_profile))

    def test_the_refusal_speaks_the_apps_language(self) -> None:
        self.unfollow(BORIS, self.anna_profile)

        response = self.as_user(ANNA).post(
            "/api/v1/chats",
            json={"profile_id": self.boris_profile},
            headers={"Accept-Language": "ru"},
        )

        self.assertEqual(response.status_code, 403, response.text)
        self.assertEqual(response.json()["detail"], "Написать можно тому, кто подписан на вас.")

    def test_whoever_was_written_to_may_answer(self) -> None:
        # Anna follows Boris, Boris does not follow Anna: Boris writes first,
        # and Anna answers although the rule alone would not let her start.
        self.unfollow(BORIS, self.anna_profile)
        chat_id = self.open_chat(BORIS, self.anna_profile)["chat_id"]
        self.send(BORIS, chat_id, "Hi Anna")

        answering = self.as_user(ANNA).post(f"/api/v1/chats/{chat_id}/messages", json={"body": "Hi Boris"})

        self.assertEqual(answering.status_code, 200, answering.text)

    def test_a_chat_stays_readable_when_the_follow_breaks_and_stops_taking_messages(self) -> None:
        chat_id = self.open_chat(BORIS, self.anna_profile)["chat_id"]
        self.send(BORIS, chat_id, "Hi Anna")
        self.unfollow(ANNA, self.boris_profile)

        reading = self.as_user(BORIS).get(f"/api/v1/chats/{chat_id}/messages")
        sending = self.as_user(BORIS).post(f"/api/v1/chats/{chat_id}/messages", json={"body": "Still there?"})
        answering = self.as_user(ANNA).post(f"/api/v1/chats/{chat_id}/messages", json={"body": "Yes"})

        self.assertEqual(reading.status_code, 200, reading.text)
        self.assertEqual([m["body"] for m in reading.json()["messages"]], ["Hi Anna"])
        self.assertEqual(sending.status_code, 403, sending.text)
        self.assertEqual(sending.json()["detail"], NOT_FOLLOWING)
        # Anna was written to, so she may still answer.
        self.assertEqual(answering.status_code, 200, answering.text)

    def test_following_again_opens_it_again(self) -> None:
        chat_id = self.open_chat(BORIS, self.anna_profile)["chat_id"]
        self.unfollow(ANNA, self.boris_profile)
        self.follow(ANNA, self.boris_profile)

        self.send(BORIS, chat_id, "Welcome back")

        self.assertTrue(self.can_message(BORIS, self.anna_profile))


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
        self.follow(ANNA, clara_profile)
        self.follow(CLARA, self.anna_profile)
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

    def test_a_message_with_a_forbidden_word_is_not_sent(self) -> None:
        client = self.as_user(BORIS)

        english = client.post(f"/api/v1/chats/{self.chat_id}/messages", json={"body": "You are a f4ggot"})
        russian = client.post(f"/api/v1/chats/{self.chat_id}/messages", json={"body": "Ну ты и пидор"})
        spaced = client.post(f"/api/v1/chats/{self.chat_id}/messages", json={"body": "r a p e"})

        for response in (english, russian, spaced):
            self.assertEqual(response.status_code, 422, response.text)
            self.assertIn("can't be sent", response.json()["detail"])
        self.assertEqual(self.chats(ANNA)["chats"], [])
        self.assertEqual(self.unread(ANNA), 0)

    def test_ordinary_words_that_hide_a_forbidden_one_go_through(self) -> None:
        for body in (
            "Dick and I are going to Scunthorpe on the 5th",
            "Grapes at 10:45?",
            "Дебаты в субботу, страхуем друг друга",
            "Ребане споёт в 7",
        ):
            self.send(BORIS, self.chat_id, body)

        self.assertEqual(self.unread(ANNA), 4)

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

    def test_the_people_who_follow_each_other(self) -> None:
        self.assertEqual(self.contacts(BORIS), ["anna_p"])
        self.assertEqual(self.contacts(ANNA), ["boris_i"])

    def test_contacts_are_the_people_who_follow_you(self) -> None:
        self.unfollow(ANNA, self.boris_profile)

        self.assertEqual(self.contacts(BORIS), [])
        self.assertEqual(self.contacts(ANNA), ["boris_i"])

    def test_a_person_is_shown_as_their_own_chart(self) -> None:
        # Boris follows only Anna's mother's chart, and still Anna is drawn
        # as herself: her own chart is the one written to.
        self.unfollow(BORIS, self.anna_profile)
        self.follow(BORIS, self.mum_profile)

        people = self.as_user(BORIS).get("/api/v1/chats/contacts").json()["people"]

        self.assertEqual([person["profile_id"] for person in people], [self.anna_profile])

    def test_followers_without_a_chart_of_their_own_are_left_out(self) -> None:
        self.follow(CLARA, self.anna_profile)

        self.assertEqual(self.contacts(ANNA), ["boris_i"])

    def test_nobody_across_a_block(self) -> None:
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
        # Boris's follow in Activity, and the message.
        self.assertEqual(sent["payload"]["aps"]["badge"], 2)
        self.assertEqual(sent["payload"]["kind"], "message")
        self.assertEqual(sent["payload"]["chat_id"], self.chat_id)

    def test_the_badge_counts_activity_and_messages_together(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like", json={"feels_like": "Flowing"})
        self.send(BORIS, self.chat_id, "Hi")
        self.send(BORIS, self.chat_id, "Liked your sky")

        # The follow and the like in Activity, then each message.
        self.assertEqual([item["payload"]["aps"]["badge"] for item in self.sender.sent], [3, 4])

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


class MessageFilterTests(ChatTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.chat_id: int = self.open_chat(BORIS, self.anna_profile)["chat_id"]

    def post(self, body: str, lang: str = "en") -> Any:
        return self.as_user(BORIS).post(
            f"/api/v1/chats/{self.chat_id}/messages",
            json={"body": body},
            headers={"Accept-Language": lang},
        )

    def test_objectionable_words_are_refused_and_kept_out(self) -> None:
        for body in ("you f4ggot", "N1GGER", "r a p e", "ты пидор", "what a retard"):
            with self.subTest(body=body):
                response = self.post(body)
                self.assertEqual(response.status_code, 422, response.text)
                self.assertIn("can't be sent", response.json()["detail"])

        self.assertEqual(self.chats(ANNA)["chats"], [])

    def test_ordinary_sentences_pass(self) -> None:
        for body in (
            "Grape juice in Scunthorpe with Dick?",
            "Поп издал книгу о страховании",
            "Страхуем дом, а потом на дебаты",
            "I s a w it at 5 pm",
        ):
            with self.subTest(body=body):
                self.assertEqual(self.post(body).status_code, 200)

    def test_everyday_swearing_between_two_people_goes_through(self) -> None:
        for body in ("fuck, I missed the bus", "ну ты и сука, конечно", "иди нахуй, шучу"):
            with self.subTest(body=body):
                self.assertEqual(self.post(body).status_code, 200)

    def test_the_refusal_speaks_russian_to_a_russian_app(self) -> None:
        response = self.post("ты пидор", lang="ru")

        self.assertEqual(response.status_code, 422, response.text)
        self.assertIn("нельзя отправить", response.json()["detail"])


class RateLimitTests(ChatTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.chat_id: int = self.open_chat(BORIS, self.anna_profile)["chat_id"]
        self.session_factory = get_session_factory(os.environ["ASTRO_CONSUL_DATABASE_URL"])

    def backdate(self, sender: str, chat_id: int, count: int, age: timedelta) -> None:
        """Messages already sent, `age` ago, straight into the table."""
        when = datetime.now(UTC).replace(microsecond=0) - age
        with self.session_factory() as session:
            rows = [
                ChatMessageModel(chat_id=chat_id, sender_id=sender, body="Old", created_at=when) for _ in range(count)
            ]
            session.add_all(rows)
            session.flush()
            chat = session.get(ChatModel, chat_id)
            assert chat is not None
            chat.last_message_id = rows[-1].id
            session.commit()

    def started_chats(self, sender: str, count: int) -> None:
        """Conversations the sender started an hour ago, with people made up
        for it."""
        chat_ids = []
        with self.session_factory() as session:
            for number in range(count):
                other = f"user_stranger_{number}"
                ensure_user(session, other)
                first, second = ordered_pair(sender, other)
                chat = ChatModel(user_a_id=first, user_b_id=second, created_at=datetime.now(UTC))
                session.add(chat)
                session.flush()
                chat_ids.append(chat.id)
            session.commit()
        for chat_id in chat_ids:
            self.backdate(sender, chat_id, 1, timedelta(hours=1))

    def write(self, user_id: str, body: str) -> Any:
        return self.as_user(user_id).post(f"/api/v1/chats/{self.chat_id}/messages", json={"body": body})

    def test_thirty_messages_a_minute(self) -> None:
        for number in range(MESSAGES_PER_MINUTE):
            self.send(BORIS, self.chat_id, f"Message {number}")

        response = self.write(BORIS, "One more")
        answer = self.write(ANNA, "Slow down")

        self.assertEqual(MESSAGES_PER_MINUTE, 30)
        self.assertEqual(response.status_code, 429, response.text)
        self.assertEqual(response.headers["retry-after"], "60")
        self.assertIn("too fast", response.json()["detail"])
        self.assertEqual(answer.status_code, 200, answer.text)

    def test_a_minute_later_it_goes(self) -> None:
        self.backdate(BORIS, self.chat_id, MESSAGES_PER_MINUTE, timedelta(minutes=2))

        self.send(BORIS, self.chat_id, "Hello again")

    def test_five_hundred_messages_a_day(self) -> None:
        self.backdate(BORIS, self.chat_id, MESSAGES_PER_DAY, timedelta(hours=3))

        response = self.write(BORIS, "Hi")

        self.assertEqual(MESSAGES_PER_DAY, 500)
        self.assertEqual(response.status_code, 429, response.text)
        self.assertIn("a day allows", response.json()["detail"])

    def test_yesterdays_messages_do_not_count(self) -> None:
        self.backdate(BORIS, self.chat_id, MESSAGES_PER_DAY, timedelta(hours=25))

        self.send(BORIS, self.chat_id, "A new day")

    def test_twenty_new_chats_a_day(self) -> None:
        self.started_chats(BORIS, NEW_CHATS_PER_DAY)

        opening = self.as_user(BORIS).post("/api/v1/chats", json={"profile_id": self.anna_profile})
        first = self.write(BORIS, "Hi")

        self.assertEqual(NEW_CHATS_PER_DAY, 20)
        self.assertEqual(opening.status_code, 429, opening.text)
        self.assertIn("new chats", opening.json()["detail"])
        self.assertEqual(first.status_code, 429, first.text)

    def test_answering_or_going_on_is_not_starting_a_chat(self) -> None:
        self.started_chats(BORIS, NEW_CHATS_PER_DAY)
        self.send(ANNA, self.chat_id, "Hi Boris")

        self.send(BORIS, self.chat_id, "Hi Anna")
        self.send(BORIS, self.chat_id, "How are you?")
        self.open_chat(BORIS, self.anna_profile)


class ReportFromChatTests(ChatTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.chat_id: int = self.open_chat(BORIS, self.anna_profile)["chat_id"]
        self.mailed: list[dict[str, Any]] = []
        patcher = patch.object(social_routes, "send_report_email", self.record_mail)
        patcher.start()
        self.addCleanup(patcher.stop)

    def record_mail(self, report: dict[str, Any], profile: dict[str, Any], reporter_email: str, **kwargs: Any) -> bool:
        self.mailed.append({"report": report, "profile": profile, "conversation": kwargs.get("conversation")})
        return True

    def report(self, chat_id: int, block: bool = False) -> dict[str, Any]:
        response = self.as_user(ANNA).post(
            "/api/v1/reports",
            json={"profile_id": self.boris_profile, "reason": "harassment", "chat_id": chat_id, "block": block},
        )
        self.assertEqual(response.status_code, 200, response.text)
        result: dict[str, Any] = response.json()
        return result

    def test_the_report_carries_the_last_twenty_messages(self) -> None:
        for number in range(25):
            self.send(BORIS if number % 2 else ANNA, self.chat_id, f"Line {number}")

        result = self.report(self.chat_id)

        conversation = self.mailed[0]["conversation"]
        self.assertTrue(result["conversation_attached"])
        self.assertEqual(conversation["chat_id"], self.chat_id)
        self.assertEqual([m["body"] for m in conversation["messages"]], [f"Line {n}" for n in range(5, 25)])
        self.assertEqual(conversation["messages"][-1]["sender_name"], "Anna Petrova (@anna_p)")
        self.assertEqual(conversation["messages"][-1]["role"], "reporter")
        self.assertEqual(conversation["messages"][-2]["sender_name"], "Boris Ivanov (@boris_i)")
        self.assertEqual(conversation["messages"][-2]["role"], "reported")
        self.assertTrue(conversation["messages"][0]["created_at"].endswith("Z"))

    def test_reporting_and_blocking_still_reads_the_chat_first(self) -> None:
        self.send(BORIS, self.chat_id, "You will regret this")

        result = self.report(self.chat_id, block=True)

        self.assertTrue(result["blocked"])
        self.assertEqual([m["body"] for m in self.mailed[0]["conversation"]["messages"]], ["You will regret this"])
        self.assertEqual(self.chats(ANNA)["chats"], [])

    def test_a_chat_the_reporter_is_not_in_is_left_out(self) -> None:
        clara_profile = self._create_profile(CLARA, "Clara Weiss", "clara_w", "1995-01-15")
        self.follow(CLARA, self.boris_profile)
        self.follow(BORIS, clara_profile)
        theirs = self.open_chat(BORIS, clara_profile)["chat_id"]
        self.send(BORIS, theirs, "Private")

        result = self.report(theirs)

        self.assertFalse(result["conversation_attached"])
        self.assertIsNone(self.mailed[0]["conversation"])
        self.assertIsNotNone(result["report_id"])

    def test_a_chat_with_someone_else_is_left_out(self) -> None:
        clara_profile = self._create_profile(CLARA, "Clara Weiss", "clara_w", "1995-01-15")
        self.follow(CLARA, self.anna_profile)
        self.follow(ANNA, clara_profile)
        with_clara = self.open_chat(ANNA, clara_profile)["chat_id"]

        result = self.report(with_clara)

        self.assertFalse(result["conversation_attached"])

    def test_the_mail_shows_the_conversation_escaped(self) -> None:
        message = {
            "sender_name": "Boris Ivanov (@boris_i)",
            "role": "reported",
            "body": "<b>hi</b>\nthere",
            "created_at": "2026-09-27T10:00:00Z",
        }
        subject, body = report_email(
            {"report_id": 3, "reason": "harassment"},
            {"profile_id": "p1", "profile_name": "Boris Ivanov", "username": "boris_i"},
            "anna@example.test",
            {"chat_id": 7, "messages": [message]},
        )

        self.assertEqual(subject, "Report #3: harassment on @boris_i (from a chat)")
        self.assertIn("&lt;b&gt;hi&lt;/b&gt;<br>there", body)
        self.assertIn("chat #7", body)
        self.assertIn("2026-09-27T10:00:00Z", body)
        self.assertNotIn("<b>hi</b>", body)


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
    """The file social layer's cards (an account's first chart), blocks, and
    who follows whom, read from the fake profiles."""

    def __init__(self, first_charts: dict[str, str], profiles: FakeProfiles):
        self.first_charts = first_charts
        self.profiles = profiles
        self.blocked: dict[str, set[str]] = {}

    def follows_viewer(self, owner_user_id: str, viewer_user_id: str) -> bool:
        return any(
            self.profiles.get_owner_user_id(profile_id) == viewer_user_id
            for profile_id in self.profiles.follows.get(owner_user_id, [])
        )

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
        self.profiles = FakeProfiles(
            owners={"anna-chart": "anna", "mum-chart": "anna", "boris-chart": "boris"},
            follows={"boris": ["mum-chart"], "anna": ["boris-chart"]},
        )
        self.social = FakeSocial({"anna": "anna-chart", "boris": "boris-chart"}, self.profiles)
        self.repo = FileChatRepository(self.profiles, self.social, Path(self.temp_dir.name) / "_chats.json")  # type: ignore[arg-type]

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

    def test_contacts_are_the_people_who_follow_each_other(self) -> None:
        self.assertEqual([card["profile_id"] for card in self.repo.contacts("boris")], ["anna-chart"])
        self.assertEqual(self.repo.follows_between("boris", "anna"), (True, True))
        self.assertEqual(self.repo.primary_profile_of("anna"), "anna-chart")
        self.assertIsNone(self.repo.primary_profile_of("clara"))

        self.profiles.follows["anna"] = []

        self.assertEqual(self.repo.contacts("boris"), [])
        self.assertEqual(self.repo.follows_between("boris", "anna"), (True, False))

    def test_the_counts_the_limits_read_and_a_reported_conversation(self) -> None:
        chat = self.repo.open_chat("boris", "anna")
        hour_ago = datetime.now(UTC) - timedelta(hours=1)
        self.assertFalse(self.repo.has_conversation("anna", "boris"))

        self.repo.send_message("boris", chat["chat_id"], "Hi")
        self.repo.send_message("anna", chat["chat_id"], "Hello")
        self.repo.send_message("boris", chat["chat_id"], "How are you?")

        self.assertTrue(self.repo.has_conversation("anna", "boris"))
        self.assertEqual(self.repo.messages_sent_since("boris", hour_ago), 2)
        self.assertEqual(self.repo.chats_started_since("boris", hour_ago), 1)
        self.assertEqual(self.repo.chats_started_since("anna", hour_ago), 0)
        transcript = self.repo.transcript("anna", chat["chat_id"], limit=2)
        self.assertEqual(transcript["peer_id"], "boris")
        self.assertEqual([m["body"] for m in transcript["messages"]], ["Hello", "How are you?"])
        self.assertEqual(transcript["messages"][1]["sender_name"], "Boris")
        with self.assertRaises(ChatNotFound):
            self.repo.transcript("clara", chat["chat_id"])

    def test_a_block_hides_the_chat(self) -> None:
        chat = self.repo.open_chat("boris", "anna")
        self.repo.send_message("boris", chat["chat_id"], "Hi")
        self.social.blocked["anna"] = {"boris"}

        self.assertEqual(self.repo.list_chats("anna")["chats"], [])
        self.assertEqual(self.repo.unread_count("anna"), 0)


if __name__ == "__main__":
    unittest.main()
