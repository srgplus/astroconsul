from __future__ import annotations

from fastapi import APIRouter

from app.api.handlers import (
    create_profile_handler,
    list_profiles_handler,
    profile_detail_handler,
    transit_report_handler,
    transit_timeline_handler,
    update_profile_handler,
)
from app.schemas.requests import (
    NatalProfileUpsertRequest,
    ProfileTransitReportRequest,
    TransitReportRequest,
    TransitTimelineRequest,
)

router = APIRouter(prefix="/profiles", tags=["profiles"])


@router.get("")
def list_profiles() -> dict[str, object]:
    return list_profiles_handler()


@router.post("")
def create_profile(payload: NatalProfileUpsertRequest) -> dict[str, object]:
    return create_profile_handler(payload)


@router.get("/{profile_id}")
def profile_detail(profile_id: str) -> dict[str, object]:
    return profile_detail_handler(profile_id)


@router.patch("/{profile_id}")
def update_profile(profile_id: str, payload: NatalProfileUpsertRequest) -> dict[str, object]:
    return update_profile_handler(profile_id, payload)


@router.post("/{profile_id}/transits/report")
def profile_transit_report(profile_id: str, payload: ProfileTransitReportRequest) -> dict[str, object]:
    return transit_report_handler(
        TransitReportRequest(profile_id=profile_id, **payload.model_dump())
    )


@router.get("/{profile_id}/transits/timeline")
def profile_transit_timeline(
    profile_id: str,
    start_date: str,
    end_date: str,
    timezone: str,
) -> dict[str, object]:
    return transit_timeline_handler(
        TransitTimelineRequest(
            profile_id=profile_id,
            start_date=start_date,
            end_date=end_date,
            timezone=timezone,
        )
    )
