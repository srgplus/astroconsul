from __future__ import annotations

ASPECTS = [
    {"name": "conjunction", "angle": 0, "orb": 8},
    {"name": "sextile", "angle": 60, "orb": 4},
    {"name": "square", "angle": 90, "orb": 6},
    {"name": "trine", "angle": 120, "orb": 6},
    {"name": "opposition", "angle": 180, "orb": 8},
]


def angular_delta(a: float, b: float) -> float:
    normalized_a = a % 360
    normalized_b = b % 360
    delta = abs(normalized_a - normalized_b)
    return min(delta, 360 - delta)


def detect_aspect(
    lon1: float,
    lon2: float,
    aspects: list[dict[str, float | int | str]] | None = None,
) -> dict[str, float | int | str] | None:
    delta = angular_delta(lon1, lon2)
    candidates: list[dict[str, float | int | str]] = []

    for aspect in ASPECTS if aspects is None else aspects:
        orb = abs(delta - float(aspect["angle"]))

        if orb <= float(aspect["orb"]):
            candidates.append(
                {
                    "aspect": str(aspect["name"]),
                    "angle": int(aspect["angle"]),
                    "orb": round(orb, 6),
                    "delta": round(delta, 6),
                }
            )

    if not candidates:
        return None

    candidates.sort(key=lambda item: item["orb"])
    return candidates[0]


def compute_natal_aspects(
    planets: dict[str, float],
    aspects: list[dict[str, float | int | str]] | None = None,
) -> list[dict[str, float | int | str]]:
    planet_names = list(planets.keys())
    natal_aspects: list[dict[str, float | int | str]] = []

    for index, p1 in enumerate(planet_names):
        for p2 in planet_names[index + 1 :]:
            match = detect_aspect(planets[p1], planets[p2], aspects=aspects)

            if match is not None:
                natal_aspects.append(
                    {
                        "p1": p1,
                        "p2": p2,
                        "aspect": match["aspect"],
                        "angle": match["angle"],
                        "orb": match["orb"],
                        "delta": match["delta"],
                    }
                )

    return natal_aspects
