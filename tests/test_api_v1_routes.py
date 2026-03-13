from __future__ import annotations

import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import create_app


class ApiV1RouteTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(create_app())

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


if __name__ == "__main__":
    unittest.main()
