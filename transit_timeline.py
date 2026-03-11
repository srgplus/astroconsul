from __future__ import annotations

from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from transit_builder import build_transit_report

TIMELINE_STEP = timedelta(days=1)
STRENGTH_ORDER = {
    "exact": 4,
    "strong": 3,
    "moderate": 2,
    "wide": 1,
}


def parse_utc_datetime(value: str | None) -> datetime | None:
    if value is None:
        return None

    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def format_utc_datetime(value: datetime | None) -> str | None:
    if value is None:
        return None

    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def aspect_key(record: dict[str, object]) -> tuple[str, str, str]:
    return (
        str(record["transit"]),
        str(record["natal"]),
        str(record["aspect"]),
    )


def aspect_key_from_record(record: dict[str, object]) -> tuple[str, str, str]:
    return (
        str(record["transit_object"]),
        str(record["natal_object"]),
        str(record["aspect"]),
    )


def choose_display_utc(
    start_utc: datetime | None,
    exact_utc: datetime | None,
    end_utc: datetime | None,
    range_start_utc: datetime,
    range_end_utc: datetime,
) -> datetime | None:
    if exact_utc is not None:
        if range_start_utc <= exact_utc <= range_end_utc:
            return exact_utc
        return None

    if end_utc is None or end_utc < range_start_utc:
        return None

    if start_utc is not None:
        if start_utc > range_end_utc:
            return None
        if start_utc >= range_start_utc:
            return start_utc

    return range_start_utc


def stronger_strength(current: str, candidate: str) -> str:
    if STRENGTH_ORDER.get(candidate, 0) > STRENGTH_ORDER.get(current, 0):
        return candidate
    return current


def should_replace(existing: dict[str, object], candidate: dict[str, object]) -> bool:
    existing_display = parse_utc_datetime(existing["display_utc"])
    candidate_display = parse_utc_datetime(candidate["display_utc"])
    if existing_display is None:
        return candidate_display is not None
    if candidate_display is None:
        return False
    if candidate_display != existing_display:
        return candidate_display < existing_display

    existing_start = parse_utc_datetime(existing["start_utc"])
    candidate_start = parse_utc_datetime(candidate["start_utc"])
    if existing_start is None:
        return candidate_start is not None
    if candidate_start is None:
        return False
    return candidate_start < existing_start


def timeline_item_from_run(
    run: dict[str, object],
    run_end_local: datetime,
    range_start_utc: datetime,
    range_end_utc: datetime,
) -> dict[str, object] | None:
    start_utc = run["start_local"].astimezone(timezone.utc)
    end_utc = min(run_end_local, run["range_end_local"]).astimezone(timezone.utc)
    exact_utc = None
    display_utc = choose_display_utc(start_utc, exact_utc, end_utc, range_start_utc, range_end_utc)
    if display_utc is None:
        return None

    return {
        "transit": str(run["transit"]),
        "aspect": str(run["aspect"]),
        "natal": str(run["natal"]),
        "start_utc": format_utc_datetime(start_utc),
        "exact_utc": None,
        "end_utc": format_utc_datetime(end_utc),
        "display_utc": format_utc_datetime(display_utc),
        "strength": str(run["strength"]),
    }


def sort_key(item: dict[str, object]) -> tuple[datetime, datetime, str, str, str]:
    display_utc = parse_utc_datetime(item["display_utc"])
    start_utc = parse_utc_datetime(item["start_utc"])
    anchor = display_utc or datetime.max.replace(tzinfo=timezone.utc)
    fallback = start_utc or anchor
    return (
        anchor,
        fallback,
        str(item["transit"]),
        str(item["aspect"]),
        str(item["natal"]),
    )


def build_transit_timeline(
    chart_id: str,
    start_date: date,
    end_date: date,
    timezone_name: str,
) -> list[dict[str, object]]:
    if end_date < start_date:
        raise ValueError("end_date must be on or after start_date.")
    if not timezone_name.strip():
        raise ValueError("timezone is required.")

    try:
        tzinfo = ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError as exc:
        raise ValueError("timezone must be a valid IANA timezone, e.g. America/Los_Angeles.") from exc

    range_start_local = datetime.combine(start_date, time.min, tzinfo=tzinfo)
    range_end_local = datetime.combine(end_date, time(hour=23, minute=59, second=59), tzinfo=tzinfo)
    range_start_utc = range_start_local.astimezone(timezone.utc)
    range_end_utc = range_end_local.astimezone(timezone.utc)

    timeline_by_key: dict[tuple[str, str, str], dict[str, object]] = {}
    active_runs: dict[tuple[str, str, str], dict[str, object]] = {}
    cursor_local = range_start_local

    while cursor_local <= range_end_local:
        cursor_utc = cursor_local.astimezone(timezone.utc)
        report = build_transit_report(
            chart_id,
            cursor_utc.date().isoformat(),
            cursor_utc.strftime("%H:%M:%S"),
            include_timing=False,
        )
        active_keys_this_sample: set[tuple[str, str, str]] = set()

        for aspect_record in report["active_aspects"]:
            if str(aspect_record["transit_object"]) == "Moon":
                continue

            key = aspect_key_from_record(aspect_record)
            active_keys_this_sample.add(key)
            run = active_runs.get(key)

            if run is None:
                active_runs[key] = {
                    "transit": str(aspect_record["transit_object"]),
                    "aspect": str(aspect_record["aspect"]),
                    "natal": str(aspect_record["natal_object"]),
                    "strength": str(aspect_record["strength"]),
                    "start_local": cursor_local,
                    "last_seen_local": cursor_local,
                    "range_end_local": range_end_local,
                }
                continue

            run["last_seen_local"] = cursor_local
            run["strength"] = stronger_strength(str(run["strength"]), str(aspect_record["strength"]))

        finished_keys = [key for key in active_runs if key not in active_keys_this_sample]
        for key in finished_keys:
            run = active_runs.pop(key)
            run_end_local = run["last_seen_local"] + TIMELINE_STEP
            item = timeline_item_from_run(run, run_end_local, range_start_utc, range_end_utc)
            if item is None:
                continue

            existing = timeline_by_key.get(key)
            if existing is None or should_replace(existing, item):
                timeline_by_key[key] = item

        cursor_local += TIMELINE_STEP

    for key, run in active_runs.items():
        item = timeline_item_from_run(run, cursor_local, range_start_utc, range_end_utc)
        if item is None:
            continue

        existing = timeline_by_key.get(key)
        if existing is None or should_replace(existing, item):
            timeline_by_key[key] = item

    return sorted(timeline_by_key.values(), key=sort_key)
