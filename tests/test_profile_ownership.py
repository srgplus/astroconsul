"""Ownership checks on the profile routes that mutate a single profile."""

from __future__ import annotations

import unittest
from typing import Any

from fastapi.testclient import TestClient

from app.api.auth import get_current_user
from app.api.dependencies import get_repositories
from app.infrastructure.repositories.factory import RepositoryBundle
from app.main import create_app

OWNER_ID = "user_owner"
INTRUDER_ID = "user_intruder"
STRANGER_ID = "user_stranger"
PROFILE_ID = "profile_owned_by_owner"
STRANGER_PROFILE_ID = "profile_owned_by_stranger"


class FakeProfileRepository:
    """In-memory stand-in — only the methods these routes touch before doing work."""

    def __init__(self) -> None:
        self.profiles: dict[str, dict[str, Any]] = {
            PROFILE_ID: {
                "profile_id": PROFILE_ID,
                "profile_name": "Owner",
                "username": "owner",
                "user_id": OWNER_ID,
                "chart_id": "chart_test",
            },
            STRANGER_PROFILE_ID: {
                "profile_id": STRANGER_PROFILE_ID,
                "profile_name": "Stranger",
                "username": "stranger",
                "user_id": STRANGER_ID,
                "chart_id": "chart_test",
            },
        }
        self.deleted: list[str] = []
        self.primary: dict[str, str] = {}
        self.following: set[tuple[str, str]] = set()
        self.arrangement: dict[str, dict[str, list[str]]] = {}

    def load_profile(self, profile_id: str) -> dict[str, Any]:
        if profile_id not in self.profiles:
            raise FileNotFoundError(f"Natal profile not found: {profile_id}")
        return dict(self.profiles[profile_id])

    def delete_profile(self, profile_id: str) -> None:
        if profile_id not in self.profiles:
            raise FileNotFoundError(f"Natal profile not found: {profile_id}")
        del self.profiles[profile_id]
        self.deleted.append(profile_id)

    def set_primary_profile_id(self, user_id: str, profile_id: str) -> None:
        self.primary[user_id] = profile_id

    def is_following(self, user_id: str, profile_id: str) -> bool:
        return (user_id, profile_id) in self.following

    def resolve_profile_chart_id(self, profile_id: str) -> str:
        # No charts here — these tests only reach past the access check.
        raise FileNotFoundError(f"Chart not found for profile: {profile_id}")

    def list_summaries(self, *, user_id: str | None = None) -> list[dict[str, Any]]:
        return [dict(p) for p in self.profiles.values() if p["user_id"] == user_id]

    def list_followed(self, user_id: str) -> list[dict[str, Any]]:
        return [dict(self.profiles[pid]) for owner, pid in sorted(self.following) if owner == user_id]

    def get_primary_profile_id(self, user_id: str) -> str | None:
        return self.primary.get(user_id)

    def get_profile_arrangement(self, user_id: str) -> dict[str, list[str]]:
        return self.arrangement.get(user_id, {"favorite_profile_ids": [], "profile_order": []})

    def set_profile_arrangement(
        self, user_id: str, *, favorite_profile_ids: list[str], profile_order: list[str]
    ) -> None:
        self.arrangement[user_id] = {
            "favorite_profile_ids": favorite_profile_ids,
            "profile_order": profile_order,
        }


class ProfileRouteTestCase(unittest.TestCase):
    """Wires the profile routes to an in-memory repository and a chosen caller."""

    def setUp(self) -> None:
        self.repo = FakeProfileRepository()
        self.app = create_app()
        self.app.dependency_overrides[get_repositories] = lambda: RepositoryBundle(
            charts=None,  # type: ignore[arg-type]
            profiles=self.repo,  # type: ignore[arg-type]
            locations=None,  # type: ignore[arg-type]
        )
        self.client = TestClient(self.app)

    def tearDown(self) -> None:
        self.app.dependency_overrides.clear()

    def _authenticate_as(self, user_id: str) -> None:
        self.app.dependency_overrides[get_current_user] = lambda: {
            "user_id": user_id,
            "email": f"{user_id}@example.test",
        }


class DeleteProfileOwnershipTests(ProfileRouteTestCase):
    def test_owner_can_delete_own_profile(self) -> None:
        self._authenticate_as(OWNER_ID)

        response = self.client.delete(f"/api/v1/profiles/{PROFILE_ID}")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "deleted"})
        self.assertEqual(self.repo.deleted, [PROFILE_ID])

    def test_non_owner_gets_403_and_profile_survives(self) -> None:
        self._authenticate_as(INTRUDER_ID)

        response = self.client.delete(f"/api/v1/profiles/{PROFILE_ID}")

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["detail"], "Not your profile")
        self.assertEqual(self.repo.deleted, [])
        self.assertIn(PROFILE_ID, self.repo.profiles)

    def test_unknown_profile_id_gets_404(self) -> None:
        self._authenticate_as(OWNER_ID)

        response = self.client.delete("/api/v1/profiles/profile_does_not_exist")

        self.assertEqual(response.status_code, 404)
        self.assertEqual(self.repo.deleted, [])


class SetPrimaryProfileOwnershipTests(ProfileRouteTestCase):
    """PUT /profiles/primary writes only the caller's own record, but pinning
    someone else's profile as your primary is still not something to allow."""

    def _put_primary(self, profile_id: str):
        return self.client.put("/api/v1/profiles/primary", json={"profile_id": profile_id})

    def test_owner_can_set_own_profile_as_primary(self) -> None:
        self._authenticate_as(OWNER_ID)

        response = self._put_primary(PROFILE_ID)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.repo.primary, {OWNER_ID: PROFILE_ID})

    def test_non_owner_gets_403(self) -> None:
        self._authenticate_as(INTRUDER_ID)

        response = self._put_primary(PROFILE_ID)

        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.repo.primary, {})

    def test_unknown_profile_id_gets_404(self) -> None:
        self._authenticate_as(OWNER_ID)

        response = self._put_primary("profile_does_not_exist")

        self.assertEqual(response.status_code, 404)
        self.assertEqual(self.repo.primary, {})


class ReadableProfileRoutesTests(ProfileRouteTestCase):
    """The transit and synastry routes serve owned *and* followed profiles. An
    unknown id used to escape as an uncaught FileNotFoundError, i.e. a 500."""

    TIMELINE = "/api/v1/profiles/{pid}/transits/timeline?start_date=2026-01-01&end_date=2026-01-02&timezone=UTC"
    FORECAST = "/api/v1/profiles/{pid}/transits/forecast?timezone=UTC&days=1"

    def test_unknown_profile_id_gets_404_not_500(self) -> None:
        self._authenticate_as(OWNER_ID)
        missing = "profile_does_not_exist"

        for url in (self.TIMELINE.format(pid=missing), self.FORECAST.format(pid=missing)):
            with self.subTest(url=url):
                self.assertEqual(self.client.get(url).status_code, 404)

        report = self.client.post(
            f"/api/v1/profiles/{missing}/transits/report",
            json={"transit_date": "2026-01-01", "transit_time": "12:00:00", "timezone": "UTC"},
        )
        self.assertEqual(report.status_code, 404)

        synastry = self.client.post(
            f"/api/v1/profiles/{missing}/synastry",
            json={"partner_profile_id": PROFILE_ID},
        )
        self.assertEqual(synastry.status_code, 404)

    def test_stranger_gets_403(self) -> None:
        self._authenticate_as(INTRUDER_ID)

        response = self.client.get(self.FORECAST.format(pid=PROFILE_ID))

        self.assertEqual(response.status_code, 403)

    def test_follower_is_allowed_past_the_access_check(self) -> None:
        self._authenticate_as(INTRUDER_ID)
        self.repo.following.add((INTRUDER_ID, PROFILE_ID))

        response = self.client.get(self.FORECAST.format(pid=PROFILE_ID))

        # 404 comes from the fake repo holding no chart, i.e. from *past* the
        # access check — the point is that a follower is not turned away with 403.
        self.assertEqual(response.status_code, 404)


class ProfileArrangementTests(ProfileRouteTestCase):
    """PUT /profiles/arrangement stores the reader's Favourites group and card
    order. Unlike /primary it accepts followed profiles — starring somebody
    else's profile is your business — but only ids you have a card for, so one
    account cannot write another's profile ids into its own row."""

    def _put(self, favorites: list[str], order: list[str]):
        return self.client.put(
            "/api/v1/profiles/arrangement",
            json={"favorite_profile_ids": favorites, "profile_order": order},
        )

    def test_own_and_followed_profiles_are_stored(self) -> None:
        self._authenticate_as(OWNER_ID)
        self.repo.following.add((OWNER_ID, STRANGER_PROFILE_ID))

        response = self._put([STRANGER_PROFILE_ID], [PROFILE_ID, STRANGER_PROFILE_ID])

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            self.repo.arrangement[OWNER_ID],
            {
                "favorite_profile_ids": [STRANGER_PROFILE_ID],
                "profile_order": [PROFILE_ID, STRANGER_PROFILE_ID],
            },
        )

    def test_ids_the_caller_has_no_card_for_are_dropped(self) -> None:
        self._authenticate_as(OWNER_ID)

        # Not followed, so not on this caller's list, plus an id for nothing.
        response = self._put(
            [STRANGER_PROFILE_ID, PROFILE_ID],
            ["profile_does_not_exist", PROFILE_ID],
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            self.repo.arrangement[OWNER_ID],
            {"favorite_profile_ids": [PROFILE_ID], "profile_order": [PROFILE_ID]},
        )

    def test_repeated_ids_are_collapsed(self) -> None:
        self._authenticate_as(OWNER_ID)

        self._put([PROFILE_ID, PROFILE_ID], [PROFILE_ID, PROFILE_ID])

        self.assertEqual(
            self.repo.arrangement[OWNER_ID],
            {"favorite_profile_ids": [PROFILE_ID], "profile_order": [PROFILE_ID]},
        )

    def test_listing_leaves_out_ids_that_are_no_longer_on_the_list(self) -> None:
        self._authenticate_as(OWNER_ID)
        # A star that outlived the profile it named: followed once, since dropped.
        self.repo.arrangement[OWNER_ID] = {
            "favorite_profile_ids": [STRANGER_PROFILE_ID, PROFILE_ID],
            "profile_order": [STRANGER_PROFILE_ID],
        }

        payload = self.client.get("/api/v1/profiles").json()

        self.assertEqual(payload["favorite_profile_ids"], [PROFILE_ID])
        self.assertEqual(payload["profile_order"], [])


if __name__ == "__main__":
    unittest.main()
