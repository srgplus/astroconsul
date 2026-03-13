from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from app.core.config import clear_settings_cache, get_settings
from app.infrastructure.persistence.base import Base
from app.infrastructure.persistence.session import clear_engine_cache, database_url_for_settings, get_engine
from app.infrastructure.repositories.factory import get_repository_bundle


def import_legacy_json(
    *,
    database_url: str,
    charts_dir: Path,
    profiles_dir: Path,
    reset: bool,
) -> dict[str, int]:
    os.environ["ASTRO_CONSUL_PERSISTENCE_BACKEND"] = "database"
    os.environ["ASTRO_CONSUL_DATABASE_URL"] = database_url
    clear_settings_cache()
    clear_engine_cache()

    settings = get_settings()
    resolved_database_url = database_url_for_settings(settings)
    if resolved_database_url is None:
        raise RuntimeError("Database URL could not be resolved.")

    engine = get_engine(resolved_database_url)
    if reset:
        Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)

    repositories = get_repository_bundle(settings)

    imported_charts = 0
    imported_profiles = 0
    imported_transits = 0

    for chart_path in sorted(charts_dir.glob("*.json")):
        chart_payload = json.loads(chart_path.read_text(encoding="utf-8"))
        repositories.charts.save_chart(chart_payload, chart_id=chart_path.stem)
        imported_charts += 1

    for profile_path in sorted(profiles_dir.glob("profile_*.json")):
        payload = json.loads(profile_path.read_text(encoding="utf-8"))
        profile_id = str(payload["profile_id"])

        try:
            repositories.profiles.load_profile(profile_id)
        except FileNotFoundError:
            repositories.profiles.create_profile(
                str(payload["profile_name"]),
                str(payload["username"]),
                str(payload["chart_id"]),
                profile_input={},
                profile_id=profile_id,
                created_at=str(payload["created_at"]),
                updated_at=str(payload["updated_at"]),
            )
            imported_profiles += 1

        latest_transit = payload.get("latest_transit")
        if isinstance(latest_transit, dict):
            repositories.profiles.save_latest_transit(profile_id, latest_transit)
            imported_transits += 1

    return {
        "charts": imported_charts,
        "profiles": imported_profiles,
        "latest_transits": imported_transits,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Import legacy JSON charts and profiles into the database.")
    parser.add_argument("--database-url", required=True, help="Target database URL.")
    parser.add_argument("--charts-dir", default="charts", help="Directory containing legacy chart JSON files.")
    parser.add_argument("--profiles-dir", default="profiles", help="Directory containing legacy profile JSON files.")
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Drop and recreate the schema before importing.",
    )
    args = parser.parse_args()

    summary = import_legacy_json(
        database_url=args.database_url,
        charts_dir=Path(args.charts_dir),
        profiles_dir=Path(args.profiles_dir),
        reset=args.reset,
    )
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
