from __future__ import annotations

from fastapi import HTTPException

from app.api.dependencies import (
    get_chart_service,
    get_location_lookup_service,
    get_profile_service,
    get_repositories,
    get_transit_service,
)
from app.domain.astrology.charts import build_chart
from app.domain.astrology.locations import LocationResolutionError, resolve_location_name


def resolve_location_handler(payload) -> dict[str, object]:
    try:
        location_service = get_location_lookup_service()
        return location_service.resolve(payload.location_name, resolver=resolve_location_name)
    except (LocationResolutionError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def calculate_chart_handler(year: int, month: int, day: int, hour: float, lat: float, lon: float) -> dict[str, object]:
    chart = build_chart(year, month, day, hour, lat, lon)
    return {
        "julian_day": chart["julian_day"],
        "swiss_ephemeris_version": chart["swiss_ephemeris_version"],
        "ephemeris_path": chart["ephemeris_path"],
        "ephemeris_sources": chart["ephemeris_sources"],
        "planets": chart["planets"],
        "natal_positions": chart["natal_positions"],
        "asc": chart["angles"]["asc"],  # type: ignore[index]
        "mc": chart["angles"]["mc"],  # type: ignore[index]
        "angles": chart["angles"],
        "angle_positions": chart.get("angle_positions"),
        "houses": chart["houses"],
        "natal_aspects": chart["natal_aspects"],
        "natal_summary": chart.get("natal_summary"),
    }


def create_natal_chart_handler(payload) -> dict[str, object]:
    chart_service = get_chart_service()
    repositories = get_repositories()

    try:
        chart_id, chart_reference, chart = chart_service.build_chart_from_request(
            payload,
            save_chart_fn=repositories.charts.save_chart,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return chart_service.build_saved_chart_response(chart_id, chart_reference, chart)


def list_profiles_handler() -> dict[str, object]:
    repositories = get_repositories()
    profile_service = get_profile_service()
    return profile_service.list_profiles(repositories.profiles)


def profile_detail_handler(profile_id: str) -> dict[str, object]:
    repositories = get_repositories()
    profile_service = get_profile_service()

    try:
        return profile_service.profile_detail(
            profile_id,
            profile_repository=repositories.profiles,
            chart_repository=repositories.charts,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


def create_profile_handler(payload) -> dict[str, object]:
    repositories = get_repositories()
    chart_service = get_chart_service()
    profile_service = get_profile_service()

    try:
        chart_id, chart_reference, chart = chart_service.build_chart_from_request(
            payload,
            save_chart_fn=repositories.charts.save_chart,
        )
        return profile_service.create_profile(
            payload,
            chart_id=chart_id,
            chart_reference=str(chart_reference),
            chart=chart,
            profile_repository=repositories.profiles,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def update_profile_handler(profile_id: str, payload) -> dict[str, object]:
    repositories = get_repositories()
    chart_service = get_chart_service()
    profile_service = get_profile_service()

    try:
        existing_profile = repositories.profiles.load_profile(profile_id)
        previous_chart_id = str(existing_profile["chart_id"])
        chart_id, chart_reference, chart = chart_service.build_chart_from_request(
            payload,
            save_chart_fn=repositories.charts.save_chart,
        )
        return profile_service.update_profile(
            profile_id,
            payload,
            previous_chart_id=previous_chart_id,
            chart_id=chart_id,
            chart_reference=str(chart_reference),
            chart=chart,
            profile_repository=repositories.profiles,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def transit_report_handler(payload) -> dict[str, object]:
    repositories = get_repositories()
    transit_service = get_transit_service()
    location_service = get_location_lookup_service()

    try:
        return transit_service.build_report(
            payload,
            profile_repository=repositories.profiles,
            location_resolver=lambda location_name: location_service.resolve(
                location_name,
                resolver=resolve_location_name,
            ),
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except (LocationResolutionError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def transit_timeline_handler(payload) -> dict[str, object]:
    repositories = get_repositories()
    transit_service = get_transit_service()

    try:
        return transit_service.build_timeline(payload, profile_repository=repositories.profiles)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
