from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from app.api.dependencies import get_location_lookup_service
from app.application.services.location_lookup_service import LocationLookupService
from app.domain.astrology.locations import LocationResolutionError, resolve_location_name
from app.schemas.requests import LocationResolveRequest
from app.schemas.responses import LocationResponse

router = APIRouter(prefix="/locations", tags=["locations"])


@router.post("/resolve", response_model=LocationResponse)
def resolve_location(
    payload: LocationResolveRequest,
    location_service: LocationLookupService = Depends(get_location_lookup_service),
) -> dict[str, object]:
    try:
        return location_service.resolve(payload.location_name, resolver=resolve_location_name)
    except (LocationResolutionError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
