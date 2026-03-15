"""Transit Intensity Index (TII) — measures the overall intensity of active transits."""

from __future__ import annotations

# ---------------------------------------------------------------------------
# Weights & factors
# ---------------------------------------------------------------------------

ASPECT_WEIGHT: dict[str, float] = {
    "conjunction": 10,
    "opposition": 8,
    "square": 7,
    "trine": 6,
    "sextile": 5,
}

PLANET_FACTOR: dict[str, float] = {
    "Moon": 0.5,
    "Sun": 1.0,
    "Mercury": 1.0,
    "Venus": 1.0,
    "Mars": 1.0,
    "Jupiter": 1.3,
    "Saturn": 1.3,
    "Uranus": 1.5,
    "Neptune": 1.5,
    "Pluto": 1.5,
}

TENSION_ASPECTS: set[str] = {"square", "opposition"}

# Transit objects allowed in TII (10 classical planets only)
TII_TRANSIT_PLANETS: set[str] = set(PLANET_FACTOR.keys())

# Natal points allowed in TII (10 planets + ASC + MC)
TII_NATAL_POINTS: set[str] = set(PLANET_FACTOR.keys()) | {"ASC", "MC"}

# ---------------------------------------------------------------------------
# Feels-Like matrix:  TII bucket × tension bucket → label
# ---------------------------------------------------------------------------

_FEELS_LIKE_MATRIX: dict[tuple[str, str], str] = {
    # (tii_level, tension_level) → label
    ("low", "low"): "Calm",
    ("low", "mid"): "Subtle pressure",
    ("low", "high"): "Grinding",
    ("mid", "low"): "Flowing",
    ("mid", "mid"): "Dynamic",
    ("mid", "high"): "Pressured",
    ("high", "low"): "Expansive",
    ("high", "mid"): "Charged",
    ("high", "high"): "Intense",
    ("extreme", "low"): "Powerful",
    ("extreme", "mid"): "Volatile",
    ("extreme", "high"): "Explosive",
}


def _tii_bucket(tii: float) -> str:
    if tii < 25:
        return "low"
    if tii < 55:
        return "mid"
    if tii < 80:
        return "high"
    return "extreme"


def _tension_bucket(ratio: float) -> str:
    if ratio < 0.3:
        return "low"
    if ratio < 0.6:
        return "mid"
    return "high"


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def _orb_score(orb: float) -> float:
    """Tighter orb → higher score.  Capped at 10 to prevent explosion near 0."""
    return min(10.0, 1.0 / (orb + 0.1))


def _aspect_tii_contribution(aspect: dict) -> float:
    """Raw TII contribution of a single transit aspect."""
    transit_obj = str(aspect.get("transit_object", ""))
    natal_obj = str(aspect.get("natal_object", ""))
    aspect_name = str(aspect.get("aspect", ""))
    orb = float(aspect.get("orb", 99))

    if transit_obj not in TII_TRANSIT_PLANETS:
        return 0.0
    if natal_obj not in TII_NATAL_POINTS:
        return 0.0

    weight = ASPECT_WEIGHT.get(aspect_name, 0)
    planet = PLANET_FACTOR.get(transit_obj, 1.0)
    score = weight * _orb_score(orb) * planet

    # Exactness bonus: +20% when orb < 1°, +50% when orb < 0.1° (partile)
    if orb < 0.1:
        score *= 1.5
    elif orb < 1.0:
        score *= 1.2

    return score


def compute_tii(aspects: list[dict]) -> float:
    """Compute TII (0–100) from a list of active transit-to-natal aspects."""
    raw = sum(_aspect_tii_contribution(a) for a in aspects)
    # Normalize: 320 raw ≈ 100 TII
    return round(min(100.0, raw / 320.0 * 100.0), 1)


def compute_tension_ratio(aspects: list[dict]) -> float:
    """Fraction of TII weight contributed by hard aspects (square, opposition)."""
    tension_total = 0.0
    all_total = 0.0

    for aspect in aspects:
        contribution = _aspect_tii_contribution(aspect)
        all_total += contribution
        if str(aspect.get("aspect", "")) in TENSION_ASPECTS:
            tension_total += contribution

    if all_total == 0:
        return 0.0
    return round(tension_total / all_total, 2)


def feels_like(tii: float, tension_ratio: float) -> str:
    """Human-readable intensity label from the TII × tension matrix."""
    return _FEELS_LIKE_MATRIX.get(
        (_tii_bucket(tii), _tension_bucket(tension_ratio)),
        "Neutral",
    )


def top_active_transits(aspects: list[dict], n: int = 3) -> list[dict]:
    """Return the *n* aspects with the highest TII contribution."""
    scored = []
    for aspect in aspects:
        contribution = _aspect_tii_contribution(aspect)
        if contribution > 0:
            scored.append({**aspect, "_tii_contribution": round(contribution, 2)})

    scored.sort(key=lambda a: a["_tii_contribution"], reverse=True)
    return scored[:n]
