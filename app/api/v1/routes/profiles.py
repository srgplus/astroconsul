from __future__ import annotations

from datetime import date

from fastapi import APIRouter, Depends, HTTPException

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


@router.get("", response_model=ProfileListResponse)
def list_profiles(
    profile_service: ProfileService = Depends(get_profile_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    return profile_service.list_profiles(repos.profiles)


@router.post("", response_model=ProfileDetailResponse)
def create_profile(
    payload: NatalProfileUpsertRequest,
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
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/{profile_id}", response_model=ProfileDetailResponse)
def profile_detail(
    profile_id: str,
    profile_service: ProfileService = Depends(get_profile_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    try:
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
    chart_service: ChartService = Depends(get_chart_service),
    profile_service: ProfileService = Depends(get_profile_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    try:
        existing_profile = repos.profiles.load_profile(profile_id)
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
    transit_service: TransitService = Depends(get_transit_service),
    location_service: LocationLookupService = Depends(get_location_lookup_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
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
    transit_service: TransitService = Depends(get_transit_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
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
