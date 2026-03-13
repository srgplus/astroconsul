from __future__ import annotations

from fastapi import APIRouter

from app.api.handlers import calculate_chart_handler
from app.schemas.requests import NatalDebugRequest

router = APIRouter(prefix="/charts", tags=["charts"])


@router.post("/natal")
def natal_debug(payload: NatalDebugRequest) -> dict[str, object]:
    return calculate_chart_handler(
        payload.year,
        payload.month,
        payload.day,
        payload.hour,
        payload.lat,
        payload.lon,
    )

