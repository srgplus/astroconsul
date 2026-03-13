from __future__ import annotations

from datetime import date, datetime, time, timezone
from typing import Optional, Union
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.domain.astrology.utils import parse_time_string


def parse_ut_birth_time(value: Union[str, float]) -> float:
    if isinstance(value, (int, float)):
        hour = float(value)
    else:
        raw_value = value.strip()

        if ":" in raw_value:
            parts = raw_value.split(":")
            if len(parts) not in (2, 3):
                raise ValueError("birth_time must be decimal UT or HH:MM[:SS].")

            hours = int(parts[0])
            minutes = int(parts[1])
            seconds = int(parts[2]) if len(parts) == 3 else 0
            hour = hours + minutes / 60 + seconds / 3600
        else:
            hour = float(raw_value)

    if hour < 0 or hour >= 24:
        raise ValueError("birth_time must be in UT decimal hours between 0 and 24.")

    return hour


def format_datetime(value: datetime) -> str:
    formatted = value.isoformat(timespec="seconds")
    return formatted.replace("+00:00", "Z")


def resolve_time_basis(time_basis: Optional[str], timezone_name: Optional[str]) -> str:
    if time_basis is None:
        return "local" if timezone_name and timezone_name.strip() else "UT"

    normalized = time_basis.strip().upper()
    if normalized in {"UT", "UTC"}:
        return "UT"
    if normalized == "LOCAL":
        return "local"

    raise ValueError("time_basis must be either 'UT' or 'local'.")


def decimal_hour_to_time(value: float, field_name: str) -> time:
    if value < 0 or value >= 24:
        raise ValueError(f"{field_name} must be between 0 and 24 hours.")

    total_seconds = int(round(value * 3600))
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    return time(hour=hours, minute=minutes, second=seconds)


def parse_clock_time(value: Union[str, float], field_name: str) -> time:
    if isinstance(value, (int, float)):
        decimal_hour = float(value)
        return decimal_hour_to_time(decimal_hour, field_name)

    raw_value = value.strip()

    if ":" not in raw_value:
        try:
            return decimal_hour_to_time(float(raw_value), field_name)
        except ValueError as exc:
            raise ValueError(f"{field_name} must be in HH:MM or HH:MM:SS format.") from exc

    return parse_time_string(raw_value)


def parse_local_clock_time(value: Union[str, float], field_name: str) -> time:
    if isinstance(value, (int, float)):
        return decimal_hour_to_time(float(value), field_name)

    raw_value = value.strip()

    if ":" not in raw_value:
        raise ValueError(f"{field_name} must be in HH:MM or HH:MM:SS format.")

    return parse_time_string(raw_value)


def convert_local_datetime(
    local_date: date,
    local_time_value: Union[str, float],
    timezone_name: str,
    *,
    field_name: str,
) -> tuple[datetime, datetime]:
    if not timezone_name.strip():
        raise ValueError("timezone is required when using local datetime input.")

    try:
        tzinfo = ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError as exc:
        raise ValueError("timezone must be a valid IANA timezone, e.g. Europe/Minsk.") from exc

    local_time = parse_local_clock_time(local_time_value, field_name)
    local_dt = datetime.combine(local_date, local_time, tzinfo=tzinfo)
    utc_dt = local_dt.astimezone(timezone.utc)
    return local_dt, utc_dt


def ensure_chart_reference(chart_id: Optional[str], profile_id: Optional[str], *, resolver) -> str:
    if profile_id and profile_id.strip():
        return resolver(profile_id.strip())
    if chart_id and chart_id.strip():
        return chart_id.strip()
    raise ValueError("Either profile_id or chart_id is required.")

