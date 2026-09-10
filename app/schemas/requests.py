from __future__ import annotations

from datetime import date

from pydantic import BaseModel, Field


class NatalChartCreateRequest(BaseModel):
    birth_date: date
    birth_time: str | float
    timezone: str | None = None
    name: str | None = None
    location_name: str | None = None
    latitude: float
    longitude: float
    time_basis: str | None = None


class TransitReportRequest(BaseModel):
    chart_id: str | None = None
    profile_id: str | None = None
    transit_date: str
    transit_time: str
    timezone: str | None = None
    location_name: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    include_timing: bool = False
    lang: str = "ru"


class TransitTimelineRequest(BaseModel):
    chart_id: str | None = None
    profile_id: str | None = None
    start_date: date
    end_date: date
    timezone: str


class NatalProfileUpsertRequest(NatalChartCreateRequest):
    profile_name: str
    username: str


class LocationResolveRequest(BaseModel):
    location_name: str


class NatalDebugRequest(BaseModel):
    year: int
    month: int
    day: int
    hour: float
    lat: float
    lon: float


class ProfileTransitReportRequest(BaseModel):
    transit_date: str
    transit_time: str
    timezone: str | None = None
    location_name: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    include_timing: bool = False
    lang: str = "ru"


class ProfileTransitTimelineRequest(BaseModel):
    start_date: date
    end_date: date
    timezone: str


class ForecastRequest(BaseModel):
    profile_id: str | None = None
    chart_id: str | None = None
    start_date: date | None = None
    days: int = 10
    timezone: str
    lang: str = "ru"


class SynastryReportRequest(BaseModel):
    partner_profile_id: str
    lang: str = "ru"


class ProfileArrangementRequest(BaseModel):
    """How the reader arranged their saved list: the ids in the Favourites
    group, and the order every card was dragged into.

    Whole lists rather than a delta, because the client already holds the only
    complete picture of the order and a delta would need the two to agree about
    a list that changes under them both."""

    favorite_profile_ids: list[str] = Field(default_factory=list, max_length=1000)
    profile_order: list[str] = Field(default_factory=list, max_length=1000)
