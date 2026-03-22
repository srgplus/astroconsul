"""Synastry (inter-chart) aspect detection and compatibility scoring."""

from __future__ import annotations

from aspect_engine import ASPECTS, angular_delta

# ---------------------------------------------------------------------------
# Synastry-specific orbs (tighter than natal, matches transit engine)
# ---------------------------------------------------------------------------

SYNASTRY_ASPECTS = [
    {"name": "conjunction", "angle": 0, "orb": 8},
    {"name": "sextile", "angle": 60, "orb": 4},
    {"name": "square", "angle": 90, "orb": 6},
    {"name": "trine", "angle": 120, "orb": 6},
    {"name": "opposition", "angle": 180, "orb": 8},
]

# ---------------------------------------------------------------------------
# Planet category mapping for scoring
# ---------------------------------------------------------------------------

EMOTIONAL_PLANETS = {"Moon", "Venus", "Neptune"}
MENTAL_PLANETS = {"Mercury", "Jupiter", "Uranus"}
PHYSICAL_PLANETS = {"Sun", "Mars", "ASC"}
KARMIC_PLANETS = {"Saturn", "Pluto", "North Node", "South Node", "Lilith", "Chiron"}

# Aspect harmony weights: positive = harmonious, negative = tense
# For conjunction, the weight depends on planets involved
ASPECT_WEIGHTS: dict[str, float] = {
    "conjunction": 8.0,
    "trine": 6.0,
    "sextile": 4.0,
    "square": -3.0,
    "opposition": -2.0,
}

# Planets whose conjunction adds tension rather than harmony
HARD_CONJUNCTION_PLANETS = {"Saturn", "Pluto", "Lilith", "South Node"}


def synastry_aspect_strength(orb: float) -> str:
    """Classify aspect strength by orb for synastry."""
    if orb < 1.0:
        return "exact"
    if orb < 3.0:
        return "strong"
    if orb < 5.0:
        return "moderate"
    return "wide"


def compute_synastry_aspects(
    person_a_positions: list[dict],
    person_b_positions: list[dict],
    person_b_angles: dict[str, float] | None = None,
) -> list[dict]:
    """Compute inter-chart aspects between two natal charts.

    Parameters
    ----------
    person_a_positions : list[dict]
        Person A's natal positions (each has 'id' and 'longitude').
    person_b_positions : list[dict]
        Person B's natal positions (each has 'id' and 'longitude').
    person_b_angles : dict | None
        Person B's angles {'asc': float, 'mc': float} — added to B's objects.

    Returns
    -------
    list[dict]
        List of synastry aspects sorted by orb (tightest first).
    """
    aspects: list[dict] = []

    # Build B objects list (planets + angles)
    b_objects: list[tuple[str, float]] = [
        (pos["id"], float(pos["longitude"])) for pos in person_b_positions
    ]
    if person_b_angles:
        if "asc" in person_b_angles:
            b_objects.append(("ASC", float(person_b_angles["asc"])))
        if "mc" in person_b_angles:
            b_objects.append(("MC", float(person_b_angles["mc"])))

    for a_pos in person_a_positions:
        a_id = a_pos["id"]
        a_lon = float(a_pos["longitude"])

        for b_id, b_lon in b_objects:
            delta = angular_delta(a_lon, b_lon)
            candidates: list[dict] = []

            for aspect_def in SYNASTRY_ASPECTS:
                orb = abs(delta - float(aspect_def["angle"]))
                if orb <= float(aspect_def["orb"]):
                    candidates.append({
                        "person_a_object": a_id,
                        "person_b_object": b_id,
                        "aspect": str(aspect_def["name"]),
                        "exact_angle": int(aspect_def["angle"]),
                        "delta": round(delta, 4),
                        "orb": round(orb, 4),
                        "strength": synastry_aspect_strength(orb),
                    })

            if candidates:
                candidates.sort(key=lambda x: x["orb"])
                aspects.append(candidates[0])

    aspects.sort(key=lambda x: x["orb"])
    return aspects


def _categorize_aspect(a_obj: str, b_obj: str) -> list[str]:
    """Return which scoring categories an aspect belongs to."""
    categories: list[str] = []
    objects = {a_obj, b_obj}
    if objects & EMOTIONAL_PLANETS:
        categories.append("emotional")
    if objects & MENTAL_PLANETS:
        categories.append("mental")
    if objects & PHYSICAL_PLANETS:
        categories.append("physical")
    if objects & KARMIC_PLANETS:
        categories.append("karmic")
    # If no specific category, count toward overall only
    return categories if categories else ["general"]


def _aspect_score(aspect: dict) -> float:
    """Compute a raw score contribution for a single aspect.

    Tighter orbs contribute more. Harmonious aspects add, tense subtract
    (but tension also adds chemistry, so the penalty is mild).
    """
    aspect_name = aspect["aspect"]
    orb = aspect["orb"]
    a_obj = aspect["person_a_object"]
    b_obj = aspect["person_b_object"]

    base = ASPECT_WEIGHTS.get(aspect_name, 0.0)

    # Conjunction with hard planets is more ambivalent
    if aspect_name == "conjunction" and ({a_obj, b_obj} & HARD_CONJUNCTION_PLANETS):
        base = 3.0  # Still positive but reduced

    # Opposition between lights/Venus can be magnetic (attraction)
    if aspect_name == "opposition" and ({a_obj, b_obj} & {"Sun", "Moon", "Venus", "Mars"}):
        base = 2.0  # Flip to positive — magnetic attraction

    # Orb multiplier: tighter = stronger effect (1.0 at 0°, ~0.2 at max orb)
    max_orb = 8.0
    orb_factor = max(0.0, 1.0 - (orb / max_orb))

    return base * orb_factor


def compute_synastry_scores(aspects: list[dict]) -> dict:
    """Compute overall and category compatibility scores.

    Returns
    -------
    dict with keys: overall, overall_label, emotional, mental, physical, karmic
    All scores are 0–100.
    """
    raw: dict[str, float] = {
        "emotional": 0.0,
        "mental": 0.0,
        "physical": 0.0,
        "karmic": 0.0,
        "general": 0.0,
    }
    counts: dict[str, int] = {k: 0 for k in raw}

    for aspect in aspects:
        score = _aspect_score(aspect)
        categories = _categorize_aspect(
            aspect["person_a_object"], aspect["person_b_object"]
        )
        for cat in categories:
            raw[cat] += score
            counts[cat] += 1

    def _normalize(raw_score: float, count: int) -> int:
        """Normalize a raw score to 0-100 range."""
        if count == 0:
            return 50  # Neutral if no aspects in category
        # Baseline: 50 (neutral). Each point of raw_score shifts by ~5.
        normalized = 50 + (raw_score * 4.0)
        return max(0, min(100, round(normalized)))

    emotional = _normalize(raw["emotional"], counts["emotional"])
    mental = _normalize(raw["mental"], counts["mental"])
    physical = _normalize(raw["physical"], counts["physical"])
    karmic = _normalize(raw["karmic"], counts["karmic"])

    # Overall = weighted average of all categories + general
    total_raw = sum(raw.values())
    total_count = sum(counts.values())
    overall = _normalize(total_raw, total_count)

    label = _score_label(overall)

    return {
        "overall": overall,
        "overall_label": label,
        "emotional": emotional,
        "mental": mental,
        "physical": physical,
        "karmic": karmic,
    }


def _score_label(score: int) -> str:
    if score >= 86:
        return "Soulmate"
    if score >= 71:
        return "Magnetic"
    if score >= 51:
        return "Harmonious"
    if score >= 31:
        return "Complex"
    return "Challenging"


def _score_label_ru(score: int) -> str:
    if score >= 86:
        return "Родственные души"
    if score >= 71:
        return "Магнетизм"
    if score >= 51:
        return "Гармония"
    if score >= 31:
        return "Сложная связь"
    return "Вызов"
