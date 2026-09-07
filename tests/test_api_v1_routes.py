from __future__ import annotations

import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import create_app

# profiles/*.json is gitignored (it is real user data), so these two cases only
# have something to assert against on a developer machine that has run the app.
HAS_LOCAL_PROFILES = any(Path("profiles").glob("profile_*.json"))
NEEDS_PROFILES = "needs local profile fixtures in profiles/"


class ApiV1RouteTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(create_app())

    @unittest.skipUnless(HAS_LOCAL_PROFILES, NEEDS_PROFILES)
    def test_profiles_route_matches_legacy_listing_contract(self) -> None:
        response = self.client.get("/api/v1/profiles")

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertIn("profiles", payload)
        self.assertGreater(len(payload["profiles"]), 0)
        self.assertIn("profile_id", payload["profiles"][0])

    @patch("app.api.handlers.resolve_location_name")
    def test_location_resolve_route_uses_versioned_contract(self, resolve_location_name) -> None:
        resolve_location_name.return_value = {
            "location_name": "Warsaw",
            "resolved_name": "Warsaw, Masovian Voivodeship, Poland",
            "latitude": 52.2297,
            "longitude": 21.0122,
            "timezone": "Europe/Warsaw",
            "source": "test",
        }

        response = self.client.post("/api/v1/locations/resolve", json={"location_name": "Warsaw"})

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["timezone"], "Europe/Warsaw")
        self.assertEqual(payload["resolved_name"], "Warsaw, Masovian Voivodeship, Poland")

    @unittest.skipUnless(HAS_LOCAL_PROFILES, NEEDS_PROFILES)
    def test_profile_scoped_transit_routes_generate_report_and_timeline(self) -> None:
        profiles_response = self.client.get("/api/v1/profiles")
        profile_id = profiles_response.json()["profiles"][0]["profile_id"]

        report_response = self.client.post(
            f"/api/v1/profiles/{profile_id}/transits/report",
            json={
                "transit_date": "2026-03-09",
                "transit_time": "06:06:01",
                "timezone": "Europe/Warsaw",
                "include_timing": False,
            },
        )
        timeline_response = self.client.get(
            f"/api/v1/profiles/{profile_id}/transits/timeline",
            params={
                "start_date": "2026-03-11",
                "end_date": "2026-04-10",
                "timezone": "America/Los_Angeles",
            },
        )

        self.assertEqual(report_response.status_code, 200)
        self.assertEqual(timeline_response.status_code, 200)
        self.assertIn("snapshot", report_response.json())
        self.assertIn("timeline", timeline_response.json())
        self.assertGreater(len(timeline_response.json()["timeline"]), 0)


class AccountRouteTests(unittest.TestCase):
    """The iOS app's Settings -> "Manage account" points its WebView here.

    Apple reviews account deletion under 5.1.1(v): if this route stops serving
    the SPA the button lands on a 404 and the deletion flow is unreachable from
    the app, which is exactly what got flagged.
    """

    def setUp(self) -> None:
        self.client = TestClient(create_app())

    def test_account_route_answers_as_the_spa_root_and_not_as_a_missing_page(
        self,
    ) -> None:
        # Asked of the app rather than read off `app.routes`, whose entries are
        # not the same shape across FastAPI versions.
        home = self.client.get("/")
        account = self.client.get("/account")
        missing = self.client.get("/not-a-route-in-this-app")

        # The same document as the SPA root, whichever state the build is in:
        # CI's backend job never builds the frontend, so both are the "not
        # built yet" 404 there and the SPA on a machine that has run
        # `npm run build`.
        self.assertEqual(account.status_code, home.status_code)
        self.assertEqual(account.text, home.text)
        # And distinguishable from a bare "Not Found", which is what /account
        # would answer if the route went away.
        self.assertNotEqual(account.text, missing.text)

    @unittest.skipUnless(
        (Path("frontend") / "dist" / "index.html").exists(),
        "needs a built frontend in frontend/dist",
    )
    def test_account_route_serves_the_spa(self) -> None:
        response = self.client.get("/account")

        self.assertEqual(response.status_code, 200)
        self.assertIn("text/html", response.headers["content-type"])


if __name__ == "__main__":
    unittest.main()
