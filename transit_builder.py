from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import swisseph as swe

from astro_utils import (
    determine_house,
    longitude_to_zodiac_position,
    normalize_longitude,
    parse_iso_date,
    parse_time_string,
    time_to_decimal_hours,
)
from chart_builder import (
    CHARTS_DIR,
    EPHE_PATH,
    FLAGS,
    HOUSE_SYSTEM,
    HOUSE_SYSTEM_NAME,
    TRANSIT_OBJECT_IDS,
    TRANSIT_OBJECT_ORDER,
    build_chart,
    chart_needs_upgrade,
    compute_part_of_fortune,
    is_diurnal_chart,
    swiss_ephemeris_version,
)
from transit_aspect_engine import compute_transit_to_natal_aspects
from transit_timing_engine import compute_active_aspect_timing

swe.set_ephe_path(str(EPHE_PATH))
MAX_TRANSIT_ORB = 1.99


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


def _load_chart_from_db(chart_id: str) -> dict[str, object] | None:
    """Fallback: load chart payload from natal_charts table when file not on disk."""
    try:
        from app.core.config import get_settings
        settings = get_settings()
        if not settings.use_database:
            return None
        db_url = settings.effective_database_url
        if not db_url:
            return None
        from app.infrastructure.persistence.session import get_engine, normalize_database_url
        from sqlalchemy import text
        engine = get_engine(normalize_database_url(db_url))
        with engine.connect() as conn:
            row = conn.execute(
                text("SELECT chart_payload_json FROM natal_charts WHERE id = :cid"),
                {"cid": chart_id},
            ).fetchone()
            if row and row[0]:
                payload = row[0] if isinstance(row[0], dict) else json.loads(row[0])
                # Also save to disk for future use
                filename = chart_id if chart_id.endswith('.json') else f"{chart_id}.json"
                path = CHARTS_DIR / filename
                CHARTS_DIR.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
                return payload
    except Exception:
        pass
    return None


def load_saved_chart(chart_id: str) -> tuple[Path, dict[str, object]]:
    try:
        chart_path = resolve_chart_path(chart_id)
        chart = json.loads(chart_path.read_text(encoding='utf-8'))
    except FileNotFoundError:
        # Fallback to DB when chart file not on disk (e.g. Railway deployment)
        db_chart = _load_chart_from_db(chart_id)
        if db_chart is None:
            raise FileNotFoundError(f"Natal chart not found: {chart_id}")
        filename = chart_id if chart_id.endswith('.json') else f"{chart_id}.json"
        chart_path = CHARTS_DIR / filename
        chart = db_chart

    if chart_needs_upgrade(chart):
        birth_data = chart.get("birth_data") or {}
        required_fields = {"year", "month", "day", "hour", "latitude", "longitude"}
        if required_fields.issubset(birth_data):
            chart = build_chart(
                int(birth_data["year"]),
                int(birth_data["month"]),
                int(birth_data["day"]),
                float(birth_data["hour"]),
                float(birth_data["latitude"]),
                float(birth_data["longitude"]),
                birth_input=chart.get("birth_input"),
            )
            chart_path.write_text(json.dumps(chart, indent=2, sort_keys=True), encoding="utf-8")

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


def build_transit_point(
    object_id: str,
    longitude: float,
    *,
    speed: float | None = None,
    retrograde: bool | None = None,
) -> dict[str, object]:
    position = longitude_to_zodiac_position(longitude)
    position["id"] = object_id

    if speed is not None:
        position["speed"] = round(speed, 6)
        position["retrograde"] = speed < 0 if retrograde is None else retrograde
    else:
        position["speed"] = None
        position["retrograde"] = retrograde

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


def compute_local_houses_and_angles(jd: float, latitude: float, longitude: float) -> tuple[list[float], dict[str, float]]:
    house_cusps, ascmc = swe.houses(jd, latitude, longitude, HOUSE_SYSTEM)

    if len(house_cusps) == 13:
        houses = [normalize_longitude(value) for value in house_cusps[1:13]]
    else:
        houses = [normalize_longitude(value) for value in house_cusps[:12]]

    angles = {
        "asc": normalize_longitude(ascmc[0]),
        "mc": normalize_longitude(ascmc[1]),
        "vertex": normalize_longitude(ascmc[3]),
    }
    return houses, angles


def transit_object_sort_key(object_id: str) -> tuple[int, str]:
    try:
        return (TRANSIT_OBJECT_ORDER.index(object_id), object_id)
    except ValueError:
        return (len(TRANSIT_OBJECT_ORDER), object_id)


def compute_geocentric_transit_objects(jd: float) -> list[dict[str, object]]:
    transit_objects: list[dict[str, object]] = []

    for object_id, swe_id in TRANSIT_OBJECT_IDS.items():
        values, _ = swe.calc_ut(jd, swe_id, FLAGS)
        transit_objects.append(build_transit_point(object_id, values[0], speed=values[3]))

    north_node = next(item for item in transit_objects if item["id"] == "North Node")
    transit_objects.append(
        build_transit_point(
            "South Node",
            normalize_longitude(float(north_node["longitude"]) + 180),
            speed=float(north_node["speed"]),
            retrograde=bool(north_node["retrograde"]),
        )
    )

    return transit_objects


def compute_location_dependent_transit_objects(
    jd: float,
    base_transit_objects: list[dict[str, object]],
    *,
    latitude: float,
    longitude: float,
) -> list[dict[str, object]]:
    local_houses, local_angles = compute_local_houses_and_angles(jd, latitude, longitude)
    transit_by_id = {str(item["id"]): item for item in base_transit_objects}
    sun_longitude = float(transit_by_id["Sun"]["longitude"])
    moon_longitude = float(transit_by_id["Moon"]["longitude"])
    asc_longitude = float(local_angles["asc"])
    part_of_fortune = compute_part_of_fortune(
        asc_longitude,
        sun_longitude,
        moon_longitude,
        is_diurnal=is_diurnal_chart(sun_longitude, local_houses),
    )

    return [
        build_transit_point("Part of Fortune", part_of_fortune),
        build_transit_point("Vertex", float(local_angles["vertex"])),
    ]


def compute_transit_positions(
    transit_year: int,
    transit_month: int,
    transit_day: int,
    transit_hour: float,
    natal_houses: list[float],
    *,
    transit_latitude: float | None = None,
    transit_longitude: float | None = None,
) -> list[dict[str, object]]:
    jd = swe.julday(transit_year, transit_month, transit_day, transit_hour)
    transit_objects = compute_geocentric_transit_objects(jd)

    if transit_latitude is not None and transit_longitude is not None:
        transit_objects.extend(
            compute_location_dependent_transit_objects(
                jd,
                transit_objects,
                latitude=transit_latitude,
                longitude=transit_longitude,
            )
        )

    mapped = map_transits_to_natal_houses(transit_objects, natal_houses)
    return sorted(mapped, key=lambda item: transit_object_sort_key(str(item["id"])))


def build_transit_report(
    chart_id: str,
    transit_date: str,
    transit_time: str,
    *,
    include_timing: bool = False,
    transit_latitude: float | None = None,
    transit_longitude: float | None = None,
    lang: str = "en",
) -> dict[str, object]:
    chart_path, natal_chart = load_saved_chart(chart_id)
    parsed_date = parse_iso_date(transit_date)
    parsed_time = parse_time_string(transit_time)
    transit_hour = time_to_decimal_hours(parsed_time)
    transit_datetime_utc = datetime.combine(parsed_date, parsed_time, tzinfo=timezone.utc)

    transit_positions = compute_transit_positions(
        parsed_date.year,
        parsed_date.month,
        parsed_date.day,
        transit_hour,
        natal_chart["houses"],
        transit_latitude=transit_latitude,
        transit_longitude=transit_longitude,
    )
    active_aspects = compute_transit_to_natal_aspects(
        transit_positions,
        natal_chart["planets"],
        natal_chart["angles"],
        lang=lang,
    )
    active_aspects = [
        aspect
        for aspect in active_aspects
        if float(aspect["orb"]) <= MAX_TRANSIT_ORB
    ]
    active_aspects.sort(
        key=lambda item: (
            float(item["orb"]),
            *transit_object_sort_key(str(item["transit_object"])),
            str(item["natal_object"]),
            int(item["exact_angle"]),
        )
    )

    if include_timing:
        longitude_cache: dict[tuple[str, int], float] = {}
        timed_aspects: list[dict[str, object]] = []

        for aspect in active_aspects:
            timed_aspect = dict(aspect)
            try:
                timed_aspect["timing"] = compute_active_aspect_timing(
                    timed_aspect,
                    transit_datetime_utc,
                    natal_chart,
                    boundary_orb=MAX_TRANSIT_ORB,
                    longitude_cache=longitude_cache,
                )
            except ValueError:
                timed_aspect["timing"] = None
            timed_aspects.append(timed_aspect)

        active_aspects = timed_aspects

    return {
        "snapshot": {
            "chart_id": chart_path.name,
            "transit_date": parsed_date.isoformat(),
            "transit_time_ut": parsed_time.strftime('%H:%M:%S'),
            "house_system": natal_chart.get("house_system", HOUSE_SYSTEM_NAME),
            "ephemeris": f"Swiss Ephemeris {swiss_ephemeris_version()}",
        },
        "natal_positions": natal_chart.get("natal_positions", []),
        "angle_positions": natal_chart.get("angle_positions", []),
        "transit_positions": transit_positions,
        "active_aspects": active_aspects,
    }
