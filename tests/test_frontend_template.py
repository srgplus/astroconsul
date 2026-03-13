from __future__ import annotations

import re
import unittest
from pathlib import Path

TEMPLATE_PATH = Path(__file__).resolve().parents[1] / "templates" / "index.html"


class FrontendTemplateTests(unittest.TestCase):
    def test_profile_and_transit_forms_do_not_ship_with_demo_values(self) -> None:
        template = TEMPLATE_PATH.read_text(encoding="utf-8")

        for input_id in (
            "birth-date",
            "birth-time",
            "timezone",
            "location-name",
            "latitude",
            "longitude",
            "transit-date",
            "transit-time",
            "transit-timezone",
        ):
            self.assertNotRegex(template, rf'<input[^>]*id="{re.escape(input_id)}"[^>]*\bvalue=')

    def test_profile_view_avoids_duplicate_natal_summary_labels(self) -> None:
        template = TEMPLATE_PATH.read_text(encoding="utf-8")

        self.assertNotIn("Review the active natal profile here.", template)
        self.assertNotIn("Profile Handle", template)
        self.assertNotIn("Natal Aspects Count", template)
        self.assertNotIn("Normalized natal placements", template)

    def test_transit_view_is_compact_and_current_sky_positions_precede_active_aspects(self) -> None:
        template = TEMPLATE_PATH.read_text(encoding="utf-8")

        self.assertNotIn("Generate deterministic transits for the currently selected natal profile.", template)
        self.assertNotIn("A concise view of the transit moment, timezone, and calculation context.", template)
        self.assertNotIn("Transit Timezone", template)
        self.assertNotIn("Grouped by object type, with the transit order kept consistent across the report.", template)
        self.assertLess(template.index("Current Sky Positions"), template.index("Transit-to-natal aspects"))

    def test_active_aspects_support_retrograde_badges(self) -> None:
        template = TEMPLATE_PATH.read_text(encoding="utf-8")

        self.assertIn("retrograde-badge", template)
        self.assertIn("showRetrogradeBadge: true", template)

    def test_vertex_belongs_to_special_points_groups(self) -> None:
        template = TEMPLATE_PATH.read_text(encoding="utf-8")

        self.assertIn(
            'Vertex: { textBadge: "Vx", transitGroup: "special",'
            ' transitOrder: 17, natalGroup: "special", natalOrder: 7 }',
            template,
        )


if __name__ == "__main__":
    unittest.main()
