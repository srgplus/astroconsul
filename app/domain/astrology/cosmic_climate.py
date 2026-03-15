"""Cosmic Climate — long-duration outer-planet transits that set the background tone."""

from __future__ import annotations

from app.data.cosmic_climate_lookup import get_cosmic_description

COSMIC_TRANSIT_PLANETS = {"Pluto", "Neptune", "Uranus", "Jupiter"}
COSMIC_NATAL_POINTS = {"Sun", "Moon", "Venus", "Mars", "ASC", "MC"}
COSMIC_MIN_DURATION_DAYS = 45
COSMIC_MAX_CARDS = 5


def _weight(aspect: dict) -> float:
    """Longer + tighter orb = more important."""
    timing = aspect.get("timing") or {}
    duration_hours = timing.get("duration_hours") or 0
    duration_days = duration_hours / 24
    orb = float(aspect.get("orb", 99))
    return duration_days / max(orb, 0.01)


def get_cosmic_climate(active_aspects: list[dict], lang: str = "ru") -> list[dict]:
    """Filter and rank the most significant long-duration outer planet transits.

    Returns up to COSMIC_MAX_CARDS aspects sorted by weight (duration/orb).
    Each aspect is enriched with cosmic-specific meaning and insight.
    """
    candidates = []
    for a in active_aspects:
        transit_obj = str(a.get("transit_object", ""))
        natal_obj = str(a.get("natal_object", ""))
        timing = a.get("timing")

        if transit_obj not in COSMIC_TRANSIT_PLANETS:
            continue
        if natal_obj not in COSMIC_NATAL_POINTS:
            continue
        if not timing:
            continue

        duration_hours = timing.get("duration_hours") or 0
        duration_days = duration_hours / 24
        if duration_days < COSMIC_MIN_DURATION_DAYS:
            continue

        candidates.append(a)

    candidates.sort(key=_weight, reverse=True)
    top = candidates[:COSMIC_MAX_CARDS]

    # Enrich with cosmic-specific descriptions
    enriched = []
    for aspect in top:
        enriched_aspect = dict(aspect)
        cosmic = get_cosmic_description(
            str(aspect.get("transit_object", "")),
            str(aspect.get("aspect", "")),
            str(aspect.get("natal_object", "")),
            lang=lang,
        )
        if cosmic:
            enriched_aspect["meaning"] = cosmic["meaning"]
            enriched_aspect["insight"] = cosmic.get("insight")
        enriched.append(enriched_aspect)

    return enriched
