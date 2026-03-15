from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from app.api.dependencies import get_location_lookup_service
from app.application.services.location_lookup_service import LocationLookupService
from app.domain.astrology.locations import LocationResolutionError, resolve_location_name, search_places
from app.schemas.requests import LocationResolveRequest
from app.schemas.responses import LocationResponse

router = APIRouter(prefix="/locations", tags=["locations"])


@router.get("/search")
def location_search(q: str = Query(..., min_length=2)) -> list[dict[str, object]]:
    """Autocomplete endpoint: returns up to 8 place candidates."""
    return search_places(q, limit=8)


@router.post("/resolve", response_model=LocationResponse)
def resolve_location(
    payload: LocationResolveRequest,
    location_service: LocationLookupService = Depends(get_location_lookup_service),
) -> dict[str, object]:
    try:
        return location_service.resolve(payload.location_name, resolver=resolve_location_name)
    except (LocationResolutionError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
