from __future__ import annotations

import unittest
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from chart_builder import build_chart, save_chart
from server import TransitTimelineRequest, transit_timeline
from transit_timeline import TIMELINE_STEP, build_transit_timeline, parse_utc_datetime


class TransitTimelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        chart = build_chart(1991, 7, 28, 22.1, 52.13472, 23.65694)
        cls.chart_id, cls.chart_path = save_chart(chart, chart_id="chart_1991_07_28_2206")
        cls.timezone_name = "America/Los_Angeles"
        tzinfo = ZoneInfo(cls.timezone_name)
        cls.range_start_utc = datetime.combine(date(2026, 3, 11), time.min, tzinfo=tzinfo).astimezone(UTC)
        cls.range_end_utc = datetime.combine(
            date(2026, 4, 10),
            time(hour=23, minute=59, second=59),
            tzinfo=tzinfo,
        ).astimezone(UTC)
        cls.timeline = build_transit_timeline(
            cls.chart_id,
            date(2026, 3, 11),
            date(2026, 4, 10),
            cls.timezone_name,
        )

    def test_daily_sampling_still_returns_expected_future_items(self) -> None:
        self.assertEqual(TIMELINE_STEP, timedelta(days=1))
        self.assertGreater(len(self.timeline), 0)
        self.assertTrue(
            any(
                item["transit"] == "Mars" and item["natal"] == "Venus" and item["aspect"] == "opposition"
                for item in self.timeline
            )
        )

    def test_timeline_adds_display_utc_and_route_returns_payload(self) -> None:
        first_item = self.timeline[0]
        self.assertIn("display_utc", first_item)
        self.assertIsNotNone(parse_utc_datetime(first_item["display_utc"]))

        response = transit_timeline(
            TransitTimelineRequest(
                chart_id=self.chart_id,
                start_date="2026-03-11",
                end_date="2026-04-10",
                timezone=self.timezone_name,
            )
        )

        self.assertIn("timeline", response)
        self.assertGreater(len(response["timeline"]), 0)
        self.assertIn("display_utc", response["timeline"][0])

    def test_timeline_keeps_exact_field_but_without_timing_calculation(self) -> None:
        self.assertTrue(all(item["exact_utc"] is None for item in self.timeline))

    def test_timeline_excludes_transit_moon_but_keeps_natal_moon(self) -> None:
        self.assertTrue(all(item["transit"] != "Moon" for item in self.timeline))
        self.assertTrue(any(item["natal"] == "Moon" and item["transit"] != "Moon" for item in self.timeline))

    def test_timeline_chooses_earliest_valid_future_display_moment(self) -> None:
        item = next(
            record
            for record in self.timeline
            if record["transit"] == "Jupiter" and record["natal"] == "Neptune" and record["aspect"] == "opposition"
        )

        self.assertIsNone(item["exact_utc"])
        self.assertEqual(item["display_utc"], self.range_start_utc.isoformat(timespec="seconds").replace("+00:00", "Z"))

    def test_timeline_is_sorted_by_display_utc(self) -> None:
        display_moments = [parse_utc_datetime(item["display_utc"]) for item in self.timeline]
        self.assertEqual(display_moments, sorted(display_moments))

        for item in self.timeline:
            display_utc = parse_utc_datetime(item["display_utc"])
            self.assertIsNotNone(display_utc)
            self.assertGreaterEqual(display_utc, self.range_start_utc)
            self.assertLessEqual(display_utc, self.range_end_utc)


if __name__ == "__main__":
    unittest.main()
