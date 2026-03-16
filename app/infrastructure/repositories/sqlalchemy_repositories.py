from __future__ import annotations

import hashlib
import json
from datetime import UTC, date, datetime, time
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings
from app.domain.astrology.charts import build_chart, chart_needs_upgrade, make_chart_id
from app.domain.astrology.utils import parse_time_string
from app.infrastructure.persistence.models import (
    LatestTransitModel,
    LocationCacheModel,
    NatalChartModel,
    ProfileModel,
    UserModel,
)
from natal_profiles import (
    UsernameConflictError,
    normalize_latest_transit,
    normalize_time_string,
    profile_summary,
    resolve_transit_timezone,
    validate_username,
)


def _now_utc() -> datetime:
    return datetime.now(UTC).replace(microsecond=0)


def _isoformat_z(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _chart_hash(chart: dict[str, object]) -> str:
    payload = json.dumps(chart, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _normalize_chart_id(chart_id: str) -> str:
    return chart_id[:-5] if chart_id.endswith(".json") else chart_id


def _coerce_date(value: object, fallback: date | None = None) -> date:
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        return date.fromisoformat(value)
    if fallback is not None:
        return fallback
    raise ValueError("birth_date is required for database persistence.")


def _coerce_time(value: object, fallback: time | None = None) -> time:
    if isinstance(value, time):
        return value.replace(microsecond=0)
    if isinstance(value, (int, float)):
        total_seconds = int(round(float(value) * 3600))
        hours, remainder = divmod(total_seconds, 3600)
        minutes, seconds = divmod(remainder, 60)
        return time(hour=hours, minute=minutes, second=seconds)
    if isinstance(value, str):
        normalized = normalize_time_string(value)
        if normalized is None:
            return parse_time_string(value)
        return time.fromisoformat(normalized)
    if fallback is not None:
        return fallback
    raise ValueError("birth_time is required for database persistence.")


def _profile_payload(model: ProfileModel) -> dict[str, Any]:
    latest_transit = None
    if model.latest_transit is not None:
        latest_transit = normalize_latest_transit(
            {
                "transit_date": model.latest_transit.transit_date.isoformat(),
                "transit_time": model.latest_transit.transit_time.replace(microsecond=0).isoformat(),
                "timezone": model.latest_transit.timezone,
                "location_name": model.latest_transit.location_name,
                "latitude": model.latest_transit.latitude,
                "longitude": model.latest_transit.longitude,
                "updated_at": _isoformat_z(model.latest_transit.updated_at),
            }
        )

    return {
        "profile_id": model.id,
        "profile_name": model.display_name,
        "username": model.handle,
        "chart_id": model.chart_id,
        "created_at": _isoformat_z(model.created_at),
        "updated_at": _isoformat_z(model.updated_at),
        "latest_transit": latest_transit,
    }


def ensure_default_user(session: Session, settings: Settings) -> UserModel:
    existing = session.get(UserModel, settings.default_user_id)
    if existing is not None:
        return existing

    user = UserModel(
        id=settings.default_user_id,
        auth_subject=settings.default_auth_subject,
        email=settings.default_user_email,
        status="active",
        created_at=_now_utc(),
    )
    session.add(user)
    session.flush()
    return user


class SqlAlchemyChartRepository:
    def __init__(self, session_factory: sessionmaker[Session]):
        self.session_factory = session_factory

    def save_chart(self, chart: dict[str, object], chart_id: str | None = None) -> tuple[str, str]:
        birth_data = chart.get("birth_data") or {}
        resolved_chart_id = chart_id or make_chart_id(
            int(birth_data["year"]),
            int(birth_data["month"]),
            int(birth_data["day"]),
            float(birth_data["hour"]),
        )

        with self.session_factory() as session:
            model = session.get(NatalChartModel, resolved_chart_id)
            created_at = model.created_at if model is not None else _now_utc()
            payload = dict(chart)
            if model is None:
                model = NatalChartModel(
                    id=resolved_chart_id,
                    chart_hash=_chart_hash(payload),
                    house_system=str(payload.get("house_system") or ""),
                    julian_day=float(payload.get("julian_day") or 0.0),
                    birth_input_json=payload.get("birth_input"),
                    chart_payload_json=payload,
                    created_at=created_at,
                )
                session.add(model)
            else:
                model.chart_hash = _chart_hash(payload)
                model.house_system = str(payload.get("house_system") or "")
                model.julian_day = float(payload.get("julian_day") or 0.0)
                model.birth_input_json = payload.get("birth_input")
                model.chart_payload_json = payload

            session.commit()

        return resolved_chart_id, f"db://natal_charts/{resolved_chart_id}"

    def load_chart(self, chart_id: str) -> tuple[str, dict[str, object]]:
        resolved_chart_id = _normalize_chart_id(chart_id)

        with self.session_factory() as session:
            model = session.get(NatalChartModel, resolved_chart_id)
            if model is None:
                raise FileNotFoundError(f"Natal chart not found: {chart_id}")

            chart = dict(model.chart_payload_json)
            if chart_needs_upgrade(chart):
                birth_data = chart.get("birth_data") or {}
                required_fields = {"year", "month", "day", "hour", "latitude", "longitude"}
                if required_fields.issubset(birth_data):
                    chart = build_chart(
                        int(birth_data["year"]),
                        int(birth_data["month"]),
                        int(birth_data["day"]),
                        float(birth_data["hour"]),
                        float(birth_data["latitude"]),
                        float(birth_data["longitude"]),
                        birth_input=chart.get("birth_input"),
                    )
                    model.chart_hash = _chart_hash(chart)
                    model.house_system = str(chart.get("house_system") or "")
                    model.julian_day = float(chart.get("julian_day") or 0.0)
                    model.birth_input_json = chart.get("birth_input")
                    model.chart_payload_json = chart
                    session.commit()

            return f"db://natal_charts/{resolved_chart_id}", chart

    def delete_chart(self, chart_id: str) -> None:
        resolved_chart_id = _normalize_chart_id(chart_id)
        with self.session_factory() as session:
            model = session.get(NatalChartModel, resolved_chart_id)
            if model is not None:
                session.delete(model)
                session.commit()


class SqlAlchemyProfileRepository:
    def __init__(
        self,
        session_factory: sessionmaker[Session],
        settings: Settings,
        chart_repository: SqlAlchemyChartRepository,
    ):
        self.session_factory = session_factory
        self.settings = settings
        self.chart_repository = chart_repository

    def _profile_input_defaults(
        self,
        profile_input: dict[str, object] | None,
        chart_payload: dict[str, object] | None,
    ) -> dict[str, object]:
        payload = dict(profile_input or {})
        birth_input = (chart_payload or {}).get("birth_input") if chart_payload else None
        birth_input_dict = birth_input if isinstance(birth_input, dict) else {}
        birth_data = (chart_payload or {}).get("birth_data") if chart_payload else None
        birth_data_dict = birth_data if isinstance(birth_data, dict) else {}

        if "birth_date" not in payload and "birth_date" in birth_input_dict:
            payload["birth_date"] = birth_input_dict["birth_date"]
        if "birth_date" not in payload and {"year", "month", "day"}.issubset(birth_data_dict):
            payload["birth_date"] = (
                f"{int(birth_data_dict['year']):04d}-{int(birth_data_dict['month']):02d}-{int(birth_data_dict['day']):02d}"
            )
        if "birth_time" not in payload and "birth_time" in birth_input_dict:
            payload["birth_time"] = birth_input_dict["birth_time"]
        if "birth_time" not in payload and "hour" in birth_data_dict:
            payload["birth_time"] = float(birth_data_dict["hour"])
        if "timezone" not in payload and "timezone" in birth_input_dict:
            payload["timezone"] = birth_input_dict["timezone"]
        if "timezone" not in payload:
            payload["timezone"] = "UTC"
        if "location_name" not in payload and "location_name" in birth_input_dict:
            payload["location_name"] = birth_input_dict["location_name"]
        if "latitude" not in payload and "latitude" in birth_input_dict:
            payload["latitude"] = birth_input_dict["latitude"]
        if "latitude" not in payload and "latitude" in birth_data_dict:
            payload["latitude"] = birth_data_dict["latitude"]
        if "longitude" not in payload and "longitude" in birth_input_dict:
            payload["longitude"] = birth_input_dict["longitude"]
        if "longitude" not in payload and "longitude" in birth_data_dict:
            payload["longitude"] = birth_data_dict["longitude"]
        return payload

    def _load_chart_payload(self, chart_id: str) -> dict[str, object]:
        _, chart = self.chart_repository.load_chart(chart_id)
        return chart

    def _ensure_username_available(
        self,
        session: Session,
        username: str,
        *,
        exclude_profile_id: str | None = None,
    ) -> str:
        normalized = validate_username(username)
        statement = select(ProfileModel).where(ProfileModel.handle == normalized)
        existing = session.execute(statement).scalar_one_or_none()
        if existing is not None and existing.id != exclude_profile_id:
            raise UsernameConflictError("username is already taken.")
        return normalized

    def list_summaries(self) -> list[dict[str, Any]]:
        with self.session_factory() as session:
            rows = session.execute(select(ProfileModel).order_by(ProfileModel.updated_at.desc())).scalars()

            summaries: list[dict[str, Any]] = []
            for profile_model in rows:
                chart_payload = dict(profile_model.chart.chart_payload_json)
                summaries.append(profile_summary(_profile_payload(profile_model), chart_payload))
            return summaries

    def load_profile(self, profile_id: str) -> dict[str, Any]:
        with self.session_factory() as session:
            model = session.get(ProfileModel, profile_id)
            if model is None:
                raise FileNotFoundError(f"Natal profile not found: {profile_id}")
            return _profile_payload(model)

    def create_profile(
        self,
        profile_name: str,
        username: str,
        chart_id: str,
        *,
        profile_input: dict[str, object] | None = None,
        profile_id: str | None = None,
        created_at: str | None = None,
        updated_at: str | None = None,
    ) -> dict[str, Any]:
        with self.session_factory() as session:
            ensure_default_user(session, self.settings)
            normalized_username = self._ensure_username_available(session, username)
            chart_payload = self._load_chart_payload(chart_id)
            payload = self._profile_input_defaults(profile_input, chart_payload)
            timestamp = (
                datetime.fromisoformat(created_at.replace("Z", "+00:00")) if created_at is not None else _now_utc()
            )
            updated_timestamp = (
                datetime.fromisoformat(updated_at.replace("Z", "+00:00")) if updated_at is not None else timestamp
            )
            profile = ProfileModel(
                id=profile_id
                or f"profile_{hashlib.sha256(f'{normalized_username}:{timestamp}'.encode()).hexdigest()[:32]}",
                user_id=self.settings.default_user_id,
                handle=normalized_username,
                display_name=profile_name.strip(),
                birth_date=_coerce_date(payload.get("birth_date")),
                birth_time=_coerce_time(payload.get("birth_time")),
                timezone=str(payload.get("timezone") or "UTC"),
                location_name=str(payload.get("location_name") or "") or None,
                latitude=float(payload.get("latitude")),
                longitude=float(payload.get("longitude")),
                chart_id=_normalize_chart_id(chart_id),
                created_at=timestamp,
                updated_at=updated_timestamp,
            )
            session.add(profile)
            session.commit()
            session.refresh(profile)
            return _profile_payload(profile)

    def update_profile(
        self,
        profile_id: str,
        profile_name: str,
        username: str,
        chart_id: str,
        *,
        profile_input: dict[str, object] | None = None,
    ) -> dict[str, Any]:
        with self.session_factory() as session:
            model = session.get(ProfileModel, profile_id)
            if model is None:
                raise FileNotFoundError(f"Natal profile not found: {profile_id}")

            normalized_username = self._ensure_username_available(
                session,
                username,
                exclude_profile_id=profile_id,
            )
            chart_payload = self._load_chart_payload(chart_id)
            payload = self._profile_input_defaults(profile_input, chart_payload)

            model.handle = normalized_username
            model.display_name = profile_name.strip()
            model.birth_date = _coerce_date(payload.get("birth_date"), fallback=model.birth_date)
            model.birth_time = _coerce_time(payload.get("birth_time"), fallback=model.birth_time)
            model.timezone = str(payload.get("timezone") or model.timezone)
            model.location_name = str(payload.get("location_name") or "") or None
            model.latitude = float(payload.get("latitude", model.latitude))
            model.longitude = float(payload.get("longitude", model.longitude))
            model.chart_id = _normalize_chart_id(chart_id)
            model.updated_at = _now_utc()
            session.commit()
            session.refresh(model)
            return _profile_payload(model)

    def resolve_profile_chart_id(self, profile_id: str) -> str:
        with self.session_factory() as session:
            model = session.get(ProfileModel, profile_id)
            if model is None:
                raise FileNotFoundError(f"Natal profile not found: {profile_id}")
            return model.chart_id

    def delete_chart_if_unreferenced(
        self,
        chart_id: str,
        *,
        exclude_profile_id: str | None = None,
    ) -> None:
        resolved_chart_id = _normalize_chart_id(chart_id)
        with self.session_factory() as session:
            statement = select(ProfileModel).where(ProfileModel.chart_id == resolved_chart_id)
            profiles = session.execute(statement).scalars().all()
            if any(profile.id != exclude_profile_id for profile in profiles):
                return

        self.chart_repository.delete_chart(resolved_chart_id)

    def search_public(self, query: str, *, limit: int = 20) -> list[dict[str, Any]]:
        with self.session_factory() as session:
            statement = (
                select(ProfileModel)
                .where(ProfileModel.handle.ilike(f"%{query}%"))
                .order_by(ProfileModel.updated_at.desc())
                .limit(limit)
            )
            rows = session.execute(statement).scalars()

            results: list[dict[str, Any]] = []
            for model in rows:
                chart_payload = dict(model.chart.chart_payload_json)
                summary = profile_summary(_profile_payload(model), chart_payload)
                summary["user_id"] = model.user_id
                summary["birth_date"] = model.birth_date.isoformat()
                summary["birth_time"] = model.birth_time.replace(microsecond=0).isoformat()
                summary["timezone"] = model.timezone
                summary["location_name"] = model.location_name
                summary["latitude"] = model.latitude
                summary["longitude"] = model.longitude
                results.append(summary)
            return results

    def save_latest_transit(self, profile_id: str, latest_transit: dict[str, Any]) -> dict[str, Any]:
        normalized = normalize_latest_transit(latest_transit)
        if normalized is None:
            raise ValueError("latest_transit payload is invalid.")

        with self.session_factory() as session:
            profile = session.get(ProfileModel, profile_id)
            if profile is None:
                raise FileNotFoundError(f"Natal profile not found: {profile_id}")

            model = session.get(LatestTransitModel, profile_id)
            transit_time = normalize_time_string(normalized["transit_time"])
            assert transit_time is not None
            if model is None:
                model = LatestTransitModel(
                    profile_id=profile_id,
                    transit_date=date.fromisoformat(str(normalized["transit_date"])),
                    transit_time=time.fromisoformat(transit_time),
                    timezone=resolve_transit_timezone(normalized["timezone"]),
                    location_name=normalized.get("location_name"),
                    latitude=normalized.get("latitude"),
                    longitude=normalized.get("longitude"),
                    updated_at=datetime.fromisoformat(str(normalized["updated_at"]).replace("Z", "+00:00")),
                )
                session.add(model)
            else:
                model.transit_date = date.fromisoformat(str(normalized["transit_date"]))
                model.transit_time = time.fromisoformat(transit_time)
                model.timezone = resolve_transit_timezone(normalized["timezone"])
                model.location_name = normalized.get("location_name")
                model.latitude = normalized.get("latitude")
                model.longitude = normalized.get("longitude")
                model.updated_at = datetime.fromisoformat(str(normalized["updated_at"]).replace("Z", "+00:00"))

            session.commit()
            session.refresh(profile)
            return _profile_payload(profile)


class SqlAlchemyLocationCacheRepository:
    def __init__(self, session_factory: sessionmaker[Session]):
        self.session_factory = session_factory

    def get(self, query: str) -> dict[str, Any] | None:
        with self.session_factory() as session:
            model = session.get(LocationCacheModel, query)
            if model is None:
                return None
            return {
                "location_name": query,
                "resolved_name": model.resolved_name,
                "latitude": model.latitude,
                "longitude": model.longitude,
                "timezone": model.timezone,
                "source": model.provider,
            }

    def put(self, query: str, payload: dict[str, Any]) -> dict[str, Any]:
        with self.session_factory() as session:
            model = session.get(LocationCacheModel, query)
            timestamp = _now_utc()
            if model is None:
                model = LocationCacheModel(
                    query=query,
                    resolved_name=str(payload["resolved_name"]),
                    latitude=float(payload["latitude"]),
                    longitude=float(payload["longitude"]),
                    timezone=str(payload["timezone"]),
                    provider=str(payload.get("source") or "unknown"),
                    updated_at=timestamp,
                )
                session.add(model)
            else:
                model.resolved_name = str(payload["resolved_name"])
                model.latitude = float(payload["latitude"])
                model.longitude = float(payload["longitude"])
                model.timezone = str(payload["timezone"])
                model.provider = str(payload.get("source") or model.provider)
                model.updated_at = timestamp

            session.commit()
            return {
                "location_name": query,
                "resolved_name": str(payload["resolved_name"]),
                "latitude": float(payload["latitude"]),
                "longitude": float(payload["longitude"]),
                "timezone": str(payload["timezone"]),
                "source": str(payload.get("source") or "unknown"),
            }
