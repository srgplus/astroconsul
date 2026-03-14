from __future__ import annotations

import json
from pathlib import Path
from typing import Any

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

NATAL_SPECIAL_OBJECT_IDS = {
    "Chiron": swe.CHIRON,
    "Lilith": swe.MEAN_APOG,
    "Selena": swe.WHITE_MOON,
    "North Node": swe.TRUE_NODE,
}

NATAL_POSITION_ORDER = [
    "Sun",
    "ASC",
    "MC",
    "Moon",
    "Mercury",
    "Venus",
    "Mars",
    "Jupiter",
    "Saturn",
    "Uranus",
    "Neptune",
    "Pluto",
    "Chiron",
    "Lilith",
    "Selena",
    "North Node",
    "South Node",
    "Part of Fortune",
    "Vertex",
]

TRANSIT_OBJECT_IDS = {
    "Moon": swe.MOON,
    "Sun": swe.SUN,
    "Mercury": swe.MERCURY,
    "Venus": swe.VENUS,
    "Mars": swe.MARS,
    "Jupiter": swe.JUPITER,
    "Saturn": swe.SATURN,
    "Uranus": swe.URANUS,
    "Neptune": swe.NEPTUNE,
    "Pluto": swe.PLUTO,
    "North Node": swe.TRUE_NODE,
    "Lilith": swe.MEAN_APOG,
}

TRANSIT_OBJECT_ORDER = [
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
    "Part of Fortune",
    "Vertex",
]


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
        "vertex": normalize_degrees(ascmc[3]),
    }
    return houses, angles


def map_natal_planets_to_houses(planets: dict[str, float], houses: list[float]) -> dict[str, int]:
    return {
        planet_id: determine_house(longitude, houses)
        for planet_id, longitude in planets.items()
    }


def is_diurnal_chart(sun_longitude: float, houses: list[float]) -> bool:
    return determine_house(sun_longitude, houses) in range(7, 13)


def compute_part_of_fortune(asc: float, sun: float, moon: float, *, is_diurnal: bool) -> float:
    if is_diurnal:
        return normalize_degrees(asc + moon - sun)
    return normalize_degrees(asc + sun - moon)


def build_unavailable_position(
    object_id: str,
    *,
    house: int | None = None,
    retrograde: bool | None = None,
) -> dict[str, object]:
    return {
        "id": object_id,
        "longitude": None,
        "sign": None,
        "degree": None,
        "minute": None,
        "second": None,
        "formatted_position": None,
        "house": house,
        "speed": None,
        "retrograde": retrograde,
    }


AUTO_HOUSE = object()


def build_chart_position(
    object_id: str,
    longitude: float,
    *,
    houses: list[float],
    speed: float | None = None,
    retrograde: bool | None = None,
    house: int | None | object = AUTO_HOUSE,
) -> dict[str, object]:
    position = longitude_to_zodiac_position(longitude)
    position["id"] = object_id
    position["house"] = determine_house(longitude, houses) if house is AUTO_HOUSE else house
    position["speed"] = round(speed, 6) if speed is not None else None
    if speed is None and retrograde is None:
        position["retrograde"] = None
    else:
        position["retrograde"] = (speed < 0) if retrograde is None and speed is not None else retrograde
    return position


def safe_calc_object(jd: float, swe_id: int) -> tuple[float, float] | None:
    try:
        values, _ = swe.calc_ut(jd, swe_id, FLAGS)
    except Exception:
        return None

    return normalize_degrees(values[0]), round(values[3], 6)


def build_natal_special_positions(
    jd: float,
    planets: dict[str, float],
    houses: list[float],
    angles: dict[str, float],
) -> dict[str, dict[str, object]]:
    positions: dict[str, dict[str, object]] = {}

    for object_id, swe_id in NATAL_SPECIAL_OBJECT_IDS.items():
        result = safe_calc_object(jd, swe_id)
        if result is None:
            positions[object_id] = build_unavailable_position(object_id)
            continue

        longitude, speed = result
        positions[object_id] = build_chart_position(
            object_id,
            longitude,
            houses=houses,
            speed=speed,
        )

    north_node = positions.get("North Node")
    if north_node and north_node.get("longitude") is not None:
        positions["South Node"] = build_chart_position(
            "South Node",
            normalize_degrees(float(north_node["longitude"]) + 180),
            houses=houses,
            speed=float(north_node["speed"]) if north_node.get("speed") is not None else None,
            retrograde=(
                bool(north_node["retrograde"])
                if north_node.get("retrograde") is not None
                else None
            ),
        )
    else:
        positions["South Node"] = build_unavailable_position("South Node")

    part_of_fortune = compute_part_of_fortune(
        float(angles["asc"]),
        float(planets["Sun"]),
        float(planets["Moon"]),
        is_diurnal=is_diurnal_chart(float(planets["Sun"]), houses),
    )
    positions["Part of Fortune"] = build_chart_position(
        "Part of Fortune",
        part_of_fortune,
        houses=houses,
    )
    positions["Vertex"] = build_chart_position(
        "Vertex",
        float(angles["vertex"]),
        houses=houses,
    )

    return positions


def build_natal_positions(
    jd: float,
    planets: dict[str, float],
    planet_speeds: dict[str, float],
    houses: list[float],
    angles: dict[str, float],
) -> list[dict[str, object]]:
    natal_positions: dict[str, dict[str, object]] = {}

    for planet_id, longitude in planets.items():
        natal_positions[planet_id] = build_chart_position(
            planet_id,
            longitude,
            houses=houses,
            speed=planet_speeds[planet_id],
        )

    natal_positions["ASC"] = build_chart_position(
        "ASC",
        float(angles["asc"]),
        houses=houses,
    )
    natal_positions["MC"] = build_chart_position(
        "MC",
        float(angles["mc"]),
        houses=houses,
    )
    natal_positions.update(
        build_natal_special_positions(
            jd,
            planets,
            houses,
            angles,
        )
    )

    return [
        natal_positions.get(object_id, build_unavailable_position(object_id))
        for object_id in NATAL_POSITION_ORDER
    ]


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
    natal_positions = build_natal_positions(jd, planets, planet_speeds, houses, angles)
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
        "natal_aspects": compute_natal_aspects({
            **planets,
            **{
                str(p["id"]): float(p["longitude"])
                for p in natal_positions
                if p.get("longitude") is not None
                and str(p.get("id")) not in planets
            },
        }),
        "natal_summary": build_natal_summary(natal_positions, angle_positions),
    }

    if birth_input is not None:
        chart["birth_input"] = birth_input

    return chart


def chart_needs_upgrade(chart: dict[str, Any]) -> bool:
    natal_positions = chart.get("natal_positions")
    if not isinstance(natal_positions, list):
        return True

    position_ids = [str(position.get("id")) for position in natal_positions if isinstance(position, dict)]
    if position_ids != NATAL_POSITION_ORDER:
        return True

    vertex_position = next(
        (position for position in natal_positions if isinstance(position, dict) and str(position.get("id")) == "Vertex"),
        None,
    )
    if not isinstance(vertex_position, dict) or vertex_position.get("house") is None:
        return True

    # Check if natal_aspects include special points and ASC/MC
    natal_aspects = chart.get("natal_aspects", [])
    special_ids = {"Chiron", "Lilith", "Selena", "North Node", "South Node", "Part of Fortune", "Vertex"}
    has_special = any(
        a.get("p1") in special_ids or a.get("p2") in special_ids
        for a in natal_aspects
        if isinstance(a, dict)
    )
    if not has_special:
        return True

    angle_ids = {"ASC", "MC"}
    has_angles = any(
        a.get("p1") in angle_ids or a.get("p2") in angle_ids
        for a in natal_aspects
        if isinstance(a, dict)
    )
    return not has_angles


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
