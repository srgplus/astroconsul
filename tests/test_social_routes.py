"""The social layer end to end: likes, Activity, who follows and likes whom,
blocks, reports and the name filter, against a real SQLite database.

Each test signs in as one of three people and acts through the HTTP routes,
so what is checked is what the app sees: Anna and Boris own a chart each,
and Clara owns none.
"""

from __future__ import annotations

import os
import tempfile
import unittest
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from typing import Any

from fastapi.testclient import TestClient

from app.api.auth import get_current_user
from app.api.dependencies import clear_dependency_caches
from app.core.config import clear_settings_cache
from app.infrastructure.persistence.base import Base
from app.infrastructure.persistence.models import ProfileLikeModel
from app.infrastructure.persistence.session import clear_engine_cache, get_engine, get_session_factory
from app.main import create_app

ANNA = "user_anna"
BORIS = "user_boris"
CLARA = "user_clara"


def _profile_body(name: str, username: str, birth_date: str) -> dict[str, Any]:
    return {
        "profile_name": name,
        "username": username,
        "birth_date": birth_date,
        "birth_time": "12:00",
        "timezone": "Europe/Berlin",
        "location_name": "Berlin, Germany",
        "latitude": 52.52,
        "longitude": 13.405,
    }


class SocialTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        database = Path(self.temp_dir.name) / "social.db"
        os.environ["ASTRO_CONSUL_PERSISTENCE_BACKEND"] = "database"
        os.environ["ASTRO_CONSUL_DATABASE_URL"] = f"sqlite:///{database}"
        os.environ["ASTRO_CONSUL_AUTH_ENABLED"] = "false"
        os.environ.pop("ASTRO_CONSUL_RESEND_API_KEY", None)
        clear_settings_cache()
        clear_dependency_caches()
        clear_engine_cache()
        Base.metadata.create_all(get_engine(f"sqlite:///{database}"))

        self.app = create_app()
        self.client = TestClient(self.app)

        self.anna_profile = self._create_profile(ANNA, "Anna Petrova", "anna_p", "1990-03-21")
        self.boris_profile = self._create_profile(BORIS, "Boris Ivanov", "boris_i", "1988-11-02")

    def tearDown(self) -> None:
        self.app.dependency_overrides.clear()
        for env_var in ("ASTRO_CONSUL_PERSISTENCE_BACKEND", "ASTRO_CONSUL_DATABASE_URL", "ASTRO_CONSUL_AUTH_ENABLED"):
            os.environ.pop(env_var, None)
        clear_dependency_caches()
        clear_settings_cache()
        clear_engine_cache()
        self.temp_dir.cleanup()

    def as_user(self, user_id: str) -> TestClient:
        self.app.dependency_overrides[get_current_user] = lambda: {
            "user_id": user_id,
            "email": f"{user_id}@example.test",
        }
        return self.client

    def _create_profile(self, user_id: str, name: str, username: str, birth_date: str) -> str:
        response = self.as_user(user_id).post("/api/v1/profiles", json=_profile_body(name, username, birth_date))
        self.assertEqual(response.status_code, 200, response.text)
        profile_id: str = response.json()["profile"]["profile_id"]
        self.as_user(user_id).put("/api/v1/profiles/primary", json={"profile_id": profile_id})
        return profile_id


class LikeTests(SocialTestCase):
    def test_like_counts_and_is_idempotent(self) -> None:
        client = self.as_user(BORIS)

        first = client.post(f"/api/v1/profiles/{self.anna_profile}/like")
        second = client.post(f"/api/v1/profiles/{self.anna_profile}/like")

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.json()["likes_count"], 1)
        self.assertTrue(second.json()["is_liked"])

    def test_unlike_takes_it_back(self) -> None:
        client = self.as_user(BORIS)
        client.post(f"/api/v1/profiles/{self.anna_profile}/like")

        response = client.delete(f"/api/v1/profiles/{self.anna_profile}/like")

        self.assertEqual(response.json()["likes_count"], 0)
        self.assertFalse(response.json()["is_liked"])

    def test_cannot_like_own_profile(self) -> None:
        response = self.as_user(ANNA).post(f"/api/v1/profiles/{self.anna_profile}/like")

        self.assertEqual(response.status_code, 400)

    def test_a_new_state_can_be_liked_again(self) -> None:
        client = self.as_user(BORIS)
        path = f"/api/v1/profiles/{self.anna_profile}/like"

        flowing = client.post(path, json={"feels_like": "Flowing"}).json()
        again = client.post(path, json={"feels_like": "Flowing"}).json()
        expansive = client.post(path, json={"feels_like": "Expansive"}).json()

        self.assertEqual(flowing["state_likes"], {"Flowing": 1})
        self.assertEqual(again["state_likes"], {"Flowing": 1})
        self.assertEqual(expansive["state_likes"], {"Flowing": 1, "Expansive": 1})
        self.assertEqual(sorted(expansive["my_state_likes"]), ["Expansive", "Flowing"])
        self.assertEqual(expansive["likes_count"], 2)

    def test_unlike_takes_back_one_state_only(self) -> None:
        client = self.as_user(BORIS)
        path = f"/api/v1/profiles/{self.anna_profile}/like"
        client.post(path, json={"feels_like": "Flowing"})
        client.post(path, json={"feels_like": "Expansive"})

        after = client.delete(path, params={"feels_like": "Flowing"}).json()

        self.assertEqual(after["state_likes"], {"Expansive": 1})
        self.assertEqual(after["my_state_likes"], ["Expansive"])

    def test_yesterdays_state_is_not_todays(self) -> None:
        # A like on the same word two days ago, written the way the route
        # writes today's.
        session_factory = get_session_factory(os.environ["ASTRO_CONSUL_DATABASE_URL"])
        with session_factory() as session:
            session.add(
                ProfileLikeModel(
                    user_id=BORIS,
                    profile_id=self.anna_profile,
                    day=date.today() - timedelta(days=2),
                    feels_like="Calm",
                    created_at=datetime.now(UTC) - timedelta(days=2),
                )
            )
            session.commit()

        before = self.as_user(BORIS).get(f"/api/v1/profiles/{self.anna_profile}").json()["profile"]
        liked = (
            self.as_user(BORIS)
            .post(f"/api/v1/profiles/{self.anna_profile}/like", json={"feels_like": "Calm", "tii": 12})
            .json()
        )

        self.assertEqual(before["my_state_likes"], [])
        self.assertEqual(before["likes_count"], 0)
        self.assertEqual(liked["state_likes"], {"Calm": 1})
        self.assertEqual(liked["likes_total"], 2)

    def test_activity_carries_the_word_that_was_liked(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like", json={"feels_like": "Expansive"})

        item = self.as_user(ANNA).get("/api/v1/activity").json()["items"][0]

        self.assertEqual(item["feels_like"], "Expansive")
        self.assertIsNotNone(item["day"])

    def test_a_word_that_is_not_ours_is_dropped(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like", json={"feels_like": "Cursed"})

        item = self.as_user(ANNA).get("/api/v1/activity").json()["items"][0]

        self.assertIsNone(item["feels_like"])

    def test_like_of_missing_profile_is_404(self) -> None:
        response = self.as_user(ANNA).post("/api/v1/profiles/profile_nope/like")

        self.assertEqual(response.status_code, 404)

    def test_detail_and_listing_carry_the_counts(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like")
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")
        self.as_user(ANNA).post(f"/api/v1/profiles/{self.boris_profile}/follow")

        detail = self.as_user(BORIS).get(f"/api/v1/profiles/{self.anna_profile}").json()["profile"]
        listing = self.as_user(ANNA).get("/api/v1/profiles").json()["profiles"]
        own = next(p for p in listing if p["profile_id"] == self.anna_profile)

        self.assertEqual(detail["likes_count"], 1)
        self.assertTrue(detail["is_liked"])
        self.assertTrue(detail["follows_you"])
        self.assertEqual(own["likes_count"], 1)
        self.assertEqual(own["followers_count"], 1)
        followed = next(p for p in listing if p["profile_id"] == self.boris_profile)
        self.assertTrue(followed["follows_you"])
        self.assertFalse(own["follows_you"])

    def test_search_results_carry_the_counts(self) -> None:
        self.as_user(CLARA).post(f"/api/v1/profiles/{self.anna_profile}/like")

        results = self.as_user(BORIS).get("/api/v1/profiles/search", params={"q": "anna"}).json()["results"]

        self.assertEqual(results[0]["likes_count"], 1)
        self.assertFalse(results[0]["is_liked"])


class ActivityTests(SocialTestCase):
    def test_owner_sees_likes_and_follows_newest_first(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like")

        activity = self.as_user(ANNA).get("/api/v1/activity").json()

        kinds = {item["kind"] for item in activity["items"]}
        self.assertEqual(kinds, {"like", "follow"})
        self.assertEqual(activity["unread_count"], 2)
        first = activity["items"][0]
        self.assertEqual(first["actor"]["profile_id"], self.boris_profile)
        self.assertEqual(first["actor"]["profile_name"], "Boris Ivanov")
        self.assertEqual(first["target"]["profile_id"], self.anna_profile)
        self.assertFalse(first["actor_followed"])
        self.assertIn("latest_transit", first["actor"])

    def test_follow_back_is_reflected(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")
        self.as_user(ANNA).post(f"/api/v1/profiles/{self.boris_profile}/follow")

        item = self.as_user(ANNA).get("/api/v1/activity").json()["items"][0]

        self.assertTrue(item["actor_followed"])

    def test_seen_clears_the_badge_until_something_new(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like")
        self.as_user(ANNA).post("/api/v1/activity/seen")

        cleared = self.as_user(ANNA).get("/api/v1/activity/unread").json()
        self.assertEqual(cleared["unread_count"], 0)

    def test_account_without_a_chart_still_shows_up(self) -> None:
        self.as_user(CLARA).post(f"/api/v1/profiles/{self.anna_profile}/like")

        item = self.as_user(ANNA).get("/api/v1/activity").json()["items"][0]

        self.assertIsNone(item["actor"]["profile_id"])

    def test_nobody_else_sees_someones_activity(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like")

        activity = self.as_user(CLARA).get("/api/v1/activity").json()

        self.assertEqual(activity["items"], [])


class PeopleListTests(SocialTestCase):
    def test_owner_sees_who_likes_and_follows(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like")
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")

        likers = self.as_user(ANNA).get(f"/api/v1/profiles/{self.anna_profile}/likes").json()["people"]
        followers = self.as_user(ANNA).get(f"/api/v1/profiles/{self.anna_profile}/followers").json()["people"]

        self.assertEqual([p["actor"]["username"] for p in likers], ["boris_i"])
        self.assertEqual([p["actor"]["username"] for p in followers], ["boris_i"])

    def test_only_the_owner_may_look(self) -> None:
        likers = self.as_user(BORIS).get(f"/api/v1/profiles/{self.anna_profile}/likes")
        followers = self.as_user(BORIS).get(f"/api/v1/profiles/{self.anna_profile}/followers")

        self.assertEqual(likers.status_code, 403)
        self.assertEqual(followers.status_code, 403)


class BlockTests(SocialTestCase):
    def _anna_blocks_boris(self) -> None:
        response = self.as_user(ANNA).post("/api/v1/blocks", json={"profile_id": self.boris_profile})
        self.assertEqual(response.status_code, 200, response.text)

    def test_block_severs_follows_and_likes_both_ways(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like")
        self.as_user(ANNA).post(f"/api/v1/profiles/{self.boris_profile}/follow")

        self._anna_blocks_boris()

        boris_list = self.as_user(BORIS).get("/api/v1/profiles").json()["profiles"]
        anna_list = self.as_user(ANNA).get("/api/v1/profiles").json()["profiles"]
        self.assertNotIn(self.anna_profile, [p["profile_id"] for p in boris_list])
        self.assertNotIn(self.boris_profile, [p["profile_id"] for p in anna_list])
        self.assertEqual(self.as_user(ANNA).get("/api/v1/activity").json()["items"], [])

    def test_blocked_account_cannot_come_back(self) -> None:
        self._anna_blocks_boris()

        follow = self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")
        like = self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like")
        detail = self.as_user(BORIS).get(f"/api/v1/profiles/{self.anna_profile}")

        self.assertEqual(follow.status_code, 404)
        self.assertEqual(like.status_code, 404)
        self.assertEqual(detail.status_code, 404)

    def test_blocker_is_told_how_to_undo_it(self) -> None:
        self._anna_blocks_boris()

        response = self.as_user(ANNA).post(f"/api/v1/profiles/{self.boris_profile}/follow")

        self.assertEqual(response.status_code, 403)
        self.assertIn("Unblock", response.json()["detail"])

    def test_neither_side_finds_the_other_in_search(self) -> None:
        self._anna_blocks_boris()

        anna_search = self.as_user(ANNA).get("/api/v1/profiles/search", params={"q": "boris"}).json()
        boris_search = self.as_user(BORIS).get("/api/v1/profiles/search", params={"q": "anna"}).json()

        self.assertEqual(anna_search["results"], [])
        self.assertEqual(boris_search["results"], [])

    def test_unblock_restores_following(self) -> None:
        self._anna_blocks_boris()
        blocks = self.as_user(ANNA).get("/api/v1/blocks").json()["blocks"]
        self.assertEqual(blocks[0]["actor"]["username"], "boris_i")

        unblock = self.as_user(ANNA).delete(f"/api/v1/blocks/{blocks[0]['block_id']}")
        follow = self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")

        self.assertEqual(unblock.status_code, 200)
        self.assertEqual(follow.status_code, 200)

    def test_cannot_lift_someone_elses_block(self) -> None:
        self._anna_blocks_boris()
        block_id = self.as_user(ANNA).get("/api/v1/blocks").json()["blocks"][0]["block_id"]

        response = self.as_user(BORIS).delete(f"/api/v1/blocks/{block_id}")

        self.assertEqual(response.status_code, 404)

    def test_cannot_block_yourself(self) -> None:
        response = self.as_user(ANNA).post("/api/v1/blocks", json={"profile_id": self.anna_profile})

        self.assertEqual(response.status_code, 400)


class ReportTests(SocialTestCase):
    def test_report_is_filed_and_can_block_in_the_same_step(self) -> None:
        self.as_user(ANNA).post(f"/api/v1/profiles/{self.boris_profile}/follow")

        response = self.as_user(ANNA).post(
            "/api/v1/reports",
            json={"profile_id": self.boris_profile, "reason": "harassment", "details": "Rude name", "block": True},
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(response.json()["blocked"])
        self.assertIsNotNone(response.json()["report_id"])
        follow = self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/follow")
        self.assertEqual(follow.status_code, 404)

    def test_unknown_reason_is_refused(self) -> None:
        response = self.as_user(ANNA).post(
            "/api/v1/reports", json={"profile_id": self.boris_profile, "reason": "dislike"}
        )

        self.assertEqual(response.status_code, 422)

    def test_cannot_report_own_profile(self) -> None:
        response = self.as_user(ANNA).post("/api/v1/reports", json={"profile_id": self.anna_profile, "reason": "spam"})

        self.assertEqual(response.status_code, 400)


class NameFilterTests(SocialTestCase):
    def test_objectionable_name_is_refused_on_create(self) -> None:
        response = self.as_user(CLARA).post("/api/v1/profiles", json=_profile_body("Fuck Off", "clara_x", "1995-06-01"))

        self.assertEqual(response.status_code, 400)
        self.assertIn("can't be used", response.json()["detail"])

    def test_objectionable_handle_is_refused_on_edit(self) -> None:
        response = self.as_user(ANNA).patch(
            f"/api/v1/profiles/{self.anna_profile}",
            json=_profile_body("Anna Petrova", "bitch_queen", "1990-03-21"),
        )

        self.assertEqual(response.status_code, 400)

    def test_ordinary_names_pass(self) -> None:
        response = self.as_user(CLARA).post(
            "/api/v1/profiles", json=_profile_body("Dick Grayson", "scunthorpe_fan", "1995-06-01")
        )

        self.assertEqual(response.status_code, 200, response.text)


class AccountDeletionTests(SocialTestCase):
    def test_deleting_an_account_takes_its_likes_and_blocks(self) -> None:
        self.as_user(BORIS).post(f"/api/v1/profiles/{self.anna_profile}/like")
        self.as_user(BORIS).post("/api/v1/blocks", json={"profile_id": self.anna_profile})

        response = self.as_user(BORIS).delete("/api/v1/auth/account")

        self.assertEqual(response.status_code, 204)
        self.assertEqual(self.as_user(ANNA).get("/api/v1/activity").json()["items"], [])
        detail = self.as_user(ANNA).get(f"/api/v1/profiles/{self.anna_profile}").json()["profile"]
        self.assertEqual(detail["likes_count"], 0)
