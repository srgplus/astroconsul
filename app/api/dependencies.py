from __future__ import annotations

from functools import lru_cache

from app.application.services.chart_service import ChartService
from app.application.services.health_service import HealthService
from app.application.services.location_lookup_service import LocationLookupService
from app.application.services.profile_service import ProfileService
from app.application.services.synastry_service import SynastryService
from app.application.services.transit_service import TransitService
from app.core.config import get_settings
from app.infrastructure.repositories.factory import get_repository_bundle


@lru_cache(maxsize=1)
def get_chart_service() -> ChartService:
    return ChartService()


@lru_cache(maxsize=1)
def get_profile_service() -> ProfileService:
    return ProfileService(chart_service=get_chart_service())


@lru_cache(maxsize=1)
def get_transit_service() -> TransitService:
    return TransitService()


@lru_cache(maxsize=1)
def get_synastry_service() -> SynastryService:
    return SynastryService()


def get_location_lookup_service() -> LocationLookupService:
    repositories = get_repository_bundle(get_settings())
    return LocationLookupService(cache_repository=repositories.locations)


@lru_cache(maxsize=1)
def get_health_service() -> HealthService:
    return HealthService(get_settings())


def get_repositories():
    return get_repository_bundle(get_settings())


def require_pro(user: dict = None):
    """FastAPI dependency that checks Pro subscription status.

    Usage: user = Depends(require_pro) in route signature.
    Returns user dict if Pro, raises 403 if free.
    """
    from typing import Any

    from fastapi import Depends, HTTPException

    from app.api.auth import get_current_user
    from app.api.v1.routes.subscriptions import get_user_subscription

    async def _check(user: dict[str, Any] = Depends(get_current_user)):
        status = get_user_subscription(user["user_id"])
        if not status["is_pro"]:
            raise HTTPException(
                status_code=403,
                detail={"error": "pro_required", "plan": status["plan"]},
            )
        return user

    return _check


def clear_dependency_caches() -> None:
    get_chart_service.cache_clear()
    get_profile_service.cache_clear()
    get_transit_service.cache_clear()
    get_synastry_service.cache_clear()
    get_health_service.cache_clear()
