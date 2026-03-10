from __future__ import annotations

import json
from pathlib import Path

import swisseph as swe

from astro_utils import (
    determine_house,
    longitude_to_zodiac_position,
    parse_iso_date,
    parse_time_string,
    time_to_decimal_hours,
)
from chart_builder import CHARTS_DIR, EPHE_PATH, FLAGS, HOUSE_SYSTEM_NAME, PLANETS, swiss_ephemeris_version
from transit_aspect_engine import compute_transit_to_natal_aspects

swe.set_ephe_path(str(EPHE_PATH))


def resolve_chart_path(chart_id: str) -> Path:
    candidate = Path(chart_id)

    if candidate.is_absolute():
        path = candidate
    else:
        filename = chart_id if chart_id.endswith('.json') else f"{chart_id}.json"
        path = CHARTS_DIR / filename

    if not path.exists():
        raise FileNotFoundError(f"Natal chart not found: {chart_id}")

    return path


def load_saved_chart(chart_id: str) -> tuple[Path, dict[str, object]]:
    chart_path = resolve_chart_path(chart_id)
    chart = json.loads(chart_path.read_text(encoding='utf-8'))
    return chart_path, chart


def build_transit_object(planet_id: str, longitude: float, speed: float) -> dict[str, object]:
    position = longitude_to_zodiac_position(longitude)
    position.update(
        {
            "id": planet_id,
            "speed": round(speed, 6),
            "retrograde": speed < 0,
        }
    )
    return position


def determine_natal_house(longitude: float, natal_houses: list[float]) -> int:
    return determine_house(longitude, natal_houses)


def map_transits_to_natal_houses(
    transit_objects: list[dict[str, object]],
    natal_houses: list[float],
) -> list[dict[str, object]]:
    mapped_objects: list[dict[str, object]] = []

    for transit_object in transit_objects:
        mapped_object = dict(transit_object)
        mapped_object["natal_house"] = determine_natal_house(
            float(transit_object["longitude"]),
            natal_houses,
        )
        mapped_objects.append(mapped_object)

    return mapped_objects


def compute_transit_positions(
    transit_year: int,
    transit_month: int,
    transit_day: int,
    transit_hour: float,
    natal_houses: list[float],
) -> list[dict[str, object]]:
    jd = swe.julday(transit_year, transit_month, transit_day, transit_hour)
    transit_objects: list[dict[str, object]] = []

    for planet_id, swe_id in PLANETS.items():
        values, _ = swe.calc_ut(jd, swe_id, FLAGS)
        transit_objects.append(build_transit_object(planet_id, values[0], values[3]))

    return map_transits_to_natal_houses(transit_objects, natal_houses)


def build_transit_report(
    chart_id: str,
    transit_date: str,
    transit_time: str,
) -> dict[str, object]:
    chart_path, natal_chart = load_saved_chart(chart_id)
    parsed_date = parse_iso_date(transit_date)
    parsed_time = parse_time_string(transit_time)
    transit_hour = time_to_decimal_hours(parsed_time)

    transit_positions = compute_transit_positions(
        parsed_date.year,
        parsed_date.month,
        parsed_date.day,
        transit_hour,
        natal_chart["houses"],
    )
    active_aspects = compute_transit_to_natal_aspects(
        transit_positions,
        natal_chart["planets"],
        natal_chart["angles"],
    )
    active_aspects.sort(
        key=lambda item: (
            float(item["orb"]),
            str(item["transit_object"]),
            str(item["natal_object"]),
            int(item["exact_angle"]),
        )
    )

    return {
        "snapshot": {
            "chart_id": chart_path.name,
            "transit_date": parsed_date.isoformat(),
            "transit_time_ut": parsed_time.strftime('%H:%M:%S'),
            "house_system": natal_chart.get("house_system", HOUSE_SYSTEM_NAME),
            "ephemeris": f"Swiss Ephemeris {swiss_ephemeris_version()}",
        },
        "transit_positions": transit_positions,
        "active_aspects": active_aspects,
    }
