"""Synastry (inter-chart) aspect detection and compatibility scoring."""

from __future__ import annotations

import math

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

# ---------------------------------------------------------------------------
# Planet importance weights — personal planets dominate scoring,
# minor points barely affect it.
# ---------------------------------------------------------------------------

PLANET_IMPORTANCE: dict[str, float] = {
    "Sun": 10, "Moon": 10,
    "Venus": 8, "Mars": 8,
    "Mercury": 6,
    "ASC": 6, "MC": 4,
    "Jupiter": 5, "Saturn": 5,
    "Uranus": 3, "Neptune": 3, "Pluto": 4,
    "North Node": 3, "South Node": 2,
    "Chiron": 3, "Lilith": 2,
    "Selena": 1, "Part of Fortune": 1, "Vertex": 1,
}


def _pair_importance(a_obj: str, b_obj: str) -> float:
    """Geometric-mean importance of two objects (1.0–10.0)."""
    wa = PLANET_IMPORTANCE.get(a_obj, 1)
    wb = PLANET_IMPORTANCE.get(b_obj, 1)
    return (wa * wb) ** 0.5


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


def _aspect_score(aspect: dict) -> tuple[float, float]:
    """Compute a weighted score and importance for a single aspect.

    Returns (weighted_score, importance) where weighted_score already
    incorporates planet-pair importance so that Sun-Moon aspects dominate
    over Selena-Vertex etc.
    """
    aspect_name = aspect["aspect"]
    orb = aspect["orb"]
    a_obj = aspect["person_a_object"]
    b_obj = aspect["person_b_object"]

    base = ASPECT_WEIGHTS.get(aspect_name, 0.0)

    # Conjunction with hard planets is intense but not clearly harmonious
    if aspect_name == "conjunction" and ({a_obj, b_obj} & HARD_CONJUNCTION_PLANETS):
        base = 0.0  # Neutral — intensity without clear harmony

    # Opposition between lights/Venus can be magnetic (attraction)
    if aspect_name == "opposition" and ({a_obj, b_obj} & {"Sun", "Moon", "Venus", "Mars"}):
        base = 2.0  # Flip to positive — magnetic attraction

    # Orb multiplier: tighter = stronger effect (1.0 at 0°, ~0.2 at max orb)
    max_orb = 8.0
    orb_factor = max(0.0, 1.0 - (orb / max_orb))

    importance = _pair_importance(a_obj, b_obj)
    return base * orb_factor * importance, importance


def compute_synastry_scores(aspects: list[dict]) -> dict:
    """Compute overall and category compatibility scores.

    Only aspects between significant planets (pair importance >= 5) affect
    the score.  Uses a harmony-ratio approach: the proportion of positive
    weighted score to total, with a tension amplifier (×3) to counteract
    the structural positive bias of aspect weights.

    Returns
    -------
    dict with keys: overall, overall_label, emotional, mental, physical, karmic
    All scores are 0–100.
    """
    _IMPORTANCE_FLOOR = 5.0
    _TENSION_AMPLIFIER = 3.0

    cats = ("emotional", "mental", "physical", "karmic", "general")
    pos: dict[str, float] = {c: 0.0 for c in cats}
    neg: dict[str, float] = {c: 0.0 for c in cats}

    for aspect in aspects:
        score, importance = _aspect_score(aspect)
        if importance < _IMPORTANCE_FLOOR:
            continue
        categories = _categorize_aspect(
            aspect["person_a_object"], aspect["person_b_object"]
        )
        for cat in categories:
            if score >= 0:
                pos[cat] += score
            else:
                neg[cat] += abs(score) * _TENSION_AMPLIFIER

    def _harmony_score(positive: float, negative: float) -> int:
        """Harmony ratio mapped to 5–95 range."""
        total = positive + negative
        if total < 1.0:
            return 50
        ratio = positive / total  # 0.0 – 1.0
        return max(5, min(95, round(ratio * 90 + 5)))

    emotional = _harmony_score(pos["emotional"], neg["emotional"])
    mental = _harmony_score(pos["mental"], neg["mental"])
    physical = _harmony_score(pos["physical"], neg["physical"])
    karmic = _harmony_score(pos["karmic"], neg["karmic"])

    all_pos = sum(pos.values())
    all_neg = sum(neg.values())
    overall = _harmony_score(all_pos, all_neg)

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
