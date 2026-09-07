"""Server-side enforcement of the free/Pro split on interpretation prose.

What a Pro subscription buys is the *written* part of a report — ``meaning``,
``action``, ``insight`` and ``keywords`` on an aspect, and the whole
``natal_interpretations`` block on a chart. The computed astrology around it
(positions, aspects, orbs, TII, timing) is free.

The React client already hides the prose a free account is not entitled to,
but that is presentation only: the response still carried every word, so the
entire paid report was readable from the browser's network tab. These helpers
take it out of the payload instead.

A free account keeps ``FREE_LIMIT`` interpretations per list — the same
allowance the client draws unlocked. *Which* entries those are has to agree
with the client's own ordering, or a free user taps one of their three
unlocked rows and finds it empty, so the orderings below mirror the client:

* ``frontend/src/components/TransitsTab.tsx`` — group, then orb
* ``frontend/src/components/DailyWeather.tsx`` — group, then transiting body,
  then orb, over the "most impact" subset it opens on
* ``frontend/src/components/ProfileDetail.tsx`` — group, then body, then orb

Where two surfaces order the same list differently, the allowance is the union
of the first ``FREE_LIMIT`` of each, so every row either one opens on carries
its text. The unions cover each surface's *default* view; narrowing a list
with its own filter can leave a free account fewer than three unlocked rows,
which the client renders as a lock rather than as empty prose. Change an
ordering in those files and this module has to follow.
"""

from __future__ import annotations

from typing import Any

from fastapi import Depends

from app.api.auth import get_current_user
from app.core.config import get_settings

# Same number the client uses as FREE_LIMIT.
FREE_LIMIT = 3

# Written text on an aspect. The rest of the record is free.
PAID_ASPECT_FIELDS = ("meaning", "action", "insight", "keywords")

# Grouping of the transiting body, from TransitsTab and DailyWeather.
_TRANSIT_PERSONAL = frozenset({"Sun", "Moon", "Mercury", "Venus", "Mars"})
_TRANSIT_OUTER = frozenset({"Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"})

# DailyWeather's TRANSIT_PLANET_ORDER.
_TRANSIT_OBJECT_ORDER = (
    "Sun",
    "Moon",
    "Mercury",
    "Venus",
    "Mars",
    "Jupiter",
    "Saturn",
    "Uranus",
    "Neptune",
    "Pluto",
    "Chiron",
    "Lilith",
    "Selena",
    "North Node",
    "South Node",
    "Part of Fortune",
    "Vertex",
)

# ProfileDetail's GROUPS, flattened — the order NatalPositionsTable draws rows in.
_NATAL_POSITION_ORDER = (
    "Sun",
    "Moon",
    "ASC",
    "MC",
    "Mercury",
    "Venus",
    "Mars",
    "Jupiter",
    "Saturn",
    "Uranus",
    "Neptune",
    "Pluto",
    "Chiron",
    "Lilith",
    "Selena",
    "North Node",
    "South Node",
    "Part of Fortune",
    "Vertex",
)

# ProfileDetail's PLANET_ORDER and its aspect grouping, both keyed on p1.
_NATAL_ASPECT_ORDER = (
    "Sun",
    "Moon",
    "Mercury",
    "Venus",
    "Mars",
    "ASC",
    "MC",
    "Jupiter",
    "Saturn",
    "Uranus",
    "Neptune",
    "Pluto",
    "Chiron",
    "Lilith",
    "Selena",
    "North Node",
    "South Node",
    "Part of Fortune",
    "Vertex",
)
_NATAL_PERSONAL = frozenset({"Sun", "Moon", "Mercury", "Venus", "Mars", "ASC", "MC"})
_NATAL_OUTER = _TRANSIT_OUTER

# NatalPositionsTable reads a cusp interpretation for the two angles only.
_ANGLE_HOUSE = {"ASC": "house_1", "MC": "house_10"}


# ── Pro status ───────────────────────────────────────────────────────


def caller_is_pro(user: dict[str, Any] = Depends(get_current_user)) -> bool:
    """FastAPI dependency: may this caller read the written interpretations?

    With auth disabled — the local default — every request is the same
    synthetic user and there is no subscription table to read, so development
    sees the full report. On Railway auth is on and the answer comes from the
    subscription record.
    """
    settings = get_settings()
    if not settings.auth_enabled:
        return True

    from app.api.v1.routes.subscriptions import get_user_subscription

    return bool(get_user_subscription(user["user_id"])["is_pro"])


# ── Field-level helpers ──────────────────────────────────────────────


def _without_prose(item: dict[str, Any]) -> dict[str, Any]:
    """Copy of *item* with its paid text blanked but its shape intact.

    The record still carries free data — orb, strength, timing — so the entry
    stays and only the words go. ``None`` rather than a dropped key keeps the
    ``string | null`` contract the client's types declare.
    """
    stripped = dict(item)
    for field in PAID_ASPECT_FIELDS:
        if field in stripped:
            stripped[field] = None
    return stripped


def _orb(item: dict[str, Any]) -> float:
    try:
        return float(item.get("orb", 99.0))
    except (TypeError, ValueError):
        return 99.0


def _rank(object_id: Any, order: tuple[str, ...]) -> int:
    try:
        return order.index(str(object_id))
    except ValueError:
        return len(order)


def _group_rank(object_id: Any, personal: frozenset[str], outer: frozenset[str]) -> int:
    name = str(object_id)
    if name in personal:
        return 0
    if name in outer:
        return 1
    return 2


def _first_free(indices: list[int]) -> set[int]:
    return set(indices[:FREE_LIMIT])


# ── Transit report ───────────────────────────────────────────────────


def _is_most_impact(aspect: dict[str, Any]) -> bool:
    """The subset DailyWeather's "most impact" toggle opens on."""
    strength = aspect.get("strength")
    if strength is not None:
        return str(strength) in ("exact", "strong")
    return _orb(aspect) <= 1.0


def _free_transit_aspect_indices(aspects: list[dict[str, Any]]) -> set[int]:
    """Indices of the transit aspects a free account keeps prose on."""
    if not aspects:
        return set()

    # TransitsTab: group, then the report's own order, which is orb ascending.
    # (It sorts by strength then orb, but strength is a band of orb, so the
    # two keys agree.)
    tab_order = sorted(
        range(len(aspects)),
        key=lambda i: (
            _group_rank(aspects[i].get("transit_object"), _TRANSIT_PERSONAL, _TRANSIT_OUTER),
            _orb(aspects[i]),
            i,
        ),
    )

    # DailyWeather: group, then transiting body, then orb — over "most impact".
    widget_order = sorted(
        (i for i in range(len(aspects)) if _is_most_impact(aspects[i])),
        key=lambda i: (
            _group_rank(aspects[i].get("transit_object"), _TRANSIT_PERSONAL, _TRANSIT_OUTER),
            _rank(aspects[i].get("transit_object"), _TRANSIT_OBJECT_ORDER),
            _orb(aspects[i]),
            i,
        ),
    )

    return _first_free(tab_order) | _first_free(widget_order)


def strip_transit_report(report: dict[str, Any]) -> dict[str, Any]:
    """Return *report* with the prose a free account is not entitled to removed."""
    result = dict(report)

    aspects = result.get("active_aspects")
    if aspects:
        allowed = _free_transit_aspect_indices(aspects)
        result["active_aspects"] = [
            dict(aspect) if index in allowed else _without_prose(aspect) for index, aspect in enumerate(aspects)
        ]

    # A free account is shown no climate prose at all — CosmicClimateWidget
    # draws the header and an Unlock button — and nothing renders the prose
    # that rides along on top_transits, so none of either survives.
    for key in ("cosmic_climate", "top_transits"):
        items = result.get(key)
        if items:
            result[key] = [_without_prose(item) for item in items]

    return result


def strip_forecast(forecast: dict[str, Any]) -> dict[str, Any]:
    """Return *forecast* with the prose stripped from each day's top transits.

    ``top_active_transits`` copies whole aspect records, so a 30-day forecast
    was carrying three written interpretations per day that no screen reads.
    """
    days = forecast.get("days")
    if not days:
        return forecast

    result = dict(forecast)
    result["days"] = [
        {**day, "top_transits": [_without_prose(item) for item in day["top_transits"]]}
        if day.get("top_transits")
        else day
        for day in days
    ]
    return result


# ── Natal interpretations ────────────────────────────────────────────


def _free_position_ids(interpretations: dict[str, Any], positions: list[dict[str, Any]]) -> set[str]:
    """Bodies whose interpretation a free account keeps.

    NatalPositionsTable counts only the rows it can actually expand, so this
    counts the same: a body with no interpretation is not one of the three.
    """
    in_signs = interpretations.get("planets_in_signs") or {}
    in_houses = interpretations.get("planets_in_houses") or {}
    cusps = interpretations.get("house_cusps_in_signs") or {}
    present = {str(position.get("id")) for position in positions}

    allowed: set[str] = set()
    for object_id in _NATAL_POSITION_ORDER:
        if object_id not in present:
            continue
        cusp_key = _ANGLE_HOUSE.get(object_id)
        if object_id in in_signs or object_id in in_houses or (cusp_key is not None and cusp_key in cusps):
            allowed.add(object_id)
        if len(allowed) == FREE_LIMIT:
            break
    return allowed


def _free_aspect_keys(aspects: list[dict[str, Any]]) -> set[tuple[str, str, str]]:
    """``(p1, aspect, p2)`` of the natal aspect rows a free account keeps.

    NatalAspectsTable opens on its "most impact" subset — orb under 3° — and
    locks by row index, whether or not the row has an interpretation, so an
    uninterpreted row inside the first three simply spends one of them.
    """
    if not aspects:
        return set()

    ordered = sorted(
        (index for index in range(len(aspects)) if _orb(aspects[index]) < 3),
        key=lambda index: (
            _group_rank(aspects[index].get("p1"), _NATAL_PERSONAL, _NATAL_OUTER),
            _rank(aspects[index].get("p1"), _NATAL_ASPECT_ORDER),
            _orb(aspects[index]),
            index,
        ),
    )

    keys: set[tuple[str, str, str]] = set()
    for index in ordered[:FREE_LIMIT]:
        aspect = aspects[index]
        keys.add((str(aspect.get("p1")), str(aspect.get("aspect")), str(aspect.get("p2"))))
    return keys


def strip_natal_interpretations(chart: dict[str, Any]) -> dict[str, Any]:
    """Return *chart* holding only the interpretations a free account may read.

    Every field of an interpretation entry is written text, and the body,
    sign, house and orb it is keyed on are already in ``natal_positions`` and
    ``natal_aspects``, so entries past the allowance are dropped outright
    rather than blanked.
    """
    interpretations = chart.get("natal_interpretations")
    if not interpretations:
        return chart

    positions = chart.get("natal_positions") or []
    aspects = chart.get("natal_aspects") or []

    allowed_ids = _free_position_ids(interpretations, positions)
    allowed_cusps = {_ANGLE_HOUSE[object_id] for object_id in allowed_ids if object_id in _ANGLE_HOUSE}
    allowed_aspects = _free_aspect_keys(aspects)

    result = dict(chart)
    result["natal_interpretations"] = {
        "planets_in_signs": {
            key: value for key, value in (interpretations.get("planets_in_signs") or {}).items() if key in allowed_ids
        },
        "planets_in_houses": {
            key: value for key, value in (interpretations.get("planets_in_houses") or {}).items() if key in allowed_ids
        },
        "house_cusps_in_signs": {
            key: value
            for key, value in (interpretations.get("house_cusps_in_signs") or {}).items()
            if key in allowed_cusps
        },
        "aspects": [
            entry
            for entry in (interpretations.get("aspects") or [])
            if (str(entry.get("p1")), str(entry.get("aspect")), str(entry.get("p2"))) in allowed_aspects
        ],
    }
    return result


def strip_profile_detail(detail: dict[str, Any]) -> dict[str, Any]:
    """Return a profile detail response with the chart's prose gated."""
    chart = detail.get("chart")
    if not chart:
        return detail
    return {**detail, "chart": strip_natal_interpretations(chart)}
