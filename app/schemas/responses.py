from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict

# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------


class HealthCheckDetail(BaseModel):
    model_config = ConfigDict(extra="allow")
    status: str
    detail: str | None = None


class LiveResponse(BaseModel):
    status: str
    app: str
    environment: str


class ReadyResponse(BaseModel):
    status: str
    checks: dict[str, HealthCheckDetail]


# ---------------------------------------------------------------------------
# Location
# ---------------------------------------------------------------------------


class LocationResponse(BaseModel):
    model_config = ConfigDict(extra="allow")
    location_name: str
    resolved_name: str
    latitude: float
    longitude: float
    timezone: str
    source: str | None = None


# ---------------------------------------------------------------------------
# Profile
# ---------------------------------------------------------------------------


class ProfileSummary(BaseModel):
    model_config = ConfigDict(extra="allow")
    profile_id: str
    profile_name: str
    username: str
    location_name: str | None = None
    local_birth_datetime: str | None = None
    is_own: bool | None = None
    is_following: bool | None = None


class PublicProfileSearchResult(BaseModel):
    model_config = ConfigDict(extra="allow")
    profile_id: str
    profile_name: str
    username: str
    birth_date: str | None = None
    birth_time: str | None = None
    timezone: str | None = None
    location_name: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    natal_summary: Any = None


class PublicProfileSearchResponse(BaseModel):
    results: list[PublicProfileSearchResult]


class ProfileListResponse(BaseModel):
    profiles: list[ProfileSummary]


class SavedChartResponse(BaseModel):
    """Chart payload returned alongside a profile."""

    model_config = ConfigDict(extra="allow")
    chart_id: str
    chart_path: str | None = None
    name: str | None = None
    location_name: str | None = None
    local_birth_datetime: str | None = None
    utc_birth_datetime: str | None = None
    julian_day: float | None = None
    house_system: str | None = None
    natal_aspect_count: int | None = None


class ProfileDetailResponse(BaseModel):
    model_config = ConfigDict(extra="allow")
    profile: ProfileSummary
    chart: SavedChartResponse


# ---------------------------------------------------------------------------
# Charts (debug)
# ---------------------------------------------------------------------------


class NatalChartDebugResponse(BaseModel):
    model_config = ConfigDict(extra="allow")
    julian_day: float
    swiss_ephemeris_version: str | None = None
    planets: dict[str, Any] | None = None
    natal_positions: list[Any] | None = None
    asc: Any = None
    mc: Any = None
    houses: list[Any] | None = None
    natal_aspects: list[Any] | None = None


# ---------------------------------------------------------------------------
# Transits
# ---------------------------------------------------------------------------


class TransitReportResponse(BaseModel):
    model_config = ConfigDict(extra="allow")
    snapshot: dict[str, Any] | None = None
    transits: list[Any] | None = None
    aspects: list[Any] | None = None
    tii: float | None = None
    tension_ratio: float | None = None
    feels_like: str | None = None
    top_transits: list[Any] | None = None


class TransitTimelineResponse(BaseModel):
    model_config = ConfigDict(extra="allow")
    timeline: list[Any]
