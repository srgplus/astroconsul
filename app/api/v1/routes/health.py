from __future__ import annotations

from fastapi import APIRouter

from app.api.dependencies import get_health_service

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/live")
def live() -> dict[str, object]:
    return get_health_service().live()


@router.get("/ready")
def ready() -> dict[str, object]:
    return get_health_service().ready()

