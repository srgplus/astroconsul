from __future__ import annotations

from fastapi import APIRouter

from app.api.v1.routes.charts import router as charts_router
from app.api.v1.routes.health import router as health_router
from app.api.v1.routes.locations import router as locations_router
from app.api.v1.routes.profiles import router as profiles_router

router = APIRouter()
router.include_router(health_router)
router.include_router(charts_router)
router.include_router(locations_router)
router.include_router(profiles_router)
