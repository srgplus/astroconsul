from __future__ import annotations

import json
import unittest
from datetime import UTC, datetime
from unittest.mock import patch

from chart_builder import CHARTS_DIR
from natal_profiles import PROFILES_DIR, create_profile, profile_path
from server import (
    NatalChartCreateRequest,
    NatalProfileUpsertRequest,
    TransitReportRequest,
    TransitTimelineRequest,
    calculate_chart,
    create_natal_chart,
    create_natal_profile,
    natal_profile_detail,
    transit_report,
    transit_timeline,
    update_natal_profile,
)


def cleanup_profile(username: str) -> None:
    if not PROFILES_DIR.exists():
        return

    for path in PROFILES_DIR.glob("profile_*.json"):
        payload = json.loads(path.read_text(encoding="utf-8"))
        if payload.get("username") == username:
            path.unlink()


def cleanup_chart(chart_id: str) -> None:
    chart_path = CHARTS_DIR / f"{chart_id}.json"
    if chart_path.exists():
        chart_path.unlink()


class ServerRouteTests(unittest.TestCase):
    def setUp(self) -> None:
        cleanup_profile("transit_profile_route")
        cleanup_profile("transit_snapshot_route")
        cleanup_profile("stateless_transit_route")
        cleanup_profile("chart_cleanup_route")
        cleanup_chart("chart_test_update_old")
        cleanup_chart("chart_test_update_new")
        cleanup_chart("chart_test_update_legacy")

    def tearDown(self) -> None:
        cleanup_profile("transit_profile_route")
        cleanup_profile("transit_snapshot_route")
        cleanup_profile("stateless_transit_route")
        cleanup_profile("chart_cleanup_route")
        cleanup_chart("chart_test_update_old")
        cleanup_chart("chart_test_update_new")
        cleanup_chart("chart_test_update_legacy")

    def test_create_natal_chart_accepts_local_datetime_contract(self) -> None:
        response = create_natal_chart(
            NatalChartCreateRequest(
                name="Serge",
                birth_date="1991-07-29",
                birth_time="01:06:00",
                timezone="Europe/Minsk",
                location_name="Brest, Belarus",
                latitude=52.13472,
                longitude=23.65694,
                time_basis="local",
            )
        )

        self.assertEqual(response["chart_id"], "chart_1991_07_28_2206")
        self.assertEqual(response["utc_birth_datetime"], "1991-07-28T22:06:00Z")
        self.assertTrue(str(response["local_birth_datetime"]).startswith("1991-07-29T01:06:00"))
        self.assertEqual(response["natal_aspect_count"], len(response["natal_aspects"]))
        self.assertEqual(len(response["natal_positions"]), 19)
        self.assertEqual(response["natal_positions"][0]["id"], "Sun")
        self.assertEqual(response["natal_positions"][0]["house"], 4)
        self.assertEqual(response["angle_positions"][0]["id"], "ASC")
        self.assertEqual(response["natal_summary"]["sun"], "Leo 5°19'44\"")

    def test_raw_natal_endpoint_includes_normalized_positions(self) -> None:
        response = calculate_chart(1991, 7, 28, 22.1, 52.13472, 23.65694)
        positions_by_id = {position["id"]: position for position in response["natal_positions"]}

        self.assertEqual(len(response["natal_positions"]), 19)
        self.assertEqual(positions_by_id["Moon"]["house"], 11)
        self.assertIn(positions_by_id["Vertex"]["house"], range(1, 13))
        self.assertEqual([position["id"] for position in response["angle_positions"]], ["ASC", "MC"])
        self.assertIn("asc", response["natal_summary"])

    def test_transit_report_accepts_local_datetime_contract(self) -> None:
        report = transit_report(
            TransitReportRequest(
                chart_id="chart_1991_07_28_2206",
                transit_date="2026-03-09",
                transit_time="06:06:01",
                timezone="Europe/Warsaw",
            )
        )

        snapshot = report["snapshot"]

        self.assertEqual(snapshot["chart_id"], "chart_1991_07_28_2206")
        self.assertEqual(snapshot["chart_filename"], "chart_1991_07_28_2206.json")
        self.assertEqual(snapshot["transit_timezone"], "Europe/Warsaw")
        self.assertEqual(snapshot["transit_utc_datetime"], "2026-03-09T05:06:01Z")
        self.assertEqual(snapshot["ephemeris_version"], "2.10.03")
        self.assertEqual(
            [position["id"] for position in report["transit_positions"][:13]],
            [
                "Moon",
                "Sun",
                "Mercury",
                "Venus",
                "Mars",
                "Jupiter",
                "Saturn",
                "Uranus",
                "Neptune",
                "Pluto",
                "North Node",
                "South Node",
                "Lilith",
            ],
        )
        self.assertEqual(len(report["natal_positions"]), 19)
        self.assertEqual(report["natal_positions"][0]["sign"], "Leo")
        self.assertEqual([position["id"] for position in report["angle_positions"]], ["ASC", "MC"])
        self.assertEqual(report["angle_positions"][0]["sign"], "Gemini")
        self.assertGreater(len(report["active_aspects"]), 0)
        self.assertTrue(all(float(aspect["orb"]) <= 1.99 for aspect in report["active_aspects"]))
        self.assertNotIn("timing", report["active_aspects"][0])

    @patch("server.resolve_location_name")
    def test_transit_report_can_resolve_transit_location_and_add_location_points(self, resolve_location_name) -> None:
        resolve_location_name.return_value = {
            "location_name": "Los Angeles",
            "resolved_name": "Los Angeles, California, United States",
            "latitude": 34.0522,
            "longitude": -118.2437,
            "timezone": "America/Los_Angeles",
            "source": "test",
        }

        report = transit_report(
            TransitReportRequest(
                chart_id="chart_1991_07_28_2206",
                transit_date="2026-03-09",
                transit_time="01:19:00",
                location_name="Los Angeles",
            )
        )

        snapshot = report["snapshot"]

        self.assertEqual(snapshot["transit_timezone"], "America/Los_Angeles")
        self.assertEqual(snapshot["transit_location_name"], "Los Angeles, California, United States")
        self.assertEqual(snapshot["transit_latitude"], 34.0522)
        self.assertEqual(snapshot["transit_longitude"], -118.2437)
        self.assertIn("Part of Fortune", [position["id"] for position in report["transit_positions"]])
        self.assertIn("Vertex", [position["id"] for position in report["transit_positions"]])

    def test_transit_report_can_include_timing(self) -> None:
        report = transit_report(
            TransitReportRequest(
                chart_id="chart_1991_07_28_2206",
                transit_date="2026-03-09",
                transit_time="06:06:01",
                timezone="Europe/Warsaw",
                include_timing=True,
            )
        )

        timing = report["active_aspects"][0]["timing"]
        self.assertIn("peak_utc", timing)
        self.assertIn("status", timing)
        self.assertIn(timing["status"], {"applying", "exact", "separating"})

    def test_transit_routes_accept_profile_id(self) -> None:
        profile = create_natal_profile(
            NatalProfileUpsertRequest(
                profile_name="Transit Route Profile",
                username="transit_profile_route",
                name="Serge",
                birth_date="1991-07-29",
                birth_time="01:06:00",
                timezone="Europe/Minsk",
                location_name="Brest, Belarus",
                latitude=52.13472,
                longitude=23.65694,
                time_basis="local",
            )
        )["profile"]

        report = transit_report(
            TransitReportRequest(
                profile_id=profile["profile_id"],
                transit_date="2026-03-09",
                transit_time="06:06:01",
                timezone="Europe/Warsaw",
            )
        )
        self.assertEqual(report["snapshot"]["profile_id"], profile["profile_id"])
        self.assertEqual(report["snapshot"]["chart_id"], "chart_1991_07_28_2206")

        timeline = transit_timeline(
            TransitTimelineRequest(
                profile_id=profile["profile_id"],
                start_date="2026-03-11",
                end_date="2026-04-10",
                timezone="America/Los_Angeles",
            )
        )
        self.assertIn("timeline", timeline)
        self.assertGreater(len(timeline["timeline"]), 0)

    @patch("server.resolve_location_name")
    def test_transit_report_persists_single_latest_snapshot_per_profile(self, resolve_location_name) -> None:
        resolve_location_name.return_value = {
            "location_name": "Los Angeles",
            "resolved_name": "Los Angeles, California, United States",
            "latitude": 34.0522,
            "longitude": -118.2437,
            "timezone": "America/Los_Angeles",
            "source": "test",
        }
        fixed_now = datetime(2026, 3, 13, 12, 0, 0, tzinfo=UTC)

        profile = create_natal_profile(
            NatalProfileUpsertRequest(
                profile_name="Transit Snapshot Route",
                username="transit_snapshot_route",
                name="Serge",
                birth_date="1991-07-29",
                birth_time="01:06:00",
                timezone="Europe/Minsk",
                location_name="Brest, Belarus",
                latitude=52.13472,
                longitude=23.65694,
                time_basis="local",
            )
        )["profile"]
        profile_file = profile_path(profile["profile_id"])

        with patch("natal_profiles.current_utc_datetime", return_value=fixed_now):
            transit_report(
                TransitReportRequest(
                    profile_id=profile["profile_id"],
                    transit_date="2026-03-14",
                    transit_time="01:19:00",
                    location_name="Los Angeles",
                )
            )

            first_saved_profile = json.loads(profile_file.read_text(encoding="utf-8"))
            self.assertEqual(
                first_saved_profile["latest_transit"],
                {
                    "transit_date": "2026-03-14",
                    "transit_time": "01:19:00",
                    "timezone": "America/Los_Angeles",
                    "location_name": "Los Angeles, California, United States",
                    "latitude": 34.0522,
                    "longitude": -118.2437,
                    "updated_at": "2026-03-13T12:00:00Z",
                },
            )

            transit_report(
                TransitReportRequest(
                    profile_id=profile["profile_id"],
                    transit_date="2026-03-15",
                    transit_time="09:45:00",
                    timezone="Asia/Tokyo",
                )
            )

            detail = natal_profile_detail(profile["profile_id"])

        second_saved_profile = json.loads(profile_file.read_text(encoding="utf-8"))
        self.assertEqual(
            second_saved_profile["latest_transit"],
            {
                "transit_date": "2026-03-15",
                "transit_time": "09:45:00",
                "timezone": "Asia/Tokyo",
                "location_name": None,
                "latitude": None,
                "longitude": None,
                "updated_at": "2026-03-13T12:00:00Z",
            },
        )
        self.assertNotIn("transit_history", second_saved_profile)
        self.assertEqual(detail["profile"]["latest_transit"], second_saved_profile["latest_transit"])

    def test_transit_report_with_chart_id_only_does_not_mutate_profile_file(self) -> None:
        profile = create_natal_profile(
            NatalProfileUpsertRequest(
                profile_name="Stateless Transit Route",
                username="stateless_transit_route",
                name="Serge",
                birth_date="1991-07-29",
                birth_time="01:06:00",
                timezone="Europe/Minsk",
                location_name="Brest, Belarus",
                latitude=52.13472,
                longitude=23.65694,
                time_basis="local",
            )
        )["profile"]
        profile_file = profile_path(profile["profile_id"])
        original_payload = profile_file.read_text(encoding="utf-8")

        transit_report(
            TransitReportRequest(
                chart_id=profile["chart_id"],
                transit_date="2026-03-14",
                transit_time="06:06:01",
                timezone="Europe/Warsaw",
            )
        )

        self.assertEqual(profile_file.read_text(encoding="utf-8"), original_payload)

    def test_update_profile_removes_old_unreferenced_chart_file(self) -> None:
        old_chart_id = "chart_test_update_old"
        new_chart_id = "chart_test_update_new"
        old_chart_path = CHARTS_DIR / f"{old_chart_id}.json"
        old_chart_path.write_text(
            json.dumps({"birth_input": {"name": "Chart Cleanup Route"}}, indent=2, sort_keys=True),
            encoding="utf-8",
        )
        profile = create_profile("Chart Cleanup Route", "chart_cleanup_route", old_chart_id)

        new_chart_path = CHARTS_DIR / f"{new_chart_id}.json"
        new_chart_payload = {
            "birth_input": {
                "name": "Chart Cleanup Route",
                "location_name": "Brest, Belarus",
                "timezone": "Europe/Minsk",
                "local_birth_datetime": "1991-07-29T01:06:00+03:00",
                "utc_birth_datetime": "1991-07-28T22:06:00Z",
            },
            "angles": {},
            "natal_aspects": [],
            "natal_positions": [],
            "houses": [],
            "angle_positions": [],
            "natal_summary": {},
        }

        with patch("server.build_chart_from_request", return_value=(new_chart_id, new_chart_path, new_chart_payload)):
            response = update_natal_profile(
                profile["profile_id"],
                NatalProfileUpsertRequest(
                    profile_name="Chart Cleanup Route",
                    username="chart_cleanup_route",
                    name="Chart Cleanup Route",
                    birth_date="1991-07-29",
                    birth_time="01:06:00",
                    timezone="Europe/Minsk",
                    location_name="Brest, Belarus",
                    latitude=52.13472,
                    longitude=23.65694,
                    time_basis="local",
                ),
            )

        self.assertEqual(response["profile"]["chart_id"], new_chart_id)
        self.assertFalse(old_chart_path.exists())

    def test_update_profile_response_upgrades_legacy_chart_payload_before_returning(self) -> None:
        legacy_chart_id = "chart_test_update_legacy"
        legacy_chart_path = CHARTS_DIR / f"{legacy_chart_id}.json"
        cleanup_chart(legacy_chart_id)
        old_chart_id = "chart_test_update_old"
        cleanup_chart(old_chart_id)

        old_chart_path = CHARTS_DIR / f"{old_chart_id}.json"
        old_chart_path.write_text(
            json.dumps({"birth_input": {"name": "Legacy Upgrade Route"}}, indent=2, sort_keys=True),
            encoding="utf-8",
        )
        profile = create_profile("Legacy Upgrade Route", "chart_cleanup_route", old_chart_id)

        legacy_chart_payload = {
            "birth_data": {
                "year": 1991,
                "month": 7,
                "day": 28,
                "hour": 22.1,
                "latitude": 52.13472,
                "longitude": 23.65694,
                "time_basis": "UT",
            },
            "birth_input": {
                "name": "Legacy Upgrade Route",
                "birth_date": "1991-07-29",
                "birth_time": "01:06:00",
                "timezone": "Europe/Minsk",
                "location_name": "Brest, Belarus",
                "local_birth_datetime": "1991-07-29T01:06:00+03:00",
                "utc_birth_datetime": "1991-07-28T22:06:00Z",
                "latitude": 52.13472,
                "longitude": 23.65694,
                "time_basis": "local",
            },
            "angles": {
                "asc": 62.240116,
                "mc": 312.643635,
                "vertex": 122.022261,
            },
            "natal_aspects": [],
            "natal_positions": [
                {"id": "Sun"},
                {"id": "Moon"},
                {"id": "Mercury"},
                {"id": "Venus"},
                {"id": "Mars"},
                {"id": "Jupiter"},
                {"id": "Saturn"},
                {"id": "Uranus"},
                {"id": "Neptune"},
                {"id": "Pluto"},
            ],
            "houses": [62.240116, 94.0, 126.0, 158.0, 190.0, 222.0, 242.240116, 274.0, 306.0, 338.0, 10.0, 42.0],
            "angle_positions": [],
            "natal_summary": {
                "sun": "Leo 5°19'44\"",
                "moon": "Aquarius 29°14'52\"",
                "asc": "Gemini 2°14'24\"",
            },
            "planets": {
                "Sun": 125.328941,
                "Moon": 329.247842,
                "Mercury": 151.922789,
                "Venus": 157.090491,
                "Mars": 158.278967,
                "Jupiter": 140.156994,
                "Saturn": 303.366013,
                "Uranus": 280.873148,
                "Neptune": 284.830152,
                "Pluto": 227.563338,
            },
        }
        legacy_chart_path.write_text(json.dumps(legacy_chart_payload, indent=2, sort_keys=True), encoding="utf-8")

        mock_return = (legacy_chart_id, legacy_chart_path, legacy_chart_payload)
        with patch("server.build_chart_from_request", return_value=mock_return):
            response = update_natal_profile(
                profile["profile_id"],
                NatalProfileUpsertRequest(
                    profile_name="Legacy Upgrade Route",
                    username="chart_cleanup_route",
                    name="Legacy Upgrade Route",
                    birth_date="1991-07-29",
                    birth_time="01:06:00",
                    timezone="Europe/Minsk",
                    location_name="Brest, Belarus",
                    latitude=52.13472,
                    longitude=23.65694,
                    time_basis="local",
                ),
            )

        object_ids = [position["id"] for position in response["chart"]["natal_positions"]]
        self.assertEqual(len(object_ids), 19)
        self.assertEqual(object_ids[:3], ["Sun", "ASC", "MC"])
        self.assertIn("Chiron", object_ids)
        self.assertIn("Vertex", object_ids)
        self.assertEqual([position["id"] for position in response["chart"]["angle_positions"]], ["ASC", "MC"])

        cleanup_chart(legacy_chart_id)


if __name__ == "__main__":
    unittest.main()
