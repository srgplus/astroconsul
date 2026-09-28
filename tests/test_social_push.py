"""Pushes for likes and follows: when one goes out, to whom, in what words,
and what happens to a token APNs no longer takes.

The sender is replaced by one that records what it was asked to send, so the
tests see exactly the payloads APNs would get; `ApnsClientTests` checks the
client itself against a fake HTTP transport.
"""

from __future__ import annotations

import json
import unittest
from typing import Any
from unittest.mock import patch

import httpx
import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from test_social_routes import ANNA, BORIS, CLARA, SocialTestCase

from app.api.dependencies import get_repositories
from app.application.services import social_push
from app.application.services.push_service import ApnsClient, PushResult
from app.application.services.social_push import compose

ANNA_PHONE = "a" * 64
ANNA_IPAD = "b" * 64


class RecordingSender:
    def __init__(self, gone: set[str] | None = None) -> None:
        self.sent: list[dict[str, Any]] = []
        self.gone = gone or set()

    def send(
        self,
        token: str,
        environment: str,
        payload: dict[str, Any],
        *,
        collapse_id: str | None = None,
    ) -> PushResult:
        self.sent.append({"token": token, "environment": environment, "payload": payload})
        if token in self.gone:
            return PushResult(ok=False, status=410, reason="Unregistered", gone=True)
        return PushResult(ok=True, status=200)

    def bodies(self) -> list[str]:
        return [item["payload"]["aps"]["alert"]["body"] for item in self.sent]


class PushTestCase(SocialTestCase):
    def setUp(self) -> None:
        super().setUp()
        social_push._recent_pushes.clear()
        self.sender = RecordingSender()
        patcher = patch.object(social_push, "get_sender", lambda: self.sender)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.register(ANNA, ANNA_PHONE)

    def register(self, user_id: str, token: str, *, lang: str = "en", environment: str = "production") -> None:
        response = self.as_user(user_id).post(
            "/api/v1/devices",
            json={"token": token, "environment": environment, "lang": lang},
        )
        self.assertEqual(response.status_code, 200, response.text)

    def devices(self, user_id: str) -> list[dict[str, str]]:
        repos = get_repositories()
        assert repos.social is not None
        return repos.social.devices_for(user_id)


class LikePushTests(PushTestCase):
    def test_a_like_is_pushed_to_the_owner_in_the_rows_words(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like", json={"feels_like": "Flowing"})

        self.assertEqual(self.sender.bodies(), ["Boris Ivanov liked your chart · Flowing"])
        sent = self.sender.sent[0]
        self.assertEqual(sent["token"], ANNA_PHONE)
        self.assertEqual(sent["environment"], "production")
        self.assertEqual(sent["payload"]["aps"]["badge"], 1)
        self.assertEqual(sent["payload"]["kind"], "like")
        self.assertEqual(sent["payload"]["profile_id"], self.anna_profile)

    def test_a_like_says_who_it_is_from_for_the_phone_to_draw(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like", json={"feels_like": "Flowing"})

        payload = self.sender.sent[0]["payload"]
        self.assertEqual(payload["aps"]["mutable-content"], 1)
        self.assertEqual(payload["sender"]["name"], "Boris Ivanov")
        # Born 2 November 1988: the Sun in Scorpio.
        self.assertEqual(payload["sender"]["sign"], "Scorpio")
        self.assertEqual(payload["short_body"], "Liked your chart · Flowing")
        # A hash, the same for every push from Boris, and not his account id.
        self.assertNotIn(BORIS, payload["sender"]["id"])
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")
        self.assertEqual(self.sender.sent[1]["payload"]["sender"]["id"], payload["sender"]["id"])

    def test_a_second_state_the_same_day_does_not_buzz_again(self) -> None:
        path = f"/api/v1/profiles/{self.anna_profile}/like"
        self.as_user(BORIS).post(path, json={"feels_like": "Flowing"})
        self.as_user(BORIS).post(path, json={"feels_like": "Expansive"})
        self.as_user(BORIS).post(path, json={"feels_like": "Flowing"})

        self.assertEqual(len(self.sender.sent), 1)

    def test_unliking_and_liking_again_is_not_news_twice(self) -> None:
        path = f"/api/v1/profiles/{self.anna_profile}/like"
        for _ in range(3):
            self.as_user(BORIS).post(path, json={"feels_like": "Flowing"})
            self.as_user(BORIS).delete(path, params={"feels_like": "Flowing"})
        self.as_user(BORIS).post(path, json={"feels_like": "Flowing"})

        self.assertEqual(len(self.sender.sent), 1)

    def test_liking_your_own_chart_sends_nothing(self) -> None:
        self.as_user(ANNA).post(f"/api/v1/profiles/{self.anna_profile}/like", json={"feels_like": "Flowing"})

        self.assertEqual(self.sender.sent, [])

    def test_every_phone_of_the_owner_hears_in_its_own_language(self) -> None:
        self.register(ANNA, ANNA_IPAD, lang="ru", environment="sandbox")

        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like", json={"feels_like": "Expansive"})

        by_token = {item["token"]: item for item in self.sender.sent}
        self.assertEqual(
            by_token[ANNA_IPAD]["payload"]["aps"]["alert"]["body"], "Boris Ivanov лайкнул(а) вашу карту · Расширение"
        )
        self.assertEqual(by_token[ANNA_IPAD]["environment"], "sandbox")
        self.assertIn(ANNA_PHONE, by_token)

    def test_switched_off_likes_stay_quiet_and_follows_still_come(self) -> None:
        self.as_user(ANNA).put("/api/v1/social/settings", json={"push_likes": False})

        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like")
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")

        self.assertEqual(self.sender.bodies(), ["Boris Ivanov started following you"])

    def test_an_account_without_a_chart_is_named_as_a_member(self) -> None:
        self.as_user(CLARA).post(f"/api/v1/profiles/{self.anna_profile}/like")

        self.assertEqual(self.sender.bodies(), ["A big3.me member liked your chart"])
        sender = self.sender.sent[0]["payload"]["sender"]
        self.assertEqual(sender["name"], "A big3.me member")
        self.assertNotIn("sign", sender)

    def test_a_token_apns_dropped_is_forgotten(self) -> None:
        self.sender.gone = {ANNA_PHONE}

        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like")

        self.assertEqual(self.devices(ANNA), [])

    def test_no_key_means_no_push_and_the_like_still_lands(self) -> None:
        with patch.object(social_push, "get_sender", lambda: None):
            response = self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["likes_count"], 1)
        self.assertEqual(self.sender.sent, [])


class FollowPushTests(PushTestCase):
    def test_a_new_follow_is_pushed(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")

        self.assertEqual(self.sender.bodies(), ["Boris Ivanov started following you"])
        self.assertEqual(self.sender.sent[0]["payload"]["kind"], "follow")
        self.assertEqual(self.sender.sent[0]["payload"]["short_body"], "Started following you")

    def test_following_again_is_not_news_twice(self) -> None:
        path = f"/api/v1/profiles/{self.anna_profile}/follow"
        self.as_user(BORIS).post(path)
        self.as_user(BORIS).post(path)
        self.as_user(BORIS).delete(path)
        self.as_user(BORIS).post(path)

        self.assertEqual(len(self.sender.sent), 1)

    def test_a_chart_that_is_not_the_primary_is_named(self) -> None:
        response = self.as_user(ANNA).post(
            "/api/v1/profiles",
            json={
                "profile_name": "Mum",
                "username": "anna_mum",
                "birth_date": "1960-06-15",
                "birth_time": "08:00",
                "timezone": "Europe/Berlin",
                "location_name": "Berlin, Germany",
                "latitude": 52.52,
                "longitude": 13.405,
            },
        )
        mum = response.json()["profile"]["profile_id"]

        self.as_user(BORIS).post(f"/api/v1/profiles/{mum}/follow")

        self.assertEqual(self.sender.bodies(), ["Boris Ivanov started following Mum"])
        self.assertEqual(self.sender.sent[0]["payload"]["short_body"], "Started following Mum")


class DeviceTests(PushTestCase):
    def test_a_phone_moves_to_whoever_signs_in_on_it(self) -> None:
        self.register(BORIS, ANNA_PHONE)

        self.assertEqual(self.devices(ANNA), [])
        self.assertEqual([d["token"] for d in self.devices(BORIS)], [ANNA_PHONE])

    def test_sign_out_forgets_only_your_own_phone(self) -> None:
        self.register(BORIS, ANNA_IPAD)

        self.as_user(BORIS).delete(f"/api/v1/devices/{ANNA_PHONE}")
        self.as_user(ANNA).delete(f"/api/v1/devices/{ANNA_PHONE}")

        self.assertEqual(self.devices(ANNA), [])
        self.assertEqual([d["token"] for d in self.devices(BORIS)], [ANNA_IPAD])

    def test_a_token_that_is_not_hex_is_refused(self) -> None:
        response = self.as_user(ANNA).post("/api/v1/devices", json={"token": "not a token at all!"})

        self.assertEqual(response.status_code, 422)

    def test_settings_carry_every_switch(self) -> None:
        before = self.as_user(ANNA).get("/api/v1/social/settings").json()
        after = self.as_user(ANNA).put("/api/v1/social/settings", json={"push_follows": False}).json()

        self.assertEqual(before, {"show_counts": True, "push_likes": True, "push_follows": True, "push_messages": True})
        self.assertEqual(after, {"show_counts": True, "push_likes": True, "push_follows": False, "push_messages": True})

    def test_deleting_the_account_forgets_its_phones(self) -> None:
        response = self.as_user(ANNA).delete("/api/v1/auth/account")

        self.assertEqual(response.status_code, 204)
        self.assertEqual(self.devices(ANNA), [])


class ComposeTests(unittest.TestCase):
    def test_other_chart_in_russian(self) -> None:
        body = compose("like", "ru", actor_name="Борис", chart_name="Мама", is_primary=False, feels_like=None)

        self.assertEqual(body, "Борис лайкнул(а) карту «Мама»")

    def test_under_the_name_in_russian(self) -> None:
        body = compose(
            "like", "ru", actor_name="Борис", chart_name="Мама", is_primary=False, feels_like="Calm", titled=True
        )

        self.assertEqual(body, "Лайкнул(а) карту «Мама» · Спокойно")

    def test_unknown_language_reads_english(self) -> None:
        body = compose("follow", "de", actor_name="Boris", chart_name=None, is_primary=False, feels_like=None)

        self.assertEqual(body, "Boris started following you")


class ApnsClientTests(unittest.TestCase):
    def setUp(self) -> None:
        key = ec.generate_private_key(ec.SECP256R1())
        self.public_key = key.public_key()
        self.pem = key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        ).decode()
        self.requests: list[httpx.Request] = []
        self.answer = httpx.Response(200)

    def client(self) -> ApnsClient:
        def handler(request: httpx.Request) -> httpx.Response:
            self.requests.append(request)
            return self.answer

        return ApnsClient(
            key_id="KEY1234567",
            private_key=self.pem,
            team_id="85679N47YT",
            topic="me.big3.app",
            transport=httpx.MockTransport(handler),
        )

    def test_a_push_is_signed_for_the_team_and_sent_to_the_right_host(self) -> None:
        result = self.client().send("ab" * 32, "sandbox", {"aps": {"alert": {"body": "hi"}}}, collapse_id="c1")

        self.assertTrue(result.ok)
        request = self.requests[0]
        self.assertEqual(str(request.url), f"https://api.sandbox.push.apple.com/3/device/{'ab' * 32}")
        self.assertEqual(request.headers["apns-topic"], "me.big3.app")
        self.assertEqual(request.headers["apns-push-type"], "alert")
        self.assertEqual(request.headers["apns-collapse-id"], "c1")
        token = request.headers["authorization"].removeprefix("bearer ")
        self.assertEqual(jwt.get_unverified_header(token)["kid"], "KEY1234567")
        claims = jwt.decode(token, self.public_key, algorithms=["ES256"])
        self.assertEqual(claims["iss"], "85679N47YT")
        self.assertEqual(json.loads(request.content), {"aps": {"alert": {"body": "hi"}}})

    def test_the_provider_token_is_reused(self) -> None:
        client = self.client()
        client.send("ab" * 32, "production", {})
        client.send("ab" * 32, "production", {})

        self.assertEqual(self.requests[0].headers["authorization"], self.requests[1].headers["authorization"])
        self.assertTrue(str(self.requests[0].url).startswith("https://api.push.apple.com/"))

    def test_an_unregistered_token_comes_back_gone(self) -> None:
        self.answer = httpx.Response(410, json={"reason": "Unregistered"})

        result = self.client().send("ab" * 32, "production", {})

        self.assertFalse(result.ok)
        self.assertTrue(result.gone)
        self.assertEqual(result.reason, "Unregistered")

    def test_a_bad_key_is_not_a_gone_token(self) -> None:
        self.answer = httpx.Response(403, json={"reason": "InvalidProviderToken"})

        result = self.client().send("ab" * 32, "production", {})

        self.assertFalse(result.gone)
        self.assertEqual(result.status, 403)


if __name__ == "__main__":
    unittest.main()
