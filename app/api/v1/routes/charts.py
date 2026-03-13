from __future__ import annotations

from fastapi import APIRouter

from app.domain.astrology.charts import build_chart
from app.schemas.requests import NatalDebugRequest
from app.schemas.responses import NatalChartDebugResponse

router = APIRouter(prefix="/charts", tags=["charts"])


@router.post("/natal", response_model=NatalChartDebugResponse)
def natal_debug(payload: NatalDebugRequest) -> dict[str, object]:
    chart = build_chart(payload.year, payload.month, payload.day, payload.hour, payload.lat, payload.lon)
    return {
        "julian_day": chart["julian_day"],
        "swiss_ephemeris_version": chart["swiss_ephemeris_version"],
        "ephemeris_path": chart["ephemeris_path"],
        "ephemeris_sources": chart["ephemeris_sources"],
        "planets": chart["planets"],
        "natal_positions": chart["natal_positions"],
        "asc": chart["angles"]["asc"],  # type: ignore[index]
        "mc": chart["angles"]["mc"],  # type: ignore[index]
        "angles": chart["angles"],
        "angle_positions": chart.get("angle_positions"),
        "houses": chart["houses"],
        "natal_aspects": chart["natal_aspects"],
        "natal_summary": chart.get("natal_summary"),
    }
