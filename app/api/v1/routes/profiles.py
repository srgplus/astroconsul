from __future__ import annotations

from datetime import date
from typing import Any

from fastapi import APIRouter, Depends, HTTPException

from app.api.auth import get_current_user
from app.api.dependencies import (
    get_chart_service,
    get_location_lookup_service,
    get_profile_service,
    get_repositories,
    get_transit_service,
)
from app.application.services.chart_service import ChartService
from app.application.services.location_lookup_service import LocationLookupService
from app.application.services.profile_service import ProfileService
from app.application.services.transit_service import TransitService
from app.domain.astrology.locations import LocationResolutionError, resolve_location_name
from app.infrastructure.repositories.factory import RepositoryBundle
from app.schemas.requests import (
    NatalProfileUpsertRequest,
    ProfileTransitReportRequest,
    TransitReportRequest,
    TransitTimelineRequest,
)
from app.schemas.responses import (
    ProfileDetailResponse,
    ProfileListResponse,
    TransitReportResponse,
    TransitTimelineResponse,
)

router = APIRouter(prefix="/profiles", tags=["profiles"])


def _verify_ownership(profile: dict[str, Any], user_id: str) -> None:
    """Raise 403 if the profile doesn't belong to this user."""
    owner = profile.get("user_id", "user_local_dev")
    if owner != user_id:
        raise HTTPException(status_code=403, detail="Not your profile")


@router.get("", response_model=ProfileListResponse)
def list_profiles(
    user: dict[str, Any] = Depends(get_current_user),
    profile_service: ProfileService = Depends(get_profile_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    return profile_service.list_profiles(repos.profiles, user_id=user["user_id"])


@router.post("", response_model=ProfileDetailResponse)
def create_profile(
    payload: NatalProfileUpsertRequest,
    user: dict[str, Any] = Depends(get_current_user),
    chart_service: ChartService = Depends(get_chart_service),
    profile_service: ProfileService = Depends(get_profile_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    try:
        chart_id, chart_reference, chart = chart_service.build_chart_from_request(
            payload,
            save_chart_fn=repos.charts.save_chart,
        )
        return profile_service.create_profile(
            payload,
            chart_id=chart_id,
            chart_reference=str(chart_reference),
            chart=chart,
            profile_repository=repos.profiles,
            user_id=user["user_id"],
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/{profile_id}", response_model=ProfileDetailResponse)
def profile_detail(
    profile_id: str,
    user: dict[str, Any] = Depends(get_current_user),
    profile_service: ProfileService = Depends(get_profile_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    try:
        profile = repos.profiles.load_profile(profile_id)
        _verify_ownership(profile, user["user_id"])
        return profile_service.profile_detail(
            profile_id,
            profile_repository=repos.profiles,
            chart_repository=repos.charts,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.patch("/{profile_id}", response_model=ProfileDetailResponse)
def update_profile(
    profile_id: str,
    payload: NatalProfileUpsertRequest,
    user: dict[str, Any] = Depends(get_current_user),
    chart_service: ChartService = Depends(get_chart_service),
    profile_service: ProfileService = Depends(get_profile_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    try:
        existing_profile = repos.profiles.load_profile(profile_id)
        _verify_ownership(existing_profile, user["user_id"])
        previous_chart_id = str(existing_profile["chart_id"])
        chart_id, chart_reference, chart = chart_service.build_chart_from_request(
            payload,
            save_chart_fn=repos.charts.save_chart,
        )
        return profile_service.update_profile(
            profile_id,
            payload,
            previous_chart_id=previous_chart_id,
            chart_id=chart_id,
            chart_reference=str(chart_reference),
            chart=chart,
            profile_repository=repos.profiles,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/{profile_id}/transits/report", response_model=TransitReportResponse)
def profile_transit_report(
    profile_id: str,
    payload: ProfileTransitReportRequest,
    user: dict[str, Any] = Depends(get_current_user),
    transit_service: TransitService = Depends(get_transit_service),
    location_service: LocationLookupService = Depends(get_location_lookup_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    profile = repos.profiles.load_profile(profile_id)
    _verify_ownership(profile, user["user_id"])
    request = TransitReportRequest(profile_id=profile_id, **payload.model_dump())
    try:
        return transit_service.build_report(
            request,
            profile_repository=repos.profiles,
            location_resolver=lambda name: location_service.resolve(name, resolver=resolve_location_name),
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except (LocationResolutionError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/{profile_id}/transits/timeline", response_model=TransitTimelineResponse)
def profile_transit_timeline(
    profile_id: str,
    start_date: date,
    end_date: date,
    timezone: str,
    user: dict[str, Any] = Depends(get_current_user),
    transit_service: TransitService = Depends(get_transit_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    profile = repos.profiles.load_profile(profile_id)
    _verify_ownership(profile, user["user_id"])
    request = TransitTimelineRequest(
        profile_id=profile_id,
        start_date=start_date,
        end_date=end_date,
        timezone=timezone,
    )
    try:
        return transit_service.build_timeline(request, profile_repository=repos.profiles)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
