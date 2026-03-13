from __future__ import annotations

import unittest

from chart_builder import NATAL_POSITION_ORDER, build_chart, map_natal_planets_to_houses


class NatalPositionsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.chart = build_chart(1991, 7, 28, 22.1, 52.13472, 23.65694)
        cls.positions = cls.chart["natal_positions"]
        cls.positions_by_id = {position["id"]: position for position in cls.positions}

    def test_natal_positions_exists_for_all_display_objects(self) -> None:
        self.assertEqual(len(self.positions), len(NATAL_POSITION_ORDER))
        self.assertEqual([position["id"] for position in self.positions], NATAL_POSITION_ORDER)

    def test_natal_positions_include_required_fields(self) -> None:
        required_fields = {"id", "longitude", "sign", "degree", "minute", "second", "retrograde", "house"}

        for position in self.positions:
            self.assertTrue(required_fields.issubset(position.keys()))
            self.assertIn(type(position["retrograde"]), {bool, type(None)})
            if position["house"] is not None:
                self.assertIn(position["house"], range(1, 13))

    def test_known_brest_house_mapping_matches_expected_planets(self) -> None:
        expected_houses = {
            "Sun": 4,
            "ASC": 1,
            "MC": 10,
            "Moon": 11,
            "Mercury": 5,
            "Venus": 5,
            "Mars": 5,
            "Jupiter": 4,
            "Saturn": 10,
            "Uranus": 8,
            "Neptune": 9,
            "Pluto": 6,
        }

        actual_houses = {
            planet_id: int(self.positions_by_id[planet_id]["house"])
            for planet_id in expected_houses
        }

        self.assertEqual(actual_houses, expected_houses)

    def test_wraparound_house_logic_handles_zero_degree_boundary(self) -> None:
        houses = [350.0, 20.0, 50.0, 80.0, 110.0, 140.0, 170.0, 200.0, 230.0, 260.0, 290.0, 320.0]
        planets = {
            "NearZero": 359.5,
            "WrappedIntoOne": 5.0,
            "BeforeFirst": 345.0,
            "SecondHouse": 25.0,
        }

        mapped_houses = map_natal_planets_to_houses(planets, houses)

        self.assertEqual(mapped_houses["NearZero"], 1)
        self.assertEqual(mapped_houses["WrappedIntoOne"], 1)
        self.assertEqual(mapped_houses["BeforeFirst"], 12)
        self.assertEqual(mapped_houses["SecondHouse"], 2)

    def test_special_points_and_vertex_are_exposed(self) -> None:
        for object_id in ("Chiron", "Lilith", "Selena", "North Node", "South Node", "Part of Fortune", "Vertex"):
            self.assertIn(object_id, self.positions_by_id)

        self.assertIn(self.positions_by_id["Part of Fortune"]["house"], range(1, 13))
        self.assertIn(self.positions_by_id["Vertex"]["house"], range(1, 13))
        self.assertIsNone(self.positions_by_id["Vertex"]["retrograde"])

    def test_angle_positions_and_natal_summary_exist(self) -> None:
        angle_ids = [position["id"] for position in self.chart["angle_positions"]]

        self.assertEqual(angle_ids, ["ASC", "MC"])
        self.assertEqual(self.chart["natal_summary"]["sun"], "Leo 5°19'44\"")
        self.assertEqual(self.chart["natal_summary"]["moon"], "Aquarius 29°14'52\"")
        self.assertEqual(self.chart["natal_summary"]["asc"], "Gemini 2°14'24\"")


if __name__ == "__main__":
    unittest.main()
