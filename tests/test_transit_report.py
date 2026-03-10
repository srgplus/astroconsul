from __future__ import annotations

import unittest

from chart_builder import build_chart, save_chart
from transit_builder import build_transit_report


class TransitReportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        chart = build_chart(1991, 7, 28, 22.1, 52.13472, 23.65694)
        cls.chart_id, cls.chart_path = save_chart(chart, chart_id='chart_1991_07_28_2206')
        cls.report = build_transit_report(cls.chart_path.name, '2026-03-09', '03:06:01')

    def test_transit_builder_returns_ten_planets(self) -> None:
        self.assertEqual(len(self.report['transit_positions']), 10)

    def test_transit_house_mapping_returns_valid_house_numbers(self) -> None:
        for transit_object in self.report['transit_positions']:
            self.assertIn(transit_object['natal_house'], range(1, 13))

    def test_transit_aspects_are_deterministic(self) -> None:
        second_report = build_transit_report(self.chart_path.name, '2026-03-09', '03:06:01')
        self.assertEqual(self.report['active_aspects'], second_report['active_aspects'])

    def test_transit_aspects_are_sorted_by_orb(self) -> None:
        orbs = [aspect['orb'] for aspect in self.report['active_aspects']]
        self.assertEqual(orbs, sorted(orbs))

    def test_known_brest_chart_returns_known_valid_aspect(self) -> None:
        self.assertGreater(len(self.report['active_aspects']), 0)
        self.assertTrue(
            any(
                aspect['transit_object'] == 'Venus'
                and aspect['natal_object'] == 'Saturn'
                and aspect['aspect'] == 'sextile'
                and aspect['is_within_orb']
                for aspect in self.report['active_aspects']
            )
        )


if __name__ == '__main__':
    unittest.main()
