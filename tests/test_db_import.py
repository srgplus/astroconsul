from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from app.api.dependencies import clear_dependency_caches
from app.core.config import clear_settings_cache
from app.infrastructure.persistence.models import LatestTransitModel, NatalChartModel, ProfileModel, UserModel
from app.infrastructure.persistence.session import clear_engine_cache, get_session_factory
from scripts.import_legacy_json_to_db import import_legacy_json


class LegacyImportTests(unittest.TestCase):
    def tearDown(self) -> None:
        for env_var in ("ASTRO_CONSUL_PERSISTENCE_BACKEND", "ASTRO_CONSUL_DATABASE_URL"):
            os.environ.pop(env_var, None)
        clear_dependency_caches()
        clear_settings_cache()
        clear_engine_cache()

    def test_import_legacy_json_preserves_chart_and_profile_ids(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            charts_dir = root / "charts"
            profiles_dir = root / "profiles"
            charts_dir.mkdir()
            profiles_dir.mkdir()

            chart_id = "chart_1991_07_28_2206"
            profile_id = "profile_import_target"
            chart_payload = json.loads(Path("charts/chart_1991_07_28_2206.json").read_text(encoding="utf-8"))
            profile_payload = {
                "profile_id": profile_id,
                "profile_name": "Imported Profile",
                "username": "import_target",
                "chart_id": chart_id,
                "created_at": "2026-03-01T00:00:00Z",
                "updated_at": "2026-03-02T00:00:00Z",
                "latest_transit": {
                    "transit_date": "2026-03-14",
                    "transit_time": "01:19:00",
                    "timezone": "America/Los_Angeles",
                    "location_name": "Los Angeles",
                    "latitude": 34.0522,
                    "longitude": -118.2437,
                    "updated_at": "2026-03-13T12:00:00Z",
                },
            }

            (charts_dir / f"{chart_id}.json").write_text(
                json.dumps(chart_payload, indent=2, sort_keys=True),
                encoding="utf-8",
            )
            (profiles_dir / f"{profile_id}.json").write_text(
                json.dumps(profile_payload, indent=2, sort_keys=True),
                encoding="utf-8",
            )

            db_path = root / "astro_consul.sqlite3"
            database_url = f"sqlite:///{db_path}"
            summary = import_legacy_json(
                database_url=database_url,
                charts_dir=charts_dir,
                profiles_dir=profiles_dir,
                reset=True,
            )

            self.assertEqual(summary["charts"], 1)
            self.assertEqual(summary["profiles"], 1)
            self.assertEqual(summary["latest_transits"], 1)

            session_factory = get_session_factory(database_url)
            with session_factory() as session:
                self.assertIsNotNone(session.get(UserModel, "user_local_dev"))
                chart = session.get(NatalChartModel, chart_id)
                profile = session.get(ProfileModel, profile_id)
                latest_transit = session.get(LatestTransitModel, profile_id)

                self.assertIsNotNone(chart)
                self.assertEqual(chart.id, chart_id)
                self.assertIsNotNone(profile)
                self.assertEqual(profile.chart_id, chart_id)
                self.assertEqual(profile.handle, "import_target")
                self.assertIsNotNone(latest_transit)
                self.assertEqual(latest_transit.timezone, "America/Los_Angeles")


if __name__ == "__main__":
    unittest.main()
