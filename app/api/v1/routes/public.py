from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query

from app.api.dependencies import (
    get_profile_service,
    get_repositories,
)
from app.api.v1.routes.profiles import _build_natal_interpretations
from app.application.services.profile_service import ProfileService
from app.infrastructure.repositories.factory import RepositoryBundle

router = APIRouter(prefix="/public", tags=["public"])


@router.get("/featured")
def get_featured_profiles(
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    profiles = repos.profiles.list_featured(limit=6)
    # Strip user_id from response — public callers don't need it
    for p in profiles:
        p.pop("user_id", None)
    return {"profiles": profiles}


@router.get("/profiles/{profile_id}")
def get_public_profile_detail(
    profile_id: str,
    lang: str = Query("en"),
    profile_service: ProfileService = Depends(get_profile_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    try:
        # Use load_profile_with_social to get profile + followers in one session
        profile_data = repos.profiles.load_profile_with_social(profile_id, "")
        result = profile_service.profile_detail_from_loaded(
            profile_data,
            chart_repository=repos.charts,
        )
        result["chart"]["natal_interpretations"] = _build_natal_interpretations(
            result["chart"], lang,
        )
        # Public view: only followers_count, no user-specific fields
        result["profile"]["followers_count"] = profile_data["followers_count"]
        return result
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
