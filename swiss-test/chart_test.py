"""Minimal Swiss Ephemeris natal chart accuracy prototype."""

from __future__ import annotations

from datetime import datetime, timedelta

try:
    import swisseph as swe
except ModuleNotFoundError as exc:
    raise SystemExit(
        "swisseph is not installed. Run `pip install -r requirements.txt` first."
    ) from exc


BIRTH_DATA = {
    "year": 1990,
    "month": 11,
    "day": 15,
    "hour": 14,
    "minute": 35,
    "latitude": 40.7128,
    "longitude": -74.0060,
    "timezone_offset": -5,
    "house_system": b"P",
}

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

DEGREE_SYMBOL = "\N{DEGREE SIGN}"
EPHE_PATH = "./ephe"


def format_degrees(value: float) -> str:
    return f"{value % 360:.6f}{DEGREE_SYMBOL}"


def format_signed_degrees(value: float) -> str:
    return f"{value:+.6f}{DEGREE_SYMBOL}"


def format_timezone(offset_hours: float) -> str:
    sign = "+" if offset_hours >= 0 else "-"
    total_minutes = int(round(abs(offset_hours) * 60))
    hours, minutes = divmod(total_minutes, 60)
    return f"UTC{sign}{hours:02d}:{minutes:02d}"


def swiss_ephemeris_version() -> str:
    version = getattr(swe, "version", "unknown")
    return version() if callable(version) else str(version)


def local_to_utc(
    year: int, month: int, day: int, hour: int, minute: int, timezone_offset: float
) -> datetime:
    local_dt = datetime(year, month, day, hour, minute)
    return local_dt - timedelta(hours=timezone_offset)


def calculate_julian_day(utc_dt: datetime) -> float:
    hour_decimal = (
        utc_dt.hour
        + utc_dt.minute / 60
        + utc_dt.second / 3600
        + utc_dt.microsecond / 3_600_000_000
    )
    return swe.julday(utc_dt.year, utc_dt.month, utc_dt.day, hour_decimal)


def describe_ephemeris_source(retflags: int) -> str:
    if retflags & swe.FLG_MOSEPH:
        return "Moshier fallback"
    if retflags & swe.FLG_SWIEPH:
        return "Swiss Ephemeris files"
    return f"Unknown ({retflags})"


def calculate_planets(
    jd_ut: float,
) -> tuple[dict[str, dict[str, float | bool | str]], set[str]]:
    flags = swe.FLG_SWIEPH | swe.FLG_SPEED
    results: dict[str, dict[str, float | bool | str]] = {}
    sources: set[str] = set()

    for name, planet_id in PLANETS.items():
        values, retflags = swe.calc_ut(jd_ut, planet_id, flags)
        speed = values[3]
        source = describe_ephemeris_source(retflags)
        sources.add(source)
        results[name] = {
            "longitude": values[0] % 360,
            "latitude": values[1],
            "speed": speed,
            "retrograde": speed < 0,
            "ephemeris_source": source,
        }

    return results, sources


def calculate_houses(
    jd_ut: float, latitude: float, longitude: float, house_system: bytes
) -> tuple[list[float], dict[str, float]]:
    house_cusps, ascmc = swe.houses(jd_ut, latitude, longitude, house_system)

    if len(house_cusps) == 13:
        cusps = [value % 360 for value in house_cusps[1:13]]
    else:
        cusps = [value % 360 for value in house_cusps[:12]]

    angles = {
        "ASC": ascmc[0] % 360,
        "MC": ascmc[1] % 360,
    }
    return cusps, angles


def print_chart() -> None:
    swe.set_ephe_path(EPHE_PATH)

    utc_dt = local_to_utc(
        BIRTH_DATA["year"],
        BIRTH_DATA["month"],
        BIRTH_DATA["day"],
        BIRTH_DATA["hour"],
        BIRTH_DATA["minute"],
        BIRTH_DATA["timezone_offset"],
    )
    jd_ut = calculate_julian_day(utc_dt)
    planets, ephemeris_sources = calculate_planets(jd_ut)
    house_cusps, angles = calculate_houses(
        jd_ut,
        BIRTH_DATA["latitude"],
        BIRTH_DATA["longitude"],
        BIRTH_DATA["house_system"],
    )

    print("Swiss Ephemeris version:", swiss_ephemeris_version())
    print(f"Ephemeris path: {EPHE_PATH}")
    print()

    print("BIRTH DATA")
    print(f"Date: {BIRTH_DATA['year']}-{BIRTH_DATA['month']:02d}-{BIRTH_DATA['day']:02d}")
    print(f"Time: {BIRTH_DATA['hour']:02d}:{BIRTH_DATA['minute']:02d}")
    print(f"Latitude: {BIRTH_DATA['latitude']:.4f}")
    print(f"Longitude: {BIRTH_DATA['longitude']:.4f}")
    print(f"Timezone: {format_timezone(BIRTH_DATA['timezone_offset'])}")
    print(f"UTC Date/Time: {utc_dt.strftime('%Y-%m-%d %H:%M')}")
    print()

    print("JULIAN DAY")
    print(f"{jd_ut:.8f}")
    print()

    print("EPHEMERIS")
    for source in sorted(ephemeris_sources):
        print(source)
    if "Moshier fallback" in ephemeris_sources:
        print(f"Warning: Swiss Ephemeris data files were not found in {EPHE_PATH}.")
    print()

    print("PLANETS")
    print()
    for name, values in planets.items():
        print(f"{name}:")
        print(f"  Longitude: {format_degrees(values['longitude'])}")
        print(f"  Latitude: {format_signed_degrees(values['latitude'])}")
        print(f"  Speed: {values['speed']:+.6f}{DEGREE_SYMBOL}/day")
        print(f"  Retrograde: {'Yes' if values['retrograde'] else 'No'}")
        print()

    print("ANGLES")
    print()
    print(f"ASC: {format_degrees(angles['ASC'])}")
    print(f"MC: {format_degrees(angles['MC'])}")
    print()

    print("HOUSE CUSPS")
    print()
    for index, cusp in enumerate(house_cusps, start=1):
        print(f"{index}: {format_degrees(cusp)}")


if __name__ == "__main__":
    print_chart()
