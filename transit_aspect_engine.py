from __future__ import annotations

from aspect_engine import ASPECTS, angular_delta
from app.data.transit_aspects_lookup import get_aspect_description


def detect_transit_aspect(
    transit_longitude: float,
    natal_longitude: float,
) -> dict[str, float | int | str | bool] | None:
    delta = angular_delta(transit_longitude, natal_longitude)
    candidates: list[dict[str, float | int | str | bool]] = []

    for aspect in ASPECTS:
        orb = abs(delta - float(aspect["angle"]))

        if orb <= float(aspect["orb"]):
            candidates.append(
                {
                    "aspect": str(aspect["name"]),
                    "exact_angle": int(aspect["angle"]),
                    "delta": round(delta, 6),
                    "orb": round(orb, 6),
                    "is_within_orb": True,
                }
            )

    if not candidates:
        return None

    candidates.sort(key=lambda item: item["orb"])
    return candidates[0]


def aspect_strength(orb: float) -> str:
    if orb <= 0.25:
        return "exact"
    if orb <= 1.0:
        return "strong"
    if orb <= 1.99:
        return "moderate"
    return "wide"


def compute_transit_to_natal_aspects(
    transit_objects: list[dict[str, object]],
    natal_planets: dict[str, float],
    natal_angles: dict[str, float],
    *,
    lang: str = "en",
) -> list[dict[str, object]]:
    aspects: list[dict[str, object]] = []
    natal_objects = list(natal_planets.items()) + [
        ("ASC", float(natal_angles["asc"])),
        ("MC", float(natal_angles["mc"])),
    ]

    for transit_object in transit_objects:
        transit_longitude = float(transit_object["longitude"])

        for natal_object, natal_longitude in natal_objects:
            match = detect_transit_aspect(transit_longitude, natal_longitude)

            if match is None:
                continue

            desc = get_aspect_description(
                str(transit_object["id"]),
                str(match["aspect"]),
                natal_object,
                lang=lang,
            )
            aspects.append(
                {
                    "transit_object": transit_object["id"],
                    "natal_object": natal_object,
                    "aspect": match["aspect"],
                    "exact_angle": match["exact_angle"],
                    "delta": match["delta"],
                    "orb": match["orb"],
                    "is_within_orb": match["is_within_orb"],
                    "strength": aspect_strength(float(match["orb"])),
                    "meaning": desc["meaning"],
                    "action": desc["action"],
                    "keywords": desc["keywords"],
                }
            )

    return aspects
