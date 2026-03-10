from __future__ import annotations

import json
from pathlib import Path

import swisseph as swe

from aspect_engine import compute_natal_aspects
from astro_utils import determine_house, hour_to_time_token, longitude_to_zodiac_position, normalize_longitude

BASE_DIR = Path(__file__).resolve().parent
EPHE_PATH = BASE_DIR / "ephe"
CHARTS_DIR = BASE_DIR / "charts"
HOUSE_SYSTEM = b"P"
HOUSE_SYSTEM_NAME = "Placidus"
FLAGS = swe.FLG_SWIEPH | swe.FLG_SPEED

swe.set_ephe_path(str(EPHE_PATH))

PLANETS = {
    "Sun": swe.SUN,
    "Moon": swe.MOON,
    "Mercury": swe.MERCURY,
    "Venus": swe.VENUS,
    "Mars": swe.MARS,
    "Jupiter": swe.JUPITER,
    "Saturn": swe.SATURN,
    "Uranus": swe.URANUS,
    "Neptune": swe.NEPTUNE,
    "Pluto": swe.PLUTO,
}


def normalize_degrees(value: float) -> float:
    return normalize_longitude(value)


def swiss_ephemeris_version() -> str:
    version = getattr(swe, "version", "unknown")
    return version() if callable(version) else str(version)


def describe_ephemeris_source(retflags: int) -> str:
    if retflags & swe.FLG_MOSEPH:
        return "Moshier fallback"
    if retflags & swe.FLG_SWIEPH:
        return "Swiss Ephemeris files"
    return f"Unknown ({retflags})"


def compute_planets(jd: float) -> tuple[dict[str, float], dict[str, float], list[str]]:
    planets: dict[str, float] = {}
    planet_speeds: dict[str, float] = {}
    ephemeris_sources: set[str] = set()

    for name, planet_id in PLANETS.items():
        values, retflags = swe.calc_ut(jd, planet_id, FLAGS)
        planets[name] = normalize_degrees(values[0])
        planet_speeds[name] = round(values[3], 6)
        ephemeris_sources.add(describe_ephemeris_source(retflags))

    return planets, planet_speeds, sorted(ephemeris_sources)


def compute_houses(jd: float, latitude: float, longitude: float) -> tuple[list[float], dict[str, float]]:
    house_cusps, ascmc = swe.houses(jd, latitude, longitude, HOUSE_SYSTEM)

    if len(house_cusps) == 13:
        houses = [normalize_degrees(value) for value in house_cusps[1:13]]
    else:
        houses = [normalize_degrees(value) for value in house_cusps[:12]]

    angles = {
        "asc": normalize_degrees(ascmc[0]),
        "mc": normalize_degrees(ascmc[1]),
    }
    return houses, angles


def map_natal_planets_to_houses(planets: dict[str, float], houses: list[float]) -> dict[str, int]:
    return {
        planet_id: determine_house(longitude, houses)
        for planet_id, longitude in planets.items()
    }


def build_natal_positions(
    planets: dict[str, float],
    planet_speeds: dict[str, float],
    houses: list[float],
) -> list[dict[str, object]]:
    natal_houses = map_natal_planets_to_houses(planets, houses)
    natal_positions: list[dict[str, object]] = []

    for planet_id in PLANETS:
        position = longitude_to_zodiac_position(planets[planet_id])
        position.update(
            {
                "id": planet_id,
                "retrograde": planet_speeds[planet_id] < 0,
                "house": natal_houses[planet_id],
                "speed": planet_speeds[planet_id],
            }
        )
        natal_positions.append(position)

    return natal_positions


def build_angle_positions(angles: dict[str, float]) -> list[dict[str, object]]:
    angle_positions: list[dict[str, object]] = []

    for angle_id, longitude in (("ASC", float(angles["asc"])), ("MC", float(angles["mc"]))):
        position = longitude_to_zodiac_position(longitude)
        position.update({"id": angle_id})
        angle_positions.append(position)

    return angle_positions


def format_summary_position(position: dict[str, object]) -> str:
    return (
        f"{position['sign']} {position['degree']}°"
        f"{int(position['minute']):02d}'{int(position['second']):02d}\""
    )


def build_natal_summary(
    natal_positions: list[dict[str, object]],
    angle_positions: list[dict[str, object]],
) -> dict[str, str]:
    positions_by_id = {str(position["id"]): position for position in natal_positions}
    angles_by_id = {str(position["id"]): position for position in angle_positions}

    return {
        "sun": format_summary_position(positions_by_id["Sun"]),
        "moon": format_summary_position(positions_by_id["Moon"]),
        "asc": format_summary_position(angles_by_id["ASC"]),
    }


def build_chart(
    year: int,
    month: int,
    day: int,
    hour: float,
    latitude: float,
    longitude: float,
    *,
    birth_input: dict[str, object] | None = None,
) -> dict[str, object]:
    jd = swe.julday(year, month, day, hour)
    planets, planet_speeds, ephemeris_sources = compute_planets(jd)
    houses, angles = compute_houses(jd, latitude, longitude)
    natal_positions = build_natal_positions(planets, planet_speeds, houses)
    angle_positions = build_angle_positions(angles)

    chart = {
        "birth_data": {
            "year": year,
            "month": month,
            "day": day,
            "hour": round(hour, 6),
            "latitude": latitude,
            "longitude": longitude,
            "time_basis": "UT",
        },
        "house_system": HOUSE_SYSTEM_NAME,
        "julian_day": round(jd, 8),
        "swiss_ephemeris_version": swiss_ephemeris_version(),
        "ephemeris_path": str(EPHE_PATH),
        "ephemeris_sources": ephemeris_sources,
        "planets": planets,
        "natal_positions": natal_positions,
        "houses": houses,
        "angles": angles,
        "angle_positions": angle_positions,
        "natal_aspects": compute_natal_aspects(planets),
        "natal_summary": build_natal_summary(natal_positions, angle_positions),
    }

    if birth_input is not None:
        chart["birth_input"] = birth_input

    return chart


def make_chart_id(year: int, month: int, day: int, hour: float) -> str:
    return f"chart_{year:04d}_{month:02d}_{day:02d}_{hour_to_time_token(hour)}"


def save_chart(chart: dict[str, object], chart_id: str | None = None) -> tuple[str, Path]:
    CHARTS_DIR.mkdir(parents=True, exist_ok=True)

    if chart_id is None:
        birth_data = chart["birth_data"]
        chart_id = make_chart_id(
            int(birth_data["year"]),
            int(birth_data["month"]),
            int(birth_data["day"]),
            float(birth_data["hour"]),
        )

    output_path = CHARTS_DIR / f"{chart_id}.json"
    output_path.write_text(json.dumps(chart, indent=2, sort_keys=True), encoding="utf-8")
    return chart_id, output_path
