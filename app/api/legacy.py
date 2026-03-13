from __future__ import annotations

from fastapi import APIRouter

from app.api.handlers import (
    calculate_chart_handler,
    create_natal_chart_handler,
    create_profile_handler,
    list_profiles_handler,
    profile_detail_handler,
    resolve_location_handler,
    transit_report_handler,
    transit_timeline_handler,
    update_profile_handler,
)
from app.schemas.requests import (
    LocationResolveRequest,
    NatalChartCreateRequest,
    NatalProfileUpsertRequest,
    TransitReportRequest,
    TransitTimelineRequest,
)

router = APIRouter()


@router.post("/resolve-location")
def resolve_location(payload: LocationResolveRequest) -> dict[str, object]:
    return resolve_location_handler(payload)


@router.get("/natal")
def calculate_chart(
    year: int,
    month: int,
    day: int,
    hour: float,
    lat: float,
    lon: float,
) -> dict[str, object]:
    return calculate_chart_handler(year, month, day, hour, lat, lon)


@router.post("/create-natal-chart")
def create_natal_chart(payload: NatalChartCreateRequest) -> dict[str, object]:
    return create_natal_chart_handler(payload)


@router.get("/natal-profiles")
def natal_profiles() -> dict[str, object]:
    return list_profiles_handler()


@router.get("/natal-profiles/{profile_id}")
def natal_profile_detail(profile_id: str) -> dict[str, object]:
    return profile_detail_handler(profile_id)


@router.post("/natal-profiles")
def create_natal_profile(payload: NatalProfileUpsertRequest) -> dict[str, object]:
    return create_profile_handler(payload)


@router.put("/natal-profiles/{profile_id}")
def update_natal_profile(profile_id: str, payload: NatalProfileUpsertRequest) -> dict[str, object]:
    return update_profile_handler(profile_id, payload)


@router.post("/transit-report")
def transit_report(payload: TransitReportRequest) -> dict[str, object]:
    return transit_report_handler(payload)


@router.post("/transit-timeline")
def transit_timeline(payload: TransitTimelineRequest) -> dict[str, object]:
    return transit_timeline_handler(payload)

