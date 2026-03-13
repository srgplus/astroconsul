from __future__ import annotations

from fastapi import APIRouter, Depends

from app.api.dependencies import get_health_service
from app.application.services.health_service import HealthService
from app.schemas.responses import LiveResponse, ReadyResponse

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/live", response_model=LiveResponse)
def live(health_service: HealthService = Depends(get_health_service)) -> dict[str, object]:
    return health_service.live()


@router.get("/ready", response_model=ReadyResponse)
def ready(health_service: HealthService = Depends(get_health_service)) -> dict[str, object]:
    return health_service.ready()
