from __future__ import annotations

import unittest
from datetime import datetime, timezone

from chart_builder import build_chart, save_chart
from transit_builder import MAX_TRANSIT_ORB, build_transit_report
from transit_timing_engine import aspect_error_at


def parse_utc(value: str | None) -> datetime | None:
    if value is None:
        return None

    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def natal_longitude_for(report: dict[str, object], object_id: str) -> float:
    for row in report["natal_positions"]:
        if row["id"] == object_id:
            return float(row["longitude"])

    for row in report["angle_positions"]:
        if row["id"] == object_id:
            return float(row["longitude"])

    raise AssertionError(f"Missing natal object in report: {object_id}")


class TransitTimingEngineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        chart = build_chart(1991, 7, 28, 22.1, 52.13472, 23.65694)
        cls.chart_id, cls.chart_path = save_chart(chart, chart_id="chart_1991_07_28_2206")
        cls.transit_datetime_utc = datetime(2026, 3, 9, 3, 6, 1, tzinfo=timezone.utc)
        cls.report = build_transit_report(
            cls.chart_path.name,
            "2026-03-09",
            "03:06:01",
            include_timing=True,
        )

    def test_timed_aspects_include_timing_block(self) -> None:
        first_aspect = self.report["active_aspects"][0]
        self.assertIn("timing", first_aspect)
        self.assertIn("status", first_aspect["timing"])
        self.assertIn("peak_orb", first_aspect["timing"])

    def test_known_venus_saturn_aspect_has_ordered_timing(self) -> None:
        aspect = next(
            item
            for item in self.report["active_aspects"]
            if item["transit_object"] == "Venus"
            and item["natal_object"] == "Saturn"
            and item["aspect"] == "sextile"
        )
        timing = aspect["timing"]

        start_utc = parse_utc(timing["start_utc"])
        peak_utc = parse_utc(timing["peak_utc"])
        end_utc = parse_utc(timing["end_utc"])

        self.assertIsNotNone(start_utc)
        self.assertIsNotNone(peak_utc)
        self.assertIsNotNone(end_utc)
        self.assertLessEqual(start_utc, peak_utc)
        self.assertLessEqual(peak_utc, end_utc)
        self.assertLessEqual(float(timing["peak_orb"]), float(aspect["orb"]))
        self.assertGreater(float(timing["duration_hours"]), 0)
        natal_longitude = natal_longitude_for(self.report, str(aspect["natal_object"]))

        start_error = aspect_error_at(
            str(aspect["transit_object"]),
            natal_longitude,
            int(aspect["exact_angle"]),
            start_utc,
        )
        end_error = aspect_error_at(
            str(aspect["transit_object"]),
            natal_longitude,
            int(aspect["exact_angle"]),
            end_utc,
        )
        self.assertLessEqual(start_error, MAX_TRANSIT_ORB + 0.02)
        self.assertLessEqual(end_error, MAX_TRANSIT_ORB + 0.02)

    def test_status_matches_current_time_against_peak(self) -> None:
        aspect = next(
            item
            for item in self.report["active_aspects"]
            if item["transit_object"] == "Venus"
            and item["natal_object"] == "Saturn"
            and item["aspect"] == "sextile"
        )
        peak_utc = parse_utc(aspect["timing"]["peak_utc"])
        self.assertIsNotNone(peak_utc)

        delta_seconds = (self.transit_datetime_utc - peak_utc).total_seconds()
        if abs(delta_seconds) <= 60:
            expected_status = "exact"
        elif delta_seconds < 0:
            expected_status = "applying"
        else:
            expected_status = "separating"

        self.assertEqual(aspect["timing"]["status"], expected_status)

    def test_exactness_fields_are_consistent(self) -> None:
        for aspect in self.report["active_aspects"]:
            timing = aspect["timing"]
            exact_utc = timing["exact_utc"]

            if exact_utc is None:
                self.assertFalse(timing["will_perfect"])
                continue

            self.assertTrue(timing["will_perfect"])
            self.assertLessEqual(float(timing["peak_orb"]), 0.01)
            self.assertEqual(exact_utc, timing["peak_utc"])


if __name__ == "__main__":
    unittest.main()
