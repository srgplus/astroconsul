from __future__ import annotations

import unittest

from aspect_engine import angular_delta, compute_natal_aspects, detect_aspect


class AspectEngineTests(unittest.TestCase):
    def test_sun_opposition_saturn_example(self) -> None:
        aspects = compute_natal_aspects({"Sun": 10.0, "Saturn": 188.0})

        self.assertEqual(len(aspects), 1)
        self.assertEqual(aspects[0]["p1"], "Sun")
        self.assertEqual(aspects[0]["p2"], "Saturn")
        self.assertEqual(aspects[0]["aspect"], "opposition")
        self.assertAlmostEqual(aspects[0]["orb"], 2.0)

    def test_wraparound_case(self) -> None:
        self.assertAlmostEqual(angular_delta(359.0, 1.0), 2.0)
        match = detect_aspect(359.0, 1.0)

        self.assertIsNotNone(match)
        self.assertEqual(match["aspect"], "conjunction")
        self.assertAlmostEqual(match["orb"], 2.0)

    def test_minimal_orb_selection(self) -> None:
        custom_aspects = [
            {"name": "wide", "angle": 100, "orb": 10},
            {"name": "tight", "angle": 102, "orb": 10},
        ]

        match = detect_aspect(0.0, 103.0, aspects=custom_aspects)

        self.assertIsNotNone(match)
        self.assertEqual(match["aspect"], "tight")
        self.assertAlmostEqual(match["orb"], 1.0)


if __name__ == "__main__":
    unittest.main()
