from __future__ import annotations

from datetime import date
from typing import Optional, Union

from pydantic import BaseModel


class NatalChartCreateRequest(BaseModel):
    birth_date: date
    birth_time: Union[str, float]
    timezone: Optional[str] = None
    name: Optional[str] = None
    location_name: Optional[str] = None
    latitude: float
    longitude: float
    time_basis: Optional[str] = None


class TransitReportRequest(BaseModel):
    chart_id: Optional[str] = None
    profile_id: Optional[str] = None
    transit_date: str
    transit_time: str
    timezone: Optional[str] = None
    location_name: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    include_timing: bool = False


class TransitTimelineRequest(BaseModel):
    chart_id: Optional[str] = None
    profile_id: Optional[str] = None
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
    timezone: Optional[str] = None
    location_name: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    include_timing: bool = False


class ProfileTransitTimelineRequest(BaseModel):
    start_date: date
    end_date: date
    timezone: str

