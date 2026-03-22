from __future__ import annotations

import logging
from datetime import date
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.exc import IntegrityError

logger = logging.getLogger(__name__)

from app.api.auth import get_current_user
from app.data.natal_lookup import (
    get_house_cusp_in_sign,
    get_natal_aspect,
    get_planet_in_house,
    get_planet_in_sign,
)
from app.api.dependencies import (
    get_chart_service,
    get_location_lookup_service,
    get_profile_service,
    get_repositories,
    get_synastry_service,
    get_transit_service,
)
from app.application.services.chart_service import ChartService
from app.application.services.location_lookup_service import LocationLookupService
from app.application.services.profile_service import ProfileService
from app.application.services.synastry_service import SynastryService
from app.application.services.transit_service import TransitService
from app.domain.astrology.locations import LocationResolutionError, resolve_location_name
from app.infrastructure.repositories.factory import RepositoryBundle
from app.schemas.requests import (
    ForecastRequest,
    NatalProfileUpsertRequest,
    ProfileTransitReportRequest,
    SynastryReportRequest,
    TransitReportRequest,
    TransitTimelineRequest,
)
from app.schemas.responses import (
    ForecastResponse,
    ProfileDetailResponse,
    ProfileListResponse,
    PublicProfileSearchResponse,
    SynastryReportResponse,
    TransitReportResponse,
    TransitTimelineResponse,
)

router = APIRouter(prefix="/profiles", tags=["profiles"])

# Objects that have natal interpretation entries (matches JSON data files)
_INTERP_OBJECTS = [
    "Sun", "Moon", "Mercury", "Venus", "Mars",
    "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto",
    "Chiron", "Lilith", "North Node", "Selena",
    "South Node", "Part of Fortune", "Vertex",
]


def _build_natal_interpretations(chart: dict[str, Any], lang: str) -> dict[str, Any]:
    """Build natal interpretation data from chart positions and aspects."""
    positions = chart.get("natal_positions") or []
    aspects = chart.get("natal_aspects") or []
    houses = chart.get("houses") or []

    planets_in_signs: dict[str, Any] = {}
    planets_in_houses: dict[str, Any] = {}
    for pos in positions:
        pid = pos.get("id", "")
        if pid not in _INTERP_OBJECTS:
            continue
        sign = pos.get("sign", "")
        house = pos.get("house")
        if sign:
            desc = get_planet_in_sign(pid, sign, lang)
            if desc["meaning"]:
                planets_in_signs[pid] = desc
        if house:
            desc = get_planet_in_house(pid, house, lang)
            if desc["meaning"]:
                planets_in_houses[pid] = desc

    house_cusps: dict[str, Any] = {}
    # houses is a list of longitudes for cusps 1-12
    if houses:
        signs_order = [
            "Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo",
            "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces",
        ]
        for i, cusp_lon in enumerate(houses):
            house_num = i + 1
            if isinstance(cusp_lon, (int, float)):
                sign_idx = int(cusp_lon // 30) % 12
                sign = signs_order[sign_idx]
                desc = get_house_cusp_in_sign(house_num, sign, lang)
                if desc["meaning"]:
                    house_cusps[f"house_{house_num}"] = {**desc, "sign": sign}

    aspect_interps: list[dict[str, Any]] = []
    for asp in aspects:
        p1 = asp.get("p1", "")
        p2 = asp.get("p2", "")
        aspect_type = asp.get("aspect", "")
        if not (p1 and p2 and aspect_type):
            continue
        desc = get_natal_aspect(p1, aspect_type, p2, lang)
        if desc["meaning"]:
            aspect_interps.append({
                "p1": p1, "p2": p2, "aspect": aspect_type,
                **desc,
            })

    return {
        "planets_in_signs": planets_in_signs,
        "planets_in_houses": planets_in_houses,
        "house_cusps_in_signs": house_cusps,
        "aspects": aspect_interps,
    }


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
    result = profile_service.list_profiles(repos.profiles, user_id=user["user_id"])
    result["primary_profile_id"] = repos.profiles.get_primary_profile_id(user["user_id"])
    return result


@router.put("/primary")
def set_primary_profile(
    payload: dict[str, Any],
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, str]:
    profile_id = payload.get("profile_id")
    if not profile_id or not isinstance(profile_id, str):
        raise HTTPException(status_code=400, detail="profile_id is required")
    repos.profiles.set_primary_profile_id(user["user_id"], profile_id)
    return {"status": "ok"}


@router.get("/search", response_model=PublicProfileSearchResponse)
def search_public_profiles(
    q: str = Query(..., min_length=1),
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    results = repos.profiles.search_public(q)
    current_user_id = user["user_id"]
    filtered = [r for r in results if r.get("user_id") != current_user_id]
    # Strip user_id from response — callers don't need it
    for r in filtered:
        r.pop("user_id", None)
    return {"results": filtered}


@router.post("/{profile_id}/follow")
def follow_profile(
    profile_id: str,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, str]:
    try:
        repos.profiles.load_profile(profile_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    repos.profiles.follow_profile(user["user_id"], profile_id)
    return {"status": "ok"}


@router.delete("/{profile_id}/follow")
def unfollow_profile(
    profile_id: str,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, str]:
    repos.profiles.unfollow_profile(user["user_id"], profile_id)
    return {"status": "ok"}


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
    except IntegrityError as exc:
        logger.error("Profile creation failed (IntegrityError): %s", exc)
        raise HTTPException(status_code=409, detail="Profile could not be created — possible duplicate or constraint violation.") from exc


@router.get("/{profile_id}", response_model=ProfileDetailResponse)
def profile_detail(
    profile_id: str,
    lang: str = Query("en"),
    user: dict[str, Any] = Depends(get_current_user),
    profile_service: ProfileService = Depends(get_profile_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    try:
        user_id = user["user_id"]
        # Single-session load: profile + followers/following/is_following
        profile_data = repos.profiles.load_profile_with_social(profile_id, user_id)
        # Build chart response (1 more DB session for chart load)
        result = profile_service.profile_detail_from_loaded(
            profile_data,
            chart_repository=repos.charts,
        )
        result["chart"]["natal_interpretations"] = _build_natal_interpretations(
            result["chart"], lang,
        )
        # Attach social metrics from the consolidated query
        result["profile"]["followers_count"] = profile_data["followers_count"]
        result["profile"]["following_count"] = profile_data["following_count"]
        result["profile"]["is_following"] = profile_data["is_following"]
        result["profile"]["is_own"] = profile_data["is_own"]
        return result
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.delete("/{profile_id}")
def delete_profile(
    profile_id: str,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, str]:
    try:
        repos.profiles.delete_profile(profile_id)
        return {"status": "deleted"}
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
    except IntegrityError as exc:
        logger.error("Profile update failed (IntegrityError): %s", exc)
        raise HTTPException(status_code=409, detail="Profile could not be updated — possible duplicate or constraint violation.") from exc


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
    owner = profile.get("user_id", "user_local_dev")
    user_id = user["user_id"]
    if owner != user_id and not repos.profiles.is_following(user_id, profile_id):
        raise HTTPException(status_code=403, detail="Not your profile")
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
    owner = profile.get("user_id", "user_local_dev")
    user_id = user["user_id"]
    if owner != user_id and not repos.profiles.is_following(user_id, profile_id):
        raise HTTPException(status_code=403, detail="Not your profile")
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


@router.get("/{profile_id}/transits/forecast", response_model=ForecastResponse)
def profile_transit_forecast(
    profile_id: str,
    timezone: str = Query(...),
    days: int = Query(10, ge=1, le=30),
    lang: str = Query("en"),
    user: dict[str, Any] = Depends(get_current_user),
    transit_service: TransitService = Depends(get_transit_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    profile = repos.profiles.load_profile(profile_id)
    owner = profile.get("user_id", "user_local_dev")
    user_id = user["user_id"]
    if owner != user_id and not repos.profiles.is_following(user_id, profile_id):
        raise HTTPException(status_code=403, detail="Not your profile")

    from datetime import date as date_cls

    request = ForecastRequest(
        profile_id=profile_id,
        start_date=date_cls.today(),
        days=days,
        timezone=timezone,
        lang=lang,
    )
    try:
        return transit_service.build_forecast(request, profile_repository=repos.profiles)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/{profile_id}/synastry", response_model=SynastryReportResponse)
def synastry_report(
    profile_id: str,
    payload: SynastryReportRequest,
    user: dict[str, Any] = Depends(get_current_user),
    synastry_service: SynastryService = Depends(get_synastry_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    """Compute synastry (inter-chart compatibility) between two profiles."""
    # Verify access to profile A
    profile_a = repos.profiles.load_profile(profile_id)
    owner_a = profile_a.get("user_id", "user_local_dev")
    user_id = user["user_id"]
    if owner_a != user_id and not repos.profiles.is_following(user_id, profile_id):
        raise HTTPException(status_code=403, detail="Not your profile")

    # Verify partner profile exists
    try:
        repos.profiles.load_profile(payload.partner_profile_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Partner profile not found") from exc

    try:
        return synastry_service.build_report(
            profile_id,
            payload.partner_profile_id,
            lang=payload.lang,
            profile_repository=repos.profiles,
            chart_repository=repos.charts,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
