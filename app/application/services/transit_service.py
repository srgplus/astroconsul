from __future__ import annotations

from datetime import UTC, date, datetime
from pathlib import Path

from app.application.services.input_resolution import (
    convert_local_datetime,
    ensure_chart_reference,
    format_datetime,
)
from app.domain.astrology.charts import swiss_ephemeris_version
from app.domain.astrology.cosmic_climate import get_cosmic_climate
from app.domain.astrology.moon import compute_moon_phase
from app.domain.astrology.tii import (
    compute_ope,
    compute_retrograde_index,
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

        lang = getattr(payload, "lang", "ru")
        report = build_transit_report(
            chart_id,
            utc_dt.date().isoformat(),
            utc_dt.strftime("%H:%M:%S"),
            include_timing=payload.include_timing,
            transit_latitude=transit_latitude,
            transit_longitude=transit_longitude,
            lang=lang,
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

        # --- TII scoring ---
        active_aspects = report.get("active_aspects", [])
        tii = compute_tii(active_aspects)
        tension_ratio = compute_tension_ratio(active_aspects)
        report["tii"] = tii
        report["tension_ratio"] = tension_ratio
        report["feels_like"] = feels_like(tii, tension_ratio)

        # --- OPE & Retrograde ---
        ope = compute_ope(active_aspects)
        rx = compute_retrograde_index(report.get("transit_positions", []))
        report["ope"] = ope
        report["retrograde_index"] = rx

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
                    "tii": tii,
                    "tension_ratio": tension_ratio,
                    "feels_like": report["feels_like"],
                    "ope": ope,
                    "retrograde_count": rx["count"],
                },
            )
        report["top_transits"] = top_active_transits(active_aspects)
        report["cosmic_climate"] = get_cosmic_climate(active_aspects, lang=lang)
        report["moon_phase"] = compute_moon_phase(report.get("transit_positions", []))

        report["snapshot"] = snapshot
        return report

    def build_forecast(
        self,
        payload,
        *,
        profile_repository,
    ) -> dict[str, object]:
        """Build a multi-day TII forecast (no timing engine — fast)."""
        from datetime import timedelta
        from zoneinfo import ZoneInfo

        chart_id = ensure_chart_reference(
            getattr(payload, "chart_id", None),
            payload.profile_id,
            resolver=profile_repository.resolve_profile_chart_id,
        )

        tz = ZoneInfo(payload.timezone)
        start = date.fromisoformat(str(payload.start_date))
        num_days = payload.days
        lang = getattr(payload, "lang", "ru")

        prev_tii: float | None = None
        days: list[dict] = []

        for offset in range(num_days):
            current_date = start + timedelta(days=offset)
            # Noon local → UTC
            local_noon = datetime.combine(current_date, datetime.min.time().replace(hour=12), tzinfo=tz)
            utc_noon = local_noon.astimezone(UTC)

            report = build_transit_report(
                chart_id,
                utc_noon.date().isoformat(),
                utc_noon.strftime("%H:%M:%S"),
                include_timing=False,
                lang=lang,
            )

            active_aspects = report.get("active_aspects", [])
            tii_val = compute_tii(active_aspects)
            tr = compute_tension_ratio(active_aspects)
            fl = feels_like(tii_val, tr)
            ope_val = compute_ope(active_aspects)
            rx = compute_retrograde_index(report.get("transit_positions", []))
            top = top_active_transits(active_aspects, n=3)

            # Velocity (delta vs previous day)
            velocity_delta: float | None = None
            velocity_direction: str | None = None
            if prev_tii is not None:
                velocity_delta = round(tii_val - prev_tii, 1)
                if velocity_delta > 2:
                    velocity_direction = "rising"
                elif velocity_delta < -2:
                    velocity_direction = "falling"
                else:
                    velocity_direction = "stable"

            moon_phase = compute_moon_phase(report.get("transit_positions", []))

            days.append({
                "date": current_date.isoformat(),
                "tii": tii_val,
                "tension_ratio": tr,
                "feels_like": fl,
                "ope": ope_val,
                "retrograde_count": rx["count"],
                "retrograde_planets": rx["planets"],
                "velocity_delta": velocity_delta,
                "velocity_direction": velocity_direction,
                "top_transits": top,
                "moon_phase": moon_phase,
            })
            prev_tii = tii_val

        return {"days": days}

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
