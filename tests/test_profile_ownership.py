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
PROFILE_ID = "profile_owned_by_owner"


class FakeProfileRepository:
    """In-memory stand-in — only the methods the delete route touches."""

    def __init__(self) -> None:
        self.profiles: dict[str, dict[str, Any]] = {
            PROFILE_ID: {
                "profile_id": PROFILE_ID,
                "user_id": OWNER_ID,
                "chart_id": "chart_test",
            },
        }
        self.deleted: list[str] = []

    def load_profile(self, profile_id: str) -> dict[str, Any]:
        if profile_id not in self.profiles:
            raise FileNotFoundError(f"Natal profile not found: {profile_id}")
        return dict(self.profiles[profile_id])

    def delete_profile(self, profile_id: str) -> None:
        if profile_id not in self.profiles:
            raise FileNotFoundError(f"Natal profile not found: {profile_id}")
        del self.profiles[profile_id]
        self.deleted.append(profile_id)


class DeleteProfileOwnershipTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
