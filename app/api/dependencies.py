from __future__ import annotations

from functools import lru_cache
from typing import Any

from fastapi import Depends, HTTPException

from app.api.auth import get_current_user
from app.api.paywall import caller_is_pro
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


def require_pro(
    user: dict[str, Any] = Depends(get_current_user),
    is_pro: bool = Depends(caller_is_pro),
) -> dict[str, Any]:
    """FastAPI dependency for a route that is Pro in its *entirety*.

    ``user: dict = Depends(require_pro)`` in the route signature: returns the
    user when the subscription is active, 403 otherwise. It used to be written
    as a factory returning the real check, so the usage its own docstring
    prescribed injected that inner function as the "user" and checked nothing.

    A route that is only *partly* paid must not use this. The transit report
    and the chart endpoints serve a free tier its allowance of written
    interpretations, so turning them into 403s would take that away — they
    trim the response instead, in :mod:`app.api.paywall`.

    ``get_user_subscription`` normalises every non-Pro answer to the free
    plan, expired subscriptions included, so the detail names it directly.
    """
    if not is_pro:
        raise HTTPException(status_code=403, detail={"error": "pro_required", "plan": "free"})
    return user


def clear_dependency_caches() -> None:
    get_chart_service.cache_clear()
    get_profile_service.cache_clear()
    get_transit_service.cache_clear()
    get_synastry_service.cache_clear()
    get_health_service.cache_clear()
