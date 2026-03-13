from __future__ import annotations

from fastapi import APIRouter

from app.api.handlers import resolve_location_handler
from app.schemas.requests import LocationResolveRequest

router = APIRouter(prefix="/locations", tags=["locations"])


@router.post("/resolve")
def resolve_location(payload: LocationResolveRequest) -> dict[str, object]:
    return resolve_location_handler(payload)

