from __future__ import annotations

from datetime import date

from pydantic import BaseModel


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
