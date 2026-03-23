from __future__ import annotations

import logging
from datetime import date, datetime
from itertools import combinations
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query

from app.api.dependencies import (
    get_profile_service,
    get_repositories,
)
from app.api.v1.routes.profiles import _build_natal_interpretations
from app.application.services.profile_service import ProfileService
from app.infrastructure.repositories.factory import RepositoryBundle

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/public", tags=["public"])


@router.get("/featured")
def get_featured_profiles(
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    profiles = repos.profiles.list_featured(limit=6)
    # Strip user_id from response — public callers don't need it
    for p in profiles:
        p.pop("user_id", None)
    return {"profiles": profiles}


@router.get("/profiles/{profile_id}")
def get_public_profile_detail(
    profile_id: str,
    lang: str = Query("en"),
    profile_service: ProfileService = Depends(get_profile_service),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, object]:
    try:
        # Use load_profile_with_social to get profile + followers in one session
        profile_data = repos.profiles.load_profile_with_social(profile_id, "")
        result = profile_service.profile_detail_from_loaded(
            profile_data,
            chart_repository=repos.charts,
        )
        result["chart"]["natal_interpretations"] = _build_natal_interpretations(
            result["chart"], lang,
        )
        # Public view: only followers_count, no user-specific fields
        result["profile"]["followers_count"] = profile_data["followers_count"]
        return result
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


# ---------------------------------------------------------------------------
# Cosmic Weather — public transit data for content generation
# ---------------------------------------------------------------------------

# Planets used for sky-wide aspect grid (exclude Moon for noise reduction)
_SKY_PLANETS = ["Sun", "Mercury", "Venus", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"]

# Tighter orbs for transit-to-transit (sky aspects, not natal)
_SKY_ASPECTS = [
    {"name": "conjunction", "angle": 0, "orb": 6},
    {"name": "sextile", "angle": 60, "orb": 3},
    {"name": "square", "angle": 90, "orb": 5},
    {"name": "trine", "angle": 120, "orb": 5},
    {"name": "opposition", "angle": 180, "orb": 6},
]


@router.get("/cosmic-weather")
def get_cosmic_weather(
    target_date: str = Query(None, alias="date", description="YYYY-MM-DD, defaults to today"),
) -> dict[str, Any]:
    """Return comprehensive transit data for a given date — used by content generation."""
    from aspect_engine import detect_aspect
    from app.domain.astrology.moon import compute_moon_phase
    from app.domain.astrology.tii import compute_retrograde_index
    from transit_builder import compute_transit_positions

    try:
        if target_date:
            dt = datetime.strptime(target_date, "%Y-%m-%d").date()
        else:
            dt = date.today()
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD.")

    # Equal houses (30° each) as placeholder — no natal chart needed
    equal_houses = [float(i * 30) for i in range(12)]

    try:
        positions = compute_transit_positions(
            dt.year, dt.month, dt.day, 12.0,  # noon UTC
            equal_houses,
        )
    except Exception:
        logger.exception("Failed to compute transit positions for %s", dt)
        raise HTTPException(status_code=500, detail="Ephemeris computation failed")

    # Moon phase
    moon_phase = compute_moon_phase(positions)

    # Retrograde index
    retro = compute_retrograde_index(positions)

    # Sky aspects: planet-to-planet (all pairs among main planets)
    pos_by_id = {str(p["id"]): p for p in positions}
    sky_aspects: list[dict[str, Any]] = []

    for p1, p2 in combinations(_SKY_PLANETS, 2):
        if p1 not in pos_by_id or p2 not in pos_by_id:
            continue
        lon1 = float(pos_by_id[p1]["longitude"])
        lon2 = float(pos_by_id[p2]["longitude"])
        asp = detect_aspect(lon1, lon2, _SKY_ASPECTS)
        if asp and float(asp["orb"]) <= 3.0:  # only tight aspects
            sky_aspects.append({
                "planet1": p1,
                "planet2": p2,
                "aspect": asp["aspect"],
                "orb": round(float(asp["orb"]), 2),
                "exact_angle": asp["angle"],
            })

    sky_aspects.sort(key=lambda a: a["orb"])

    # Simplify positions for response
    simple_positions = []
    for p in positions:
        pid = str(p.get("id", ""))
        if pid in ("Part of Fortune", "Vertex", "South Node"):
            continue  # skip derived points
        simple_positions.append({
            "planet": pid,
            "sign": str(p.get("sign", "")),
            "degree": int(p.get("degree", 0)),
            "minute": int(p.get("minute", 0)),
            "longitude": round(float(p.get("longitude", 0)), 4),
            "speed": round(float(p.get("speed", 0)), 4),
            "retrograde": bool(p.get("retrograde", False)),
        })

    return {
        "date": dt.isoformat(),
        "transit_positions": simple_positions,
        "moon_phase": moon_phase,
        "retrograde": retro,
        "sky_aspects": sky_aspects,
    }
