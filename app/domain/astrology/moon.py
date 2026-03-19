"""Moon phase computation from transit positions."""

from __future__ import annotations

import math


PHASE_RANGES: list[tuple[float, float, str]] = [
    (0, 3, "New Moon"),
    (3, 87, "Waxing Crescent"),
    (87, 93, "First Quarter"),
    (93, 177, "Waxing Gibbous"),
    (177, 183, "Full Moon"),
    (183, 267, "Waning Gibbous"),
    (267, 273, "Third Quarter"),
    (273, 357, "Waning Crescent"),
    (357, 360.01, "New Moon"),
]

PHASE_EMOJI: dict[str, str] = {
    "New Moon": "\U0001F311",
    "Waxing Crescent": "\U0001F312",
    "First Quarter": "\U0001F313",
    "Waxing Gibbous": "\U0001F314",
    "Full Moon": "\U0001F315",
    "Waning Gibbous": "\U0001F316",
    "Third Quarter": "\U0001F317",
    "Waning Crescent": "\U0001F318",
}


def compute_moon_phase(transit_positions: list[dict]) -> dict | None:
    """Compute moon phase from Sun and Moon transit positions.

    Returns dict with phase_name, phase_angle, illumination_pct,
    moon_sign, moon_degree, phase_emoji. Returns None if Moon/Sun not found.
    """
    moon = None
    sun = None
    for pos in transit_positions:
        obj_id = pos.get("id")
        if obj_id == "Moon":
            moon = pos
        elif obj_id == "Sun":
            sun = pos
        if moon and sun:
            break

    if not moon or not sun:
        return None

    moon_lon = float(moon["longitude"])
    sun_lon = float(sun["longitude"])

    elongation = (moon_lon - sun_lon) % 360
    illumination_pct = (1 - math.cos(math.radians(elongation))) / 2 * 100

    phase_name = "Waxing Crescent"  # fallback
    for low, high, name in PHASE_RANGES:
        if low <= elongation < high:
            phase_name = name
            break

    return {
        "phase_name": phase_name,
        "phase_angle": round(elongation, 1),
        "illumination_pct": round(illumination_pct, 1),
        "moon_sign": str(moon.get("sign", "")),
        "moon_degree": int(moon.get("degree", 0)),
        "phase_emoji": PHASE_EMOJI.get(phase_name, "\U0001F315"),
    }
