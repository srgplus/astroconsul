from __future__ import annotations

import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException

from location_service import LocationResolutionError, resolve_location_name
from server import LocationResolveRequest, NatalChartCreateRequest, create_natal_chart, resolve_location


def fake_chart(*, birth_input: dict[str, object] | None = None) -> dict[str, object]:
    return {
        "julian_day": 2448466.42083333,
        "angles": {"asc": 62.239921, "mc": 299.085652},
        "house_system": "Placidus",
        "natal_aspects": [],
        "birth_input": birth_input,
        "planets": {},
        "natal_positions": [],
        "houses": [],
        "angle_positions": [],
    }


class LocationResolutionTests(unittest.TestCase):
    def tearDown(self) -> None:
        resolve_location_name.cache_clear()

    def test_resolving_moscow_returns_expected_timezone(self) -> None:
        with (
            patch(
                "location_service.geocode_place_name",
                return_value={
                    "resolved_name": "Moscow, Russia",
                    "latitude": 55.7558,
                    "longitude": 37.6173,
                    "source": "OpenStreetMap Nominatim",
                },
            ),
            patch("location_service.lookup_timezone_name", return_value="Europe/Moscow"),
        ):
            resolved = resolve_location_name("Moscow")

        self.assertEqual(resolved["resolved_name"], "Moscow, Russia")
        self.assertAlmostEqual(resolved["latitude"], 55.7558, places=3)
        self.assertAlmostEqual(resolved["longitude"], 37.6173, places=3)
        self.assertEqual(resolved["timezone"], "Europe/Moscow")

    def test_resolving_warsaw_returns_expected_timezone(self) -> None:
        with (
            patch(
                "location_service.geocode_place_name",
                return_value={
                    "resolved_name": "Warsaw, Masovian Voivodeship, Poland",
                    "latitude": 52.2297,
                    "longitude": 21.0122,
                    "source": "OpenStreetMap Nominatim",
                },
            ),
            patch("location_service.lookup_timezone_name", return_value="Europe/Warsaw"),
        ):
            resolved = resolve_location_name("Warsaw")

        self.assertEqual(resolved["timezone"], "Europe/Warsaw")

    def test_invalid_location_returns_http_400(self) -> None:
        with patch(
            "server.resolve_location_name",
            side_effect=LocationResolutionError(
                "Could not resolve this location. Please check spelling or enter coordinates manually."
            ),
        ):
            with self.assertRaises(HTTPException) as context:
                resolve_location(LocationResolveRequest(location_name="zzzz-invalid-place"))

        self.assertEqual(context.exception.status_code, 400)
        self.assertIn("Could not resolve this location", context.exception.detail)

    def test_create_natal_uses_current_payload_coordinates(self) -> None:
        def build_chart_stub(year, month, day, hour, lat, lon, birth_input=None):  # type: ignore[no-untyped-def]
            self.assertAlmostEqual(lat, 55.7558, places=4)
            self.assertAlmostEqual(lon, 37.6173, places=4)
            return fake_chart(birth_input=birth_input)

        with (
            patch("server.build_chart", side_effect=build_chart_stub) as build_chart_mock,
            patch("server.save_chart", return_value=("chart_1991_07_28_2206", Path("/tmp/chart_1991_07_28_2206.json"))),
        ):
            response = create_natal_chart(
                NatalChartCreateRequest(
                    name="Serge",
                    birth_date="1991-07-29",
                    birth_time="01:06:00",
                    timezone="Europe/Moscow",
                    location_name="Moscow",
                    latitude=55.7558,
                    longitude=37.6173,
                    time_basis="local",
                )
            )

        self.assertTrue(build_chart_mock.called)
        self.assertEqual(response["birth_input"]["timezone"], "Europe/Moscow")
        self.assertEqual(response["birth_input"]["latitude"], 55.7558)
        self.assertEqual(response["birth_input"]["longitude"], 37.6173)

    def test_manual_override_values_still_flow_into_chart_creation(self) -> None:
        def build_chart_stub(year, month, day, hour, lat, lon, birth_input=None):  # type: ignore[no-untyped-def]
            self.assertAlmostEqual(lat, 55.7, places=3)
            self.assertAlmostEqual(lon, 37.6, places=3)
            return fake_chart(birth_input=birth_input)

        with (
            patch("server.build_chart", side_effect=build_chart_stub) as build_chart_mock,
            patch("server.save_chart", return_value=("chart_1991_07_28_2206", Path("/tmp/chart_1991_07_28_2206.json"))),
        ):
            response = create_natal_chart(
                NatalChartCreateRequest(
                    name="Serge",
                    birth_date="1991-07-29",
                    birth_time="01:06:00",
                    timezone="UTC",
                    location_name="Moscow",
                    latitude=55.7,
                    longitude=37.6,
                    time_basis="local",
                )
            )

        self.assertTrue(build_chart_mock.called)
        self.assertEqual(response["birth_input"]["timezone"], "UTC")
        self.assertEqual(response["birth_input"]["latitude"], 55.7)
        self.assertEqual(response["birth_input"]["longitude"], 37.6)


if __name__ == "__main__":
    unittest.main()
