"""Which chart is the account's own: the primary profile.

An account's first chart becomes its own without a question. Past that the app
asks, so the server's part is never to hand out a primary the account does not
own: a transfer and a delete both clear one, and the listing checks what it
reads. Run against a real SQLite database, through the HTTP routes, the way the
app sees it.
"""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from typing import Any

from fastapi.testclient import TestClient
from sqlalchemy import event, update

from app.api.auth import get_current_user
from app.api.dependencies import clear_dependency_caches
from app.core.config import clear_settings_cache
from app.infrastructure.persistence.base import Base
from app.infrastructure.persistence.models import UserModel
from app.infrastructure.persistence.session import clear_engine_cache, get_engine, get_session_factory
from app.main import create_app

ANNA = "user_anna"
BORIS = "user_boris"


def _profile_body(name: str, username: str) -> dict[str, Any]:
    return {
        "profile_name": name,
        "username": username,
        "birth_date": "1990-03-21",
        "birth_time": "12:00",
        "timezone": "Europe/Berlin",
        "location_name": "Berlin, Germany",
        "latitude": 52.52,
        "longitude": 13.405,
    }


def _enforce_foreign_keys(dbapi_connection: Any, _record: Any) -> None:
    # SQLite ignores foreign keys unless asked, and Postgres never does: without
    # this a delete that production refuses passes here.
    dbapi_connection.execute("PRAGMA foreign_keys=ON")


class PrimaryTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.database_url = f"sqlite:///{Path(self.temp_dir.name) / 'primary.db'}"
        os.environ["ASTRO_CONSUL_PERSISTENCE_BACKEND"] = "database"
        os.environ["ASTRO_CONSUL_DATABASE_URL"] = self.database_url
        os.environ["ASTRO_CONSUL_AUTH_ENABLED"] = "false"
        os.environ.pop("ASTRO_CONSUL_RESEND_API_KEY", None)
        clear_settings_cache()
        clear_dependency_caches()
        clear_engine_cache()
        engine = get_engine(self.database_url)
        event.listen(engine, "connect", _enforce_foreign_keys)
        Base.metadata.create_all(engine)

        self.app = create_app()
        self.client = TestClient(self.app)

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

    def create(self, user_id: str, name: str, username: str) -> str:
        response = self.as_user(user_id).post("/api/v1/profiles", json=_profile_body(name, username))
        self.assertEqual(response.status_code, 200, response.text)
        profile_id: str = response.json()["profile"]["profile_id"]
        return profile_id

    def listing(self, user_id: str) -> dict[str, Any]:
        response = self.as_user(user_id).get("/api/v1/profiles")
        self.assertEqual(response.status_code, 200, response.text)
        payload: dict[str, Any] = response.json()
        return payload

    def primary_of(self, user_id: str) -> str | None:
        primary: str | None = self.listing(user_id)["primary_profile_id"]
        return primary

    def stored_primary(self, user_id: str) -> str | None:
        """What the row says, as opposed to what the listing hands out."""
        with get_session_factory(self.database_url)() as session:
            user = session.get(UserModel, user_id)
            return user.primary_profile_id if user else None

    def store_primary(self, user_id: str, profile_id: str | None) -> None:
        """Writes the row directly: the shapes older code left behind."""
        with get_session_factory(self.database_url)() as session:
            session.execute(update(UserModel).where(UserModel.id == user_id).values(primary_profile_id=profile_id))
            session.commit()

    def transfer(self, sender: str, profile_id: str, recipient: str) -> dict[str, Any]:
        invite = self.as_user(sender).post(
            f"/api/v1/profiles/{profile_id}/invite", json={"email": f"{recipient}@example.com"}
        )
        self.assertEqual(invite.status_code, 200, invite.text)
        accepted = self.as_user(recipient).post(f"/api/v1/invites/{invite.json()['token']}/accept")
        self.assertEqual(accepted.status_code, 200, accepted.text)
        payload: dict[str, Any] = accepted.json()
        return payload


class FirstChartTests(PrimaryTestCase):
    def test_the_first_chart_of_an_empty_account_becomes_its_own(self) -> None:
        anna = self.create(ANNA, "Anna Petrova", "anna_p")

        self.assertEqual(self.primary_of(ANNA), anna)

    def test_a_second_chart_does_not_take_over(self) -> None:
        anna = self.create(ANNA, "Anna Petrova", "anna_p")
        self.create(ANNA, "Anna's mother", "anna_mom")

        self.assertEqual(self.primary_of(ANNA), anna)

    def test_an_account_with_charts_and_no_primary_is_asked_not_guessed(self) -> None:
        # Accounts from before the rule: charts, and nothing marked as theirs.
        self.create(ANNA, "Anna's mother", "anna_mom")
        self.store_primary(ANNA, None)

        self.create(ANNA, "Anna's friend", "anna_friend")

        self.assertIsNone(self.primary_of(ANNA))

    def test_the_first_chart_replaces_a_primary_the_account_no_longer_owns(self) -> None:
        # An account row with no charts on it and a primary left over.
        old = self.create(ANNA, "Anna Petrova", "anna_old")
        self.as_user(ANNA).delete(f"/api/v1/profiles/{old}")
        self.store_primary(ANNA, "profile_given_away_long_ago")

        anna = self.create(ANNA, "Anna Petrova", "anna_p")

        self.assertEqual(self.primary_of(ANNA), anna)

    def test_a_chart_made_after_the_last_one_was_deleted_is_the_first_again(self) -> None:
        old = self.create(ANNA, "Anna Petrova", "anna_p")
        self.as_user(ANNA).delete(f"/api/v1/profiles/{old}")

        anna = self.create(ANNA, "Anna Petrova", "anna_p2")

        self.assertEqual(self.primary_of(ANNA), anna)


class TransferTests(PrimaryTestCase):
    def test_a_chart_given_to_an_empty_account_leaves_the_question_open(self) -> None:
        gift = self.create(ANNA, "Boris Ivanov", "boris_i")

        accepted = self.transfer(ANNA, gift, BORIS)

        # Most likely Boris's own chart, but his to say: the accepting page
        # asks, and the app asks again if he does not answer there.
        self.assertIsNone(accepted["primary_profile_id"])
        self.assertIsNone(self.primary_of(BORIS))
        owned = [p["profile_id"] for p in self.listing(BORIS)["profiles"] if p["is_own"]]
        self.assertEqual(owned, [gift])

    def test_giving_away_your_own_chart_takes_it_off_you(self) -> None:
        anna = self.create(ANNA, "Anna Petrova", "anna_p")
        self.assertEqual(self.primary_of(ANNA), anna)

        self.transfer(ANNA, anna, BORIS)

        # She follows it now, and a chart she follows cannot be hers.
        listing = self.listing(ANNA)
        self.assertIsNone(listing["primary_profile_id"])
        self.assertIsNone(self.stored_primary(ANNA))
        self.assertEqual([(p["profile_id"], p["is_own"]) for p in listing["profiles"]], [(anna, False)])

    def test_giving_away_another_chart_keeps_your_own(self) -> None:
        anna = self.create(ANNA, "Anna Petrova", "anna_p")
        gift = self.create(ANNA, "Boris Ivanov", "boris_i")

        self.transfer(ANNA, gift, BORIS)

        self.assertEqual(self.primary_of(ANNA), anna)

    def test_accepting_reports_the_recipients_own_chart(self) -> None:
        boris = self.create(BORIS, "Boris Ivanov", "boris_i")
        gift = self.create(ANNA, "Boris's son", "boris_son")

        accepted = self.transfer(ANNA, gift, BORIS)

        self.assertEqual(accepted["primary_profile_id"], boris)
        self.assertEqual(self.primary_of(BORIS), boris)

    def test_the_recipient_can_then_say_it_is_theirs(self) -> None:
        gift = self.create(ANNA, "Boris Ivanov", "boris_i")
        self.transfer(ANNA, gift, BORIS)

        response = self.as_user(BORIS).put("/api/v1/profiles/primary", json={"profile_id": gift})

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(self.primary_of(BORIS), gift)


class DeleteTests(PrimaryTestCase):
    def test_deleting_your_own_chart_clears_it(self) -> None:
        anna = self.create(ANNA, "Anna Petrova", "anna_p")
        self.create(ANNA, "Anna's mother", "anna_mom")

        response = self.as_user(ANNA).delete(f"/api/v1/profiles/{anna}")

        self.assertEqual(response.status_code, 200, response.text)
        self.assertIsNone(self.stored_primary(ANNA))
        self.assertIsNone(self.primary_of(ANNA))

    def test_a_chart_once_offered_to_someone_can_still_be_deleted(self) -> None:
        anna = self.create(ANNA, "Anna Petrova", "anna_p")
        invite = self.as_user(ANNA).post(f"/api/v1/profiles/{anna}/invite", json={"email": "someone@example.com"})
        self.assertEqual(invite.status_code, 200, invite.text)

        response = self.as_user(ANNA).delete(f"/api/v1/profiles/{anna}")

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(self.listing(ANNA)["profiles"], [])


class ListingTests(PrimaryTestCase):
    def test_the_listing_never_names_a_chart_the_account_does_not_own(self) -> None:
        self.create(ANNA, "Anna Petrova", "anna_p")
        boris = self.create(BORIS, "Boris Ivanov", "boris_i")
        self.as_user(ANNA).post(f"/api/v1/profiles/{boris}/follow")
        # What a transfer used to leave behind: a primary she only follows.
        self.store_primary(ANNA, boris)

        self.assertIsNone(self.primary_of(ANNA))


if __name__ == "__main__":
    unittest.main()
