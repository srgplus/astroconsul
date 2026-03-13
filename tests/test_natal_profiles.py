from __future__ import annotations

import json
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException

import natal_profiles as natal_profiles_module
from natal_profiles import PROFILES_DIR
from server import (
    NatalProfileUpsertRequest,
    create_natal_profile,
    natal_profile_detail,
    natal_profiles,
    update_natal_profile,
)

TEST_USERNAMES = {"profile_test_alpha", "profile_test_beta"}


def cleanup_test_profiles() -> None:
    if not PROFILES_DIR.exists():
        return

    for path in PROFILES_DIR.glob("profile_*.json"):
        payload = json.loads(path.read_text(encoding="utf-8"))
        if payload.get("username") in TEST_USERNAMES:
            path.unlink()


class NatalProfilesTests(unittest.TestCase):
    def setUp(self) -> None:
        cleanup_test_profiles()

    def tearDown(self) -> None:
        cleanup_test_profiles()

    def test_natal_profiles_bootstrap_returns_items(self) -> None:
        response = natal_profiles()

        self.assertIn("profiles", response)
        self.assertGreater(len(response["profiles"]), 0)
        first_profile = response["profiles"][0]
        self.assertIn("profile_id", first_profile)
        self.assertIn("profile_name", first_profile)
        self.assertIn("username", first_profile)
        self.assertIn("chart_id", first_profile)
        self.assertIn("natal_summary", first_profile)

    def test_create_profile_returns_profile_and_chart(self) -> None:
        response = create_natal_profile(
            NatalProfileUpsertRequest(
                profile_name="Profile Test Alpha",
                username="profile_test_alpha",
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

        self.assertEqual(response["profile"]["profile_name"], "Profile Test Alpha")
        self.assertEqual(response["profile"]["username"], "profile_test_alpha")
        self.assertEqual(response["chart"]["chart_id"], "chart_1991_07_28_2206")
        self.assertEqual(response["chart"]["birth_input"]["timezone"], "Europe/Minsk")

        detail = natal_profile_detail(response["profile"]["profile_id"])
        self.assertEqual(detail["profile"]["username"], "profile_test_alpha")
        self.assertEqual(detail["chart"]["chart_id"], "chart_1991_07_28_2206")

    def test_update_profile_keeps_profile_id_and_rebinds_chart(self) -> None:
        created = create_natal_profile(
            NatalProfileUpsertRequest(
                profile_name="Profile Test Beta",
                username="profile_test_beta",
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

        updated = update_natal_profile(
            created["profile"]["profile_id"],
            NatalProfileUpsertRequest(
                profile_name="Profile Test Beta Updated",
                username="profile_test_beta",
                name="Serge Updated",
                birth_date="1994-03-26",
                birth_time="01:30:00",
                timezone="Europe/Minsk",
                location_name="Brest, Belarus",
                latitude=52.13472,
                longitude=23.65694,
                time_basis="local",
            ),
        )

        self.assertEqual(updated["profile"]["profile_id"], created["profile"]["profile_id"])
        self.assertEqual(updated["profile"]["profile_name"], "Profile Test Beta Updated")
        self.assertEqual(updated["profile"]["username"], "profile_test_beta")
        self.assertEqual(updated["chart"]["chart_id"], "chart_1994_03_25_2330")

    def test_duplicate_username_returns_http_400(self) -> None:
        create_natal_profile(
            NatalProfileUpsertRequest(
                profile_name="Profile Test Alpha",
                username="@profile_test_alpha",
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

        with self.assertRaises(HTTPException) as context:
            create_natal_profile(
                NatalProfileUpsertRequest(
                    profile_name="Profile Test Alpha Duplicate",
                    username="profile_test_alpha",
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

        self.assertEqual(context.exception.status_code, 400)


class NatalProfilesBootstrapTests(unittest.TestCase):
    def test_bootstrap_skips_chart_import_once_profiles_exist(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            temp_profiles_dir = temp_root / "profiles"
            temp_charts_dir = temp_root / "charts"
            temp_profiles_dir.mkdir()
            temp_charts_dir.mkdir()

            existing_profile = {
                "profile_id": "profile_existing",
                "profile_name": "Existing Profile",
                "username": "existing_profile",
                "chart_id": "chart_existing",
                "created_at": "2026-03-13T00:00:00Z",
                "updated_at": "2026-03-13T00:00:00Z",
            }
            (temp_profiles_dir / "profile_existing.json").write_text(
                json.dumps(existing_profile, indent=2, sort_keys=True),
                encoding="utf-8",
            )
            for chart_id in ("chart_existing", "chart_new"):
                (temp_charts_dir / f"{chart_id}.json").write_text(
                    json.dumps({"birth_input": {"name": chart_id}}, indent=2, sort_keys=True),
                    encoding="utf-8",
                )

            with (
                patch.object(natal_profiles_module, "PROFILES_DIR", temp_profiles_dir),
                patch.object(natal_profiles_module, "CHARTS_DIR", temp_charts_dir),
            ):
                natal_profiles_module.bootstrap_profiles()

            profile_files = sorted(path.name for path in temp_profiles_dir.glob("profile_*.json"))
            self.assertEqual(profile_files, ["profile_existing.json"])

    def test_load_profile_rolls_stale_latest_transit_forward_to_now(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_profiles_dir = Path(temp_dir) / "profiles"
            temp_profiles_dir.mkdir()
            profile_id = "profile_latest_transit"
            profile_path = temp_profiles_dir / f"{profile_id}.json"
            profile_path.write_text(
                json.dumps(
                    {
                        "profile_id": profile_id,
                        "profile_name": "Latest Transit Profile",
                        "username": "latest_transit_profile",
                        "chart_id": "chart_1991_07_28_2206",
                        "created_at": "2026-03-01T00:00:00Z",
                        "updated_at": "2026-03-01T00:00:00Z",
                        "latest_transit": {
                            "transit_date": "2026-03-10",
                            "transit_time": "08:30:00",
                            "timezone": "Europe/Minsk",
                            "location_name": "Brest, Belarus",
                            "latitude": 52.13472,
                            "longitude": 23.65694,
                            "updated_at": "2026-03-10T05:30:00Z",
                        },
                    },
                    indent=2,
                    sort_keys=True,
                ),
                encoding="utf-8",
            )
            fixed_now = datetime(2026, 3, 13, 18, 45, 30, tzinfo=UTC)

            with (
                patch.object(natal_profiles_module, "PROFILES_DIR", temp_profiles_dir),
                patch.object(natal_profiles_module, "current_utc_datetime", return_value=fixed_now),
            ):
                _, profile = natal_profiles_module.load_profile(profile_id)

            self.assertEqual(
                profile["latest_transit"],
                {
                    "transit_date": "2026-03-13",
                    "transit_time": "21:45:30",
                    "timezone": "Europe/Minsk",
                    "location_name": "Brest, Belarus",
                    "latitude": 52.13472,
                    "longitude": 23.65694,
                    "updated_at": "2026-03-13T18:45:30Z",
                },
            )

            persisted = json.loads(profile_path.read_text(encoding="utf-8"))
            self.assertEqual(persisted["latest_transit"], profile["latest_transit"])


if __name__ == "__main__":
    unittest.main()
