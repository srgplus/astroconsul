from __future__ import annotations

from datetime import date, datetime, time

SIGNS = [
    "Aries",
    "Taurus",
    "Gemini",
    "Cancer",
    "Leo",
    "Virgo",
    "Libra",
    "Scorpio",
    "Sagittarius",
    "Capricorn",
    "Aquarius",
    "Pisces",
]


def normalize_longitude(value: float) -> float:
    return round(value % 360, 6)


def zodiac_sign(longitude: float) -> str:
    normalized = longitude % 360
    return SIGNS[int(normalized // 30)]


def longitude_to_zodiac_position(longitude: float) -> dict[str, object]:
    normalized = longitude % 360
    sign_index = int(normalized // 30)
    position_in_sign = normalized - (sign_index * 30)
    total_seconds = int(round(position_in_sign * 3600))

    if total_seconds >= 30 * 3600:
        sign_index = (sign_index + 1) % 12
        total_seconds = 0

    degree, remainder = divmod(total_seconds, 3600)
    minute, second = divmod(remainder, 60)
    sign = SIGNS[sign_index]

    return {
        "longitude": normalize_longitude(longitude),
        "sign": sign,
        "degree": degree,
        "minute": minute,
        "second": second,
        "formatted_position": f"{degree} {sign} {minute:02d}' {second:02d}\"",
    }


def is_between_longitudes(longitude: float, start: float, end: float) -> bool:
    normalized_longitude = normalize_longitude(longitude)
    normalized_start = normalize_longitude(start)
    normalized_end = normalize_longitude(end)

    if normalized_start <= normalized_end:
        return normalized_start <= normalized_longitude < normalized_end

    return normalized_longitude >= normalized_start or normalized_longitude < normalized_end


def determine_house(longitude: float, house_cusps: list[float]) -> int:
    normalized_longitude = normalize_longitude(longitude)

    for index, start in enumerate(house_cusps):
        end = house_cusps[(index + 1) % len(house_cusps)]
        if is_between_longitudes(normalized_longitude, float(start), float(end)):
            return index + 1

    return 12


def parse_iso_date(value: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise ValueError("transit_date must be in YYYY-MM-DD format.") from exc


def parse_time_string(value: str) -> time:
    for fmt in ("%H:%M:%S", "%H:%M"):
        try:
            return datetime.strptime(value, fmt).time()
        except ValueError:
            continue

    raise ValueError("transit_time must be in HH:MM or HH:MM:SS format.")


def time_to_decimal_hours(value: time) -> float:
    return value.hour + value.minute / 60 + value.second / 3600 + value.microsecond / 3_600_000_000


def hour_to_time_token(hour: float) -> str:
    total_seconds = int(round(hour * 3600))
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)

    if seconds:
        return f"{hours:02d}{minutes:02d}{seconds:02d}"

    return f"{hours:02d}{minutes:02d}"
