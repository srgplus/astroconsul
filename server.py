from __future__ import annotations

from datetime import date, datetime, time, timezone
from pathlib import Path
from typing import Any, Optional, Union
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from astro_utils import parse_time_string, time_to_decimal_hours
from chart_builder import build_chart, chart_needs_upgrade, make_chart_id, save_chart
from chart_builder import swiss_ephemeris_version
from location_service import LocationResolutionError, resolve_location_name
from natal_profiles import (
    UsernameConflictError,
    bootstrap_profiles,
    create_profile,
    delete_chart_if_unreferenced,
    list_profile_summaries,
    load_profile,
    profile_summary,
    resolve_profile_chart_id,
    save_profile_latest_transit,
    update_profile,
)
from transit_builder import build_transit_report
from transit_builder import load_saved_chart
from transit_timeline import build_transit_timeline

app = FastAPI(title="Astro Consul MVP UI")

BASE_DIR = Path(__file__).resolve().parent
TEMPLATE_PATH = BASE_DIR / "templates" / "index.html"


class NatalChartCreateRequest(BaseModel):
    birth_date: date
    birth_time: Union[str, float]
    timezone: Optional[str] = None
    name: Optional[str] = None
    location_name: Optional[str] = None
    latitude: float
    longitude: float
    time_basis: Optional[str] = None


class TransitReportRequest(BaseModel):
    chart_id: Optional[str] = None
    profile_id: Optional[str] = None
    transit_date: str
    transit_time: str
    timezone: Optional[str] = None
    location_name: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    include_timing: bool = False


class TransitTimelineRequest(BaseModel):
    chart_id: Optional[str] = None
    profile_id: Optional[str] = None
    start_date: date
    end_date: date
    timezone: str


class NatalProfileUpsertRequest(NatalChartCreateRequest):
    profile_name: str
    username: str


class LocationResolveRequest(BaseModel):
    location_name: str


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


def decimal_hour_to_time(value: float, field_name: str) -> time:
    if value < 0 or value >= 24:
        raise ValueError(f"{field_name} must be between 0 and 24 hours.")

    total_seconds = int(round(value * 3600))
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    return time(hour=hours, minute=minutes, second=seconds)


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


def ensure_chart_reference(chart_id: Optional[str], profile_id: Optional[str]) -> str:
    if profile_id and profile_id.strip():
        return resolve_profile_chart_id(profile_id.strip())
    if chart_id and chart_id.strip():
        return chart_id.strip()
    raise ValueError("Either profile_id or chart_id is required.")


def build_saved_chart_response(chart_id: str, chart_path: Path, chart: dict[str, Any]) -> dict[str, Any]:
    if chart_needs_upgrade(chart) and chart_path.exists():
        chart_path, chart = load_saved_chart(str(chart_path))

    birth_input = chart.get("birth_input") or {}
    angles = chart.get("angles") or {}
    return {
        "chart_id": chart_id,
        "chart_path": str(chart_path),
        "name": birth_input.get("name"),
        "location_name": birth_input.get("location_name"),
        "local_birth_datetime": birth_input.get("local_birth_datetime"),
        "utc_birth_datetime": birth_input.get("utc_birth_datetime"),
        "julian_day": chart.get("julian_day"),
        "asc": angles.get("asc"),
        "mc": angles.get("mc"),
        "house_system": chart.get("house_system"),
        "natal_aspect_count": len(chart.get("natal_aspects", [])),
        "birth_input": birth_input,
        "planets": chart.get("planets"),
        "natal_positions": chart.get("natal_positions"),
        "houses": chart.get("houses"),
        "angles": angles,
        "angle_positions": chart.get("angle_positions"),
        "natal_aspects": chart.get("natal_aspects"),
        "natal_summary": chart.get("natal_summary"),
    }


def build_chart_from_request(payload: NatalChartCreateRequest) -> tuple[str, Path, dict[str, Any]]:
    try:
        time_basis = resolve_time_basis(payload.time_basis, payload.timezone)

        if time_basis == "local":
            local_dt, utc_dt = convert_local_datetime(
                payload.birth_date,
                payload.birth_time,
                payload.timezone or "",
                field_name="birth_time",
            )
            chart_date = utc_dt.date()
            ut_hour = time_to_decimal_hours(utc_dt.time())
            input_timezone = payload.timezone or "UTC"
        else:
            ut_hour = parse_ut_birth_time(payload.birth_time)
            local_dt = datetime.combine(
                payload.birth_date,
                decimal_hour_to_time(ut_hour, "birth_time"),
                tzinfo=timezone.utc,
            )
            utc_dt = local_dt
            chart_date = payload.birth_date
            input_timezone = "UTC"
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    chart = build_chart(
        chart_date.year,
        chart_date.month,
        chart_date.day,
        ut_hour,
        payload.latitude,
        payload.longitude,
        birth_input={
            "name": payload.name,
            "birth_date": payload.birth_date.isoformat(),
            "birth_time": str(payload.birth_time),
            "timezone": input_timezone,
            "location_name": payload.location_name,
            "local_birth_datetime": format_datetime(local_dt),
            "utc_birth_datetime": format_datetime(utc_dt),
            "latitude": payload.latitude,
            "longitude": payload.longitude,
            "time_basis": time_basis,
        },
    )
    chart_id = make_chart_id(
        chart_date.year,
        chart_date.month,
        chart_date.day,
        ut_hour,
    )
    saved_chart_id, output_path = save_chart(chart, chart_id=chart_id)
    return saved_chart_id, output_path, chart


@app.get("/", response_class=HTMLResponse)
def home() -> HTMLResponse:
    return HTMLResponse(TEMPLATE_PATH.read_text(encoding="utf-8"))


@app.post("/resolve-location")
def resolve_location(payload: LocationResolveRequest) -> dict[str, object]:
    try:
        return resolve_location_name(payload.location_name)
    except LocationResolutionError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.get("/natal")
def calculate_chart(
    year: int,
    month: int,
    day: int,
    hour: float,
    lat: float,
    lon: float,
) -> dict[str, object]:
    chart = build_chart(year, month, day, hour, lat, lon)

    return {
        "julian_day": chart["julian_day"],
        "swiss_ephemeris_version": chart["swiss_ephemeris_version"],
        "ephemeris_path": chart["ephemeris_path"],
        "ephemeris_sources": chart["ephemeris_sources"],
        "planets": chart["planets"],
        "natal_positions": chart["natal_positions"],
        "asc": chart["angles"]["asc"],
        "mc": chart["angles"]["mc"],
        "angles": chart["angles"],
        "angle_positions": chart.get("angle_positions"),
        "houses": chart["houses"],
        "natal_aspects": chart["natal_aspects"],
        "natal_summary": chart.get("natal_summary"),
    }


@app.post("/create-natal-chart")
def create_natal_chart(payload: NatalChartCreateRequest) -> dict[str, object]:
    chart_id, chart_path, chart = build_chart_from_request(payload)
    return build_saved_chart_response(chart_id, chart_path, chart)


@app.get("/natal-profiles")
def natal_profiles() -> dict[str, object]:
    bootstrap_profiles()
    return {"profiles": list_profile_summaries()}


@app.get("/natal-profiles/{profile_id}")
def natal_profile_detail(profile_id: str) -> dict[str, object]:
    _, profile = load_profile(profile_id)
    chart_path, chart = load_saved_chart(str(profile["chart_id"]))
    return {
        "profile": profile_summary(profile, chart),
        "chart": build_saved_chart_response(str(profile["chart_id"]), chart_path, chart),
    }


@app.post("/natal-profiles")
def create_natal_profile(payload: NatalProfileUpsertRequest) -> dict[str, object]:
    try:
        chart_id, chart_path, chart = build_chart_from_request(payload)
        profile = create_profile(
            payload.profile_name,
            payload.username,
            chart_id,
        )
    except UsernameConflictError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {
        "profile": profile_summary(profile, chart),
        "chart": build_saved_chart_response(chart_id, chart_path, chart),
    }


@app.put("/natal-profiles/{profile_id}")
def update_natal_profile(profile_id: str, payload: NatalProfileUpsertRequest) -> dict[str, object]:
    try:
        _, existing_profile = load_profile(profile_id)
        previous_chart_id = str(existing_profile["chart_id"])
        chart_id, chart_path, chart = build_chart_from_request(payload)
        profile = update_profile(
            profile_id,
            payload.profile_name,
            payload.username,
            chart_id,
        )
        if chart_id != previous_chart_id:
            delete_chart_if_unreferenced(previous_chart_id, exclude_profile_id=profile_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except UsernameConflictError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {
        "profile": profile_summary(profile, chart),
        "chart": build_saved_chart_response(chart_id, chart_path, chart),
    }


@app.post("/transit-report")
def transit_report(payload: TransitReportRequest) -> dict[str, object]:
    try:
        transit_date = date.fromisoformat(payload.transit_date)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="transit_date must be in YYYY-MM-DD format.") from exc

    transit_location_name = payload.location_name.strip() if payload.location_name else None
    transit_latitude = payload.latitude
    transit_longitude = payload.longitude
    resolved_transit_location = None

    if not transit_location_name:
        transit_latitude = None
        transit_longitude = None

    if (transit_latitude is None) != (transit_longitude is None):
        raise HTTPException(status_code=400, detail="latitude and longitude must be provided together.")

    if transit_location_name and transit_latitude is None and transit_longitude is None:
        try:
            resolved_transit_location = resolve_location_name(transit_location_name)
        except LocationResolutionError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        transit_location_name = str(resolved_transit_location["resolved_name"])
        transit_latitude = float(resolved_transit_location["latitude"])
        transit_longitude = float(resolved_transit_location["longitude"])

    try:
        chart_id = ensure_chart_reference(payload.chart_id, payload.profile_id)
        effective_timezone = payload.timezone
        if (effective_timezone is None or not effective_timezone.strip()) and resolved_transit_location is not None:
            effective_timezone = str(resolved_transit_location["timezone"])

        if effective_timezone and effective_timezone.strip():
            local_dt, utc_dt = convert_local_datetime(
                transit_date,
                payload.transit_time,
                effective_timezone,
                field_name="transit_time",
            )
            transit_timezone = effective_timezone
        else:
            utc_time = parse_time_string(payload.transit_time)
            utc_dt = datetime.combine(transit_date, utc_time, tzinfo=timezone.utc)
            local_dt = utc_dt
            transit_timezone = "UTC"

        report = build_transit_report(
            chart_id,
            utc_dt.date().isoformat(),
            utc_dt.strftime("%H:%M:%S"),
            include_timing=payload.include_timing,
            transit_latitude=transit_latitude,
            transit_longitude=transit_longitude,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    snapshot = dict(report.get("snapshot", {}))
    chart_filename = str(snapshot.get("chart_id", chart_id))
    chart_path = Path(chart_filename)
    ephemeris_version = swiss_ephemeris_version()

    snapshot.update(
        {
            "chart_id": chart_path.stem,
            "profile_id": payload.profile_id,
            "chart_filename": chart_path.name,
            "transit_local_datetime": format_datetime(local_dt),
            "transit_timezone": transit_timezone,
            "transit_utc_datetime": format_datetime(utc_dt),
            "transit_date": utc_dt.date().isoformat(),
            "transit_time_ut": utc_dt.strftime("%H:%M:%S"),
            "house_system": snapshot.get("house_system"),
            "ephemeris_version": ephemeris_version,
            "ephemeris": f"Swiss Ephemeris {ephemeris_version}",
            "transit_location_name": transit_location_name,
            "transit_latitude": transit_latitude,
            "transit_longitude": transit_longitude,
        }
    )

    if payload.profile_id:
        save_profile_latest_transit(
            payload.profile_id,
            {
                "transit_date": local_dt.date().isoformat(),
                "transit_time": local_dt.time().replace(microsecond=0).isoformat(),
                "timezone": transit_timezone,
                "location_name": transit_location_name,
                "latitude": transit_latitude,
                "longitude": transit_longitude,
            },
        )

    report["snapshot"] = snapshot
    return report


@app.post("/transit-timeline")
def transit_timeline(payload: TransitTimelineRequest) -> dict[str, object]:
    try:
        chart_id = ensure_chart_reference(payload.chart_id, payload.profile_id)
        timeline = build_transit_timeline(
            chart_id,
            payload.start_date,
            payload.end_date,
            payload.timezone,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {"timeline": timeline}
