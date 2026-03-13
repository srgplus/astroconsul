from __future__ import annotations

import unittest

from chart_builder import build_chart, save_chart
from transit_builder import build_transit_report


class TransitReportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        chart = build_chart(1991, 7, 28, 22.1, 52.13472, 23.65694)
        cls.chart_id, cls.chart_path = save_chart(chart, chart_id="chart_1991_07_28_2206")
        cls.report = build_transit_report(cls.chart_path.name, "2026-03-09", "03:06:01")
        cls.report_with_location = build_transit_report(
            cls.chart_path.name,
            "2026-03-09",
            "03:06:01",
            transit_latitude=52.13472,
            transit_longitude=23.65694,
        )

    def test_transit_builder_returns_ordered_transit_objects(self) -> None:
        object_ids = [position["id"] for position in self.report["transit_positions"]]
        self.assertEqual(
            object_ids,
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

    def test_transit_house_mapping_returns_valid_house_numbers(self) -> None:
        for transit_object in self.report["transit_positions"]:
            self.assertIn(transit_object["natal_house"], range(1, 13))

    def test_transit_location_adds_vertex_and_part_of_fortune(self) -> None:
        object_ids = [position["id"] for position in self.report_with_location["transit_positions"]]
        self.assertEqual(object_ids[-2:], ["Part of Fortune", "Vertex"])

        for object_id in ("Part of Fortune", "Vertex"):
            position = next(item for item in self.report_with_location["transit_positions"] if item["id"] == object_id)
            self.assertIn(position["natal_house"], range(1, 13))

    def test_transit_report_includes_natal_context_positions(self) -> None:
        self.assertEqual(len(self.report["natal_positions"]), 19)
        self.assertEqual(self.report["natal_positions"][0]["id"], "Sun")
        self.assertEqual(self.report["natal_positions"][0]["sign"], "Leo")
        self.assertEqual(self.report["natal_positions"][0]["house"], 4)
        self.assertEqual([position["id"] for position in self.report["angle_positions"]], ["ASC", "MC"])
        self.assertEqual(self.report["angle_positions"][0]["sign"], "Gemini")

    def test_transit_aspects_are_deterministic(self) -> None:
        second_report = build_transit_report(self.chart_path.name, "2026-03-09", "03:06:01")
        self.assertEqual(self.report["active_aspects"], second_report["active_aspects"])

    def test_transit_aspects_are_sorted_by_orb(self) -> None:
        orbs = [aspect["orb"] for aspect in self.report["active_aspects"]]
        self.assertEqual(orbs, sorted(orbs))
        self.assertTrue(all(float(orb) <= 1.99 for orb in orbs))

    def test_known_brest_chart_returns_known_valid_aspect(self) -> None:
        self.assertGreater(len(self.report["active_aspects"]), 0)
        self.assertTrue(
            any(
                aspect["transit_object"] == "Venus"
                and aspect["natal_object"] == "Saturn"
                and aspect["aspect"] == "sextile"
                and aspect["is_within_orb"]
                for aspect in self.report["active_aspects"]
            )
        )


if __name__ == "__main__":
    unittest.main()
