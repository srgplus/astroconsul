from __future__ import annotations

from datetime import UTC, date, datetime
from pathlib import Path

from app.application.services.input_resolution import (
    convert_local_datetime,
    ensure_chart_reference,
    format_datetime,
)
from app.domain.astrology.charts import swiss_ephemeris_version
from app.domain.astrology.tii import (
    compute_tension_ratio,
    compute_tii,
    feels_like,
    top_active_transits,
)
from app.domain.astrology.transits import build_transit_report, build_transit_timeline
from app.domain.astrology.utils import parse_time_string


class TransitService:
    def build_report(
        self,
        payload,
        *,
        profile_repository,
        location_resolver,
    ) -> dict[str, object]:
        try:
            transit_date = date.fromisoformat(payload.transit_date)
        except ValueError as exc:
            raise ValueError("transit_date must be in YYYY-MM-DD format.") from exc

        transit_location_name = payload.location_name.strip() if payload.location_name else None
        transit_latitude = payload.latitude
        transit_longitude = payload.longitude
        resolved_transit_location = None

        if not transit_location_name:
            transit_latitude = None
            transit_longitude = None

        if (transit_latitude is None) != (transit_longitude is None):
            raise ValueError("latitude and longitude must be provided together.")

        if transit_location_name and transit_latitude is None and transit_longitude is None:
            resolved_transit_location = location_resolver(transit_location_name)
            transit_location_name = str(resolved_transit_location["resolved_name"])
            transit_latitude = float(resolved_transit_location["latitude"])
            transit_longitude = float(resolved_transit_location["longitude"])

        chart_id = ensure_chart_reference(
            payload.chart_id,
            payload.profile_id,
            resolver=profile_repository.resolve_profile_chart_id,
        )
        effective_timezone = payload.timezone
        if (effective_timezone is None or not effective_timezone.strip()) and resolved_transit_location is not None:
            effective_timezone = str(resolved_transit_location["timezone"])

        if effective_timezone and effective_timezone.strip():
            local_dt, utc_dt = convert_local_datetime(
                transit_date,
                payload.transit_time,
                effective_timezone,
                field_name="transit_time",
            )
            transit_timezone = effective_timezone
        else:
            utc_time = parse_time_string(payload.transit_time)
            utc_dt = datetime.combine(transit_date, utc_time, tzinfo=UTC)
            local_dt = utc_dt
            transit_timezone = "UTC"

        report = build_transit_report(
            chart_id,
            utc_dt.date().isoformat(),
            utc_dt.strftime("%H:%M:%S"),
            include_timing=payload.include_timing,
            transit_latitude=transit_latitude,
            transit_longitude=transit_longitude,
        )

        snapshot = dict(report.get("snapshot", {}))
        chart_filename = str(snapshot.get("chart_id", chart_id))
        chart_path = Path(chart_filename)
        ephemeris_version = swiss_ephemeris_version()

        snapshot.update(
            {
                "chart_id": chart_path.stem,
                "profile_id": payload.profile_id,
                "chart_filename": chart_path.name,
                "transit_local_datetime": format_datetime(local_dt),
                "transit_timezone": transit_timezone,
                "transit_utc_datetime": format_datetime(utc_dt),
                "transit_date": utc_dt.date().isoformat(),
                "transit_time_ut": utc_dt.strftime("%H:%M:%S"),
                "house_system": snapshot.get("house_system"),
                "ephemeris_version": ephemeris_version,
                "ephemeris": f"Swiss Ephemeris {ephemeris_version}",
                "transit_location_name": transit_location_name,
                "transit_latitude": transit_latitude,
                "transit_longitude": transit_longitude,
            }
        )

        if payload.profile_id:
            profile_repository.save_latest_transit(
                payload.profile_id,
                {
                    "transit_date": local_dt.date().isoformat(),
                    "transit_time": local_dt.time().replace(microsecond=0).isoformat(),
                    "timezone": transit_timezone,
                    "location_name": transit_location_name,
                    "latitude": transit_latitude,
                    "longitude": transit_longitude,
                },
            )

        # --- TII scoring ---
        active_aspects = report.get("active_aspects", [])
        tii = compute_tii(active_aspects)
        tension_ratio = compute_tension_ratio(active_aspects)
        report["tii"] = tii
        report["tension_ratio"] = tension_ratio
        report["feels_like"] = feels_like(tii, tension_ratio)
        report["top_transits"] = top_active_transits(active_aspects)

        report["snapshot"] = snapshot
        return report

    def build_timeline(self, payload, *, profile_repository) -> dict[str, object]:
        chart_id = ensure_chart_reference(
            payload.chart_id,
            payload.profile_id,
            resolver=profile_repository.resolve_profile_chart_id,
        )
        timeline = build_transit_timeline(
            chart_id,
            payload.start_date,
            payload.end_date,
            payload.timezone,
        )
        return {"timeline": timeline}
