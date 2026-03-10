from __future__ import annotations

import unittest

from server import NatalChartCreateRequest, TransitReportRequest, calculate_chart, create_natal_chart, transit_report


class ServerRouteTests(unittest.TestCase):
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
        self.assertEqual(len(response["natal_positions"]), 10)
        self.assertEqual(response["natal_positions"][0]["id"], "Sun")
        self.assertEqual(response["natal_positions"][0]["house"], 4)
        self.assertEqual(response["angle_positions"][0]["id"], "ASC")
        self.assertEqual(response["natal_summary"]["sun"], "Leo 5°19'44\"")

    def test_raw_natal_endpoint_includes_normalized_positions(self) -> None:
        response = calculate_chart(1991, 7, 28, 22.1, 52.13472, 23.65694)

        self.assertEqual(len(response["natal_positions"]), 10)
        self.assertEqual(response["natal_positions"][1]["id"], "Moon")
        self.assertEqual(response["natal_positions"][1]["house"], 11)
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
        self.assertGreater(len(report["transit_positions"]), 0)
        self.assertGreater(len(report["active_aspects"]), 0)


if __name__ == "__main__":
    unittest.main()
