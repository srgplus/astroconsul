from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from app.application.services.input_resolution import (
    convert_local_datetime,
    decimal_hour_to_time,
    format_datetime,
    parse_ut_birth_time,
    resolve_time_basis,
)
from app.domain.astrology.charts import (
    build_chart,
    chart_needs_upgrade,
    load_saved_chart,
    make_chart_id,
    save_chart,
)
from app.domain.astrology.utils import time_to_decimal_hours
from app.schemas.requests import NatalChartCreateRequest


class ChartService:
    def build_saved_chart_response(
        self,
        chart_id: str,
        chart_path: str | Path,
        chart: dict[str, Any],
    ) -> dict[str, Any]:
        path_value = Path(chart_path) if not str(chart_path).startswith("db://") else str(chart_path)
        if isinstance(path_value, Path) and chart_needs_upgrade(chart) and path_value.exists():
            path_value, chart = load_saved_chart(str(path_value))

        birth_input = chart.get("birth_input") or {}
        angles = chart.get("angles") or {}
        return {
            "chart_id": chart_id,
            "chart_path": str(path_value),
            "name": birth_input.get("name"),
            "location_name": birth_input.get("location_name"),
            "local_birth_datetime": birth_input.get("local_birth_datetime"),
            "utc_birth_datetime": birth_input.get("utc_birth_datetime"),
            "julian_day": chart.get("julian_day"),
            "asc": angles.get("asc"),
            "mc": angles.get("mc"),
            "house_system": chart.get("house_system"),
            "natal_aspect_count": len(chart.get("natal_aspects", [])),
            "birth_input": birth_input,
            "planets": chart.get("planets"),
            "natal_positions": chart.get("natal_positions"),
            "houses": chart.get("houses"),
            "angles": angles,
            "angle_positions": chart.get("angle_positions"),
            "natal_aspects": chart.get("natal_aspects"),
            "natal_summary": chart.get("natal_summary"),
        }

    def build_chart_from_request(
        self,
        payload: NatalChartCreateRequest,
        *,
        build_chart_fn=build_chart,
        save_chart_fn=save_chart,
    ) -> tuple[str, str | Path, dict[str, Any]]:
        time_basis = resolve_time_basis(payload.time_basis, payload.timezone)

        if time_basis == "local":
            local_dt, utc_dt = convert_local_datetime(
                payload.birth_date,
                payload.birth_time,
                payload.timezone or "",
                field_name="birth_time",
            )
            chart_date = utc_dt.date()
            ut_hour = time_to_decimal_hours(utc_dt.time())
            input_timezone = payload.timezone or "UTC"
        else:
            ut_hour = parse_ut_birth_time(payload.birth_time)
            local_dt = datetime.combine(
                payload.birth_date,
                decimal_hour_to_time(ut_hour, "birth_time"),
                tzinfo=timezone.utc,
            )
            utc_dt = local_dt
            chart_date = payload.birth_date
            input_timezone = "UTC"

        chart = build_chart_fn(
            chart_date.year,
            chart_date.month,
            chart_date.day,
            ut_hour,
            payload.latitude,
            payload.longitude,
            birth_input={
                "name": payload.name,
                "birth_date": payload.birth_date.isoformat(),
                "birth_time": str(payload.birth_time),
                "timezone": input_timezone,
                "location_name": payload.location_name,
                "local_birth_datetime": format_datetime(local_dt),
                "utc_birth_datetime": format_datetime(utc_dt),
                "latitude": payload.latitude,
                "longitude": payload.longitude,
                "time_basis": time_basis,
            },
        )
        chart_id = make_chart_id(
            chart_date.year,
            chart_date.month,
            chart_date.day,
            ut_hour,
        )
        saved_chart_id, output_path = save_chart_fn(chart, chart_id=chart_id)
        return saved_chart_id, output_path, chart
