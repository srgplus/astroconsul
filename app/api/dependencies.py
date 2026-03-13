from __future__ import annotations

from functools import lru_cache

from app.application.services.chart_service import ChartService
from app.application.services.health_service import HealthService
from app.application.services.location_lookup_service import LocationLookupService
from app.application.services.profile_service import ProfileService
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


def get_location_lookup_service() -> LocationLookupService:
    repositories = get_repository_bundle(get_settings())
    return LocationLookupService(cache_repository=repositories.locations)


@lru_cache(maxsize=1)
def get_health_service() -> HealthService:
    return HealthService(get_settings())


def get_repositories():
    return get_repository_bundle(get_settings())


def clear_dependency_caches() -> None:
    get_chart_service.cache_clear()
    get_profile_service.cache_clear()
    get_transit_service.cache_clear()
    get_health_service.cache_clear()
