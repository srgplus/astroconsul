from __future__ import annotations

from datetime import datetime, timedelta, timezone

import swisseph as swe

from aspect_engine import ASPECTS, angular_delta
from astro_utils import normalize_longitude, time_to_decimal_hours
from chart_builder import EPHE_PATH, FLAGS, TRANSIT_OBJECT_IDS

swe.set_ephe_path(str(EPHE_PATH))

TIMING_RESOLUTION = timedelta(minutes=1)
EXACT_TOLERANCE = 0.01

SCAN_SETTINGS: dict[str, dict[str, timedelta]] = {
    "Moon": {"step": timedelta(minutes=30), "horizon": timedelta(days=7)},
    "Sun": {"step": timedelta(hours=2), "horizon": timedelta(days=120)},
    "Mercury": {"step": timedelta(hours=2), "horizon": timedelta(days=120)},
    "Venus": {"step": timedelta(hours=2), "horizon": timedelta(days=120)},
    "Mars": {"step": timedelta(hours=2), "horizon": timedelta(days=120)},
    "Jupiter": {"step": timedelta(hours=12), "horizon": timedelta(days=730)},
    "Saturn": {"step": timedelta(days=1), "horizon": timedelta(days=3650)},
    "Uranus": {"step": timedelta(days=1), "horizon": timedelta(days=3650)},
    "Neptune": {"step": timedelta(days=1), "horizon": timedelta(days=3650)},
    "Pluto": {"step": timedelta(days=1), "horizon": timedelta(days=3650)},
    "North Node": {"step": timedelta(hours=12), "horizon": timedelta(days=730)},
    "South Node": {"step": timedelta(hours=12), "horizon": timedelta(days=730)},
    "Lilith": {"step": timedelta(hours=12), "horizon": timedelta(days=730)},
}


def format_utc_datetime(value: datetime | None) -> str | None:
    if value is None:
        return None

    normalized = value.astimezone(timezone.utc).replace(microsecond=0)
    return normalized.isoformat().replace("+00:00", "Z")


def timing_settings_for_object(transit_object_id: str) -> tuple[timedelta, timedelta]:
    settings = SCAN_SETTINGS.get(transit_object_id)
    if settings is None:
        raise ValueError(f"Unsupported transit object: {transit_object_id}")
    return settings["step"], settings["horizon"]


def allowed_orb_for_aspect(aspect_record: dict[str, object]) -> float:
    aspect_name = str(aspect_record["aspect"])
    exact_angle = int(aspect_record["exact_angle"])

    for aspect in ASPECTS:
        if str(aspect["name"]) == aspect_name and int(aspect["angle"]) == exact_angle:
            return float(aspect["orb"])

    raise ValueError(f"Unknown aspect configuration: {aspect_name} ({exact_angle})")


def natal_object_longitude(natal_chart: dict[str, object], natal_object_id: str) -> float:
    if natal_object_id in natal_chart["planets"]:
        return float(natal_chart["planets"][natal_object_id])
    if natal_object_id == "ASC":
        return float(natal_chart["angles"]["asc"])
    if natal_object_id == "MC":
        return float(natal_chart["angles"]["mc"])

    raise ValueError(f"Unsupported natal object: {natal_object_id}")


def compute_transit_longitude(
    transit_object_id: str,
    moment_utc: datetime,
    longitude_cache: dict[tuple[str, int], float] | None = None,
) -> float:
    normalized_moment = moment_utc.astimezone(timezone.utc)
    cache_key = (transit_object_id, int(normalized_moment.timestamp()))

    if longitude_cache is not None and cache_key in longitude_cache:
        return longitude_cache[cache_key]

    if transit_object_id == "South Node":
        north_node_longitude = compute_transit_longitude(
            "North Node",
            normalized_moment,
            longitude_cache=longitude_cache,
        )
        longitude = normalize_longitude(north_node_longitude + 180)
        if longitude_cache is not None:
            longitude_cache[cache_key] = longitude
        return longitude

    if transit_object_id not in TRANSIT_OBJECT_IDS:
        raise ValueError(f"Unsupported transit object: {transit_object_id}")

    jd = swe.julday(
        normalized_moment.year,
        normalized_moment.month,
        normalized_moment.day,
        time_to_decimal_hours(normalized_moment.timetz().replace(tzinfo=None)),
    )
    values, _ = swe.calc_ut(jd, TRANSIT_OBJECT_IDS[transit_object_id], FLAGS)
    longitude = normalize_longitude(values[0])

    if longitude_cache is not None:
        longitude_cache[cache_key] = longitude

    return longitude


def aspect_error_at(
    transit_object_id: str,
    natal_longitude: float,
    exact_angle: int,
    moment_utc: datetime,
    longitude_cache: dict[tuple[str, int], float] | None = None,
) -> float:
    transit_longitude = compute_transit_longitude(transit_object_id, moment_utc, longitude_cache=longitude_cache)
    delta = angular_delta(transit_longitude, natal_longitude)
    return round(abs(delta - exact_angle), 6)


def is_active_at(
    transit_object_id: str,
    natal_longitude: float,
    exact_angle: int,
    allowed_orb: float,
    moment_utc: datetime,
    longitude_cache: dict[tuple[str, int], float] | None = None,
) -> bool:
    return aspect_error_at(
        transit_object_id,
        natal_longitude,
        exact_angle,
        moment_utc,
        longitude_cache=longitude_cache,
    ) <= allowed_orb


def refine_boundary(
    left: datetime,
    right: datetime,
    *,
    prefer_active: bool,
    transit_object_id: str,
    natal_longitude: float,
    exact_angle: int,
    allowed_orb: float,
    longitude_cache: dict[tuple[str, int], float] | None = None,
) -> datetime:
    low = left
    high = right

    while high - low > TIMING_RESOLUTION:
        midpoint = low + (high - low) / 2
        active = is_active_at(
            transit_object_id,
            natal_longitude,
            exact_angle,
            allowed_orb,
            midpoint,
            longitude_cache=longitude_cache,
        )

        if prefer_active:
            if active:
                high = midpoint
            else:
                low = midpoint
        else:
            if active:
                low = midpoint
            else:
                high = midpoint

    return high if prefer_active else low


def scan_boundary(
    current_utc: datetime,
    *,
    direction: int,
    step: timedelta,
    horizon: timedelta,
    transit_object_id: str,
    natal_longitude: float,
    exact_angle: int,
    allowed_orb: float,
    longitude_cache: dict[tuple[str, int], float] | None = None,
) -> datetime | None:
    active_point = current_utc
    elapsed = timedelta(0)

    while elapsed < horizon:
        candidate = active_point + (step * direction)
        active = is_active_at(
            transit_object_id,
            natal_longitude,
            exact_angle,
            allowed_orb,
            candidate,
            longitude_cache=longitude_cache,
        )

        if active:
            active_point = candidate
            elapsed += step
            continue

        if direction < 0:
            return refine_boundary(
                candidate,
                active_point,
                prefer_active=True,
                transit_object_id=transit_object_id,
                natal_longitude=natal_longitude,
                exact_angle=exact_angle,
                allowed_orb=allowed_orb,
                longitude_cache=longitude_cache,
            )

        return refine_boundary(
            active_point,
            candidate,
            prefer_active=False,
            transit_object_id=transit_object_id,
            natal_longitude=natal_longitude,
            exact_angle=exact_angle,
            allowed_orb=allowed_orb,
            longitude_cache=longitude_cache,
        )

    return None


def build_search_interval(
    current_utc: datetime,
    start_utc: datetime | None,
    end_utc: datetime | None,
    horizon: timedelta,
) -> tuple[datetime, datetime]:
    search_start = start_utc if start_utc is not None else current_utc - horizon
    search_end = end_utc if end_utc is not None else current_utc + horizon
    return search_start, search_end


def sample_points(
    start_utc: datetime,
    end_utc: datetime,
    step: timedelta,
    current_utc: datetime,
) -> list[datetime]:
    samples: list[datetime] = []
    cursor = start_utc

    while cursor <= end_utc:
        samples.append(cursor)
        cursor += step

    if not samples or samples[-1] != end_utc:
        samples.append(end_utc)

    if start_utc <= current_utc <= end_utc:
        samples.append(current_utc)

    return sorted(set(samples))


def find_peak_within_interval(
    current_utc: datetime,
    *,
    start_utc: datetime,
    end_utc: datetime,
    coarse_step: timedelta,
    transit_object_id: str,
    natal_longitude: float,
    exact_angle: int,
    longitude_cache: dict[tuple[str, int], float] | None = None,
) -> tuple[datetime, float]:
    samples = sample_points(start_utc, end_utc, coarse_step, current_utc)
    scored_samples = [
        (
            moment,
            aspect_error_at(
                transit_object_id,
                natal_longitude,
                exact_angle,
                moment,
                longitude_cache=longitude_cache,
            ),
        )
        for moment in samples
    ]
    best_index, (best_moment, best_error) = min(
        enumerate(scored_samples),
        key=lambda item: (item[1][1], item[1][0]),
    )

    local_start = samples[max(0, best_index - 1)]
    local_end = samples[min(len(samples) - 1, best_index + 1)]
    if local_start == local_end:
        local_start = start_utc
        local_end = end_utc

    cursor = local_start
    while cursor <= local_end:
        error = aspect_error_at(
            transit_object_id,
            natal_longitude,
            exact_angle,
            cursor,
            longitude_cache=longitude_cache,
        )
        if error < best_error or (error == best_error and cursor < best_moment):
            best_moment = cursor
            best_error = error
        cursor += TIMING_RESOLUTION

    return best_moment, round(best_error, 6)


def timing_status(current_utc: datetime, peak_utc: datetime) -> str:
    difference = (current_utc - peak_utc).total_seconds()
    tolerance_seconds = TIMING_RESOLUTION.total_seconds()

    if abs(difference) <= tolerance_seconds:
        return "exact"
    if difference < 0:
        return "applying"
    return "separating"


def compute_active_aspect_timing(
    aspect_record: dict[str, object],
    transit_datetime_utc: datetime,
    natal_chart: dict[str, object],
    *,
    boundary_orb: float | None = None,
    longitude_cache: dict[tuple[str, int], float] | None = None,
) -> dict[str, object]:
    transit_object_id = str(aspect_record["transit_object"])
    natal_object_id = str(aspect_record["natal_object"])
    exact_angle = int(aspect_record["exact_angle"])
    allowed_orb = allowed_orb_for_aspect(aspect_record)
    active_window_orb = boundary_orb if boundary_orb is not None else allowed_orb
    natal_longitude = natal_object_longitude(natal_chart, natal_object_id)
    step, horizon = timing_settings_for_object(transit_object_id)
    current_utc = transit_datetime_utc.astimezone(timezone.utc)

    start_utc = scan_boundary(
        current_utc,
        direction=-1,
        step=step,
        horizon=horizon,
        transit_object_id=transit_object_id,
        natal_longitude=natal_longitude,
        exact_angle=exact_angle,
        allowed_orb=active_window_orb,
        longitude_cache=longitude_cache,
    )
    end_utc = scan_boundary(
        current_utc,
        direction=1,
        step=step,
        horizon=horizon,
        transit_object_id=transit_object_id,
        natal_longitude=natal_longitude,
        exact_angle=exact_angle,
        allowed_orb=active_window_orb,
        longitude_cache=longitude_cache,
    )

    search_start, search_end = build_search_interval(current_utc, start_utc, end_utc, horizon)
    peak_utc, peak_orb = find_peak_within_interval(
        current_utc,
        start_utc=search_start,
        end_utc=search_end,
        coarse_step=step,
        transit_object_id=transit_object_id,
        natal_longitude=natal_longitude,
        exact_angle=exact_angle,
        longitude_cache=longitude_cache,
    )

    exact_utc = peak_utc if peak_orb <= EXACT_TOLERANCE else None
    duration_hours = None
    if start_utc is not None and end_utc is not None:
        duration_hours = round((end_utc - start_utc).total_seconds() / 3600, 6)

    return {
        "start_utc": format_utc_datetime(start_utc),
        "peak_utc": format_utc_datetime(peak_utc),
        "exact_utc": format_utc_datetime(exact_utc),
        "end_utc": format_utc_datetime(end_utc),
        "peak_orb": peak_orb,
        "status": timing_status(current_utc, peak_utc),
        "will_perfect": exact_utc is not None,
        "duration_hours": duration_hours,
    }
