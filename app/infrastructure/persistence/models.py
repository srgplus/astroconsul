from __future__ import annotations

from datetime import date, datetime, time
from typing import Any

from sqlalchemy import Date, DateTime, Float, ForeignKey, String, Time
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.types import JSON

from app.infrastructure.persistence.base import Base

JSONType = JSON().with_variant(JSONB, "postgresql")


class UserModel(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    auth_subject: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    email: Mapped[str] = mapped_column(String(255), nullable=False)
    status: Mapped[str] = mapped_column(String(64), nullable=False, default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    profiles: Mapped[list[ProfileModel]] = relationship(back_populates="user")


class NatalChartModel(Base):
    __tablename__ = "natal_charts"

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    chart_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    house_system: Mapped[str] = mapped_column(String(64), nullable=False)
    julian_day: Mapped[float] = mapped_column(Float, nullable=False)
    birth_input_json: Mapped[dict[str, Any] | None] = mapped_column(JSONType, nullable=True)
    chart_payload_json: Mapped[dict[str, Any]] = mapped_column(JSONType, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    profiles: Mapped[list[ProfileModel]] = relationship(back_populates="chart")


class ProfileModel(Base):
    __tablename__ = "profiles"

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    handle: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    display_name: Mapped[str] = mapped_column(String(255), nullable=False)
    birth_date: Mapped[date] = mapped_column(Date, nullable=False)
    birth_time: Mapped[time] = mapped_column(Time, nullable=False)
    timezone: Mapped[str] = mapped_column(String(255), nullable=False)
    location_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    chart_id: Mapped[str] = mapped_column(ForeignKey("natal_charts.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    user: Mapped[UserModel] = relationship(back_populates="profiles")
    chart: Mapped[NatalChartModel] = relationship(back_populates="profiles")
    latest_transit: Mapped[LatestTransitModel | None] = relationship(
        back_populates="profile",
        uselist=False,
        cascade="all, delete-orphan",
    )


class LatestTransitModel(Base):
    __tablename__ = "latest_transits"

    profile_id: Mapped[str] = mapped_column(
        ForeignKey("profiles.id"),
        primary_key=True,
    )
    transit_date: Mapped[date] = mapped_column(Date, nullable=False)
    transit_time: Mapped[time] = mapped_column(Time, nullable=False)
    timezone: Mapped[str] = mapped_column(String(255), nullable=False)
    location_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    profile: Mapped[ProfileModel] = relationship(back_populates="latest_transit")


class LocationCacheModel(Base):
    __tablename__ = "location_cache"

    query: Mapped[str] = mapped_column(String(255), primary_key=True)
    resolved_name: Mapped[str] = mapped_column(String(255), nullable=False)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    timezone: Mapped[str] = mapped_column(String(255), nullable=False)
    provider: Mapped[str] = mapped_column(String(255), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
