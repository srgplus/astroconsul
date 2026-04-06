from __future__ import annotations

from datetime import date, datetime, time
from typing import Any

from sqlalchemy import Boolean, Date, DateTime, Float, ForeignKey, Integer, String, Text, Time, UniqueConstraint
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
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
    primary_profile_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
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
    is_featured: Mapped[bool] = mapped_column(Boolean, default=False)
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
    tii: Mapped[float | None] = mapped_column(Float, nullable=True)
    tension_ratio: Mapped[float | None] = mapped_column(Float, nullable=True)
    feels_like: Mapped[str | None] = mapped_column(String(64), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    profile: Mapped[ProfileModel] = relationship(back_populates="latest_transit")


class ProfileFollowModel(Base):
    __tablename__ = "profile_follows"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    profile_id: Mapped[str] = mapped_column(ForeignKey("profiles.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    __table_args__ = (UniqueConstraint("user_id", "profile_id", name="uq_user_profile_follow"),)


class ProfileInviteModel(Base):
    __tablename__ = "profile_invites"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    profile_id: Mapped[str] = mapped_column(ForeignKey("profiles.id"), nullable=False)
    invited_email: Mapped[str] = mapped_column(String(255), nullable=False)
    token: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    invited_by: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class LocationCacheModel(Base):
    __tablename__ = "location_cache"

    query: Mapped[str] = mapped_column(String(255), primary_key=True)
    resolved_name: Mapped[str] = mapped_column(String(255), nullable=False)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    timezone: Mapped[str] = mapped_column(String(255), nullable=False)
    provider: Mapped[str] = mapped_column(String(255), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class NewsPostModel(Base):
    __tablename__ = "news_posts"

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    slug: Mapped[str] = mapped_column(String(512), unique=True, nullable=False)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    subtitle: Mapped[str | None] = mapped_column(Text, nullable=True)
    date: Mapped[date] = mapped_column(Date, nullable=False)
    author: Mapped[str] = mapped_column(String(255), nullable=False, default="Victoria")
    status: Mapped[str] = mapped_column(String(64), nullable=False, default="draft")

    # Content
    intro: Mapped[str] = mapped_column(Text, nullable=False)
    sections: Mapped[dict[str, Any] | None] = mapped_column(JSONType, nullable=True)
    conclusion: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Celebrity (nullable for non-celebrity posts)
    celebrity_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    celebrity_profile_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    celebrity_event: Mapped[str | None] = mapped_column(Text, nullable=True)

    # SEO
    meta_title: Mapped[str | None] = mapped_column(Text, nullable=True)
    meta_description: Mapped[str | None] = mapped_column(Text, nullable=True)
    keywords: Mapped[str | None] = mapped_column(Text, nullable=True)  # comma-separated
    og_image_url: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Tags (comma-separated for SQLite compat, ARRAY on PostgreSQL)
    tags: Mapped[str | None] = mapped_column(Text, nullable=True)  # comma-separated

    # Images
    hero_image_url: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Reddit cross-post tracking
    reddit_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    reddit_subreddit: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # Timestamps
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class SubscriptionModel(Base):
    __tablename__ = "subscriptions"

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(128), ForeignKey("users.id"), nullable=False)
    plan: Mapped[str] = mapped_column(String(20), nullable=False, default="free")
    payment_provider: Mapped[str | None] = mapped_column(String(20), nullable=True)
    transaction_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    amount: Mapped[int | None] = mapped_column(Integer, nullable=True)
    currency: Mapped[str] = mapped_column(String(3), default="USD")
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
