"""Natal chart interpretation lookups.

Loads natal JSON files once at import time. Provides lookup functions
for planet-in-sign, planet-in-house, house-cusp-in-sign, natal aspects,
and reference data (houses, planets, signs definitions).

All files are bilingual (EN + RU).

Usage::

    from app.data.natal_lookup import (
        get_planet_in_sign,
        get_planet_in_house,
        get_house_cusp_in_sign,
        get_natal_aspect,
        get_reference,
    )

    desc = get_planet_in_sign("Sun", "Aries")
    # {"meaning": "...", "keywords": ["...", ...]}

    desc_ru = get_planet_in_sign("Sun", "Aries", lang="ru")
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

_DATA_DIR = Path(__file__).resolve().parent.parent.parent / "data"

_PLANETS_IN_SIGNS: dict[str, dict[str, Any]] = {}
_PLANETS_IN_HOUSES: dict[str, dict[str, Any]] = {}
_HOUSE_CUSPS_IN_SIGNS: dict[str, dict[str, Any]] = {}
_ASPECTS: dict[str, dict[str, Any]] = {}
_REFERENCE: dict[str, dict[str, Any]] = {}


def _load_json(filename: str) -> dict[str, Any]:
    path = _DATA_DIR / filename
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        # Remove _meta key
        data.pop("_meta", None)
        return data
    except Exception:
        logger.exception("Failed to load %s", path)
        return {}


def _extract_lang(rec: dict[str, Any], lang: str = "en") -> dict[str, Any]:
    """Extract language-specific block from a bilingual record."""
    if "en" in rec and isinstance(rec["en"], dict):
        lang_block = rec.get(lang) or rec.get("en", {})
        return {
            "meaning": lang_block.get("meaning", ""),
            "keywords": lang_block.get("keywords", []),
        }
    return {
        "meaning": rec.get("meaning", ""),
        "keywords": rec.get("keywords", []),
    }


def _load_all() -> None:
    global _PLANETS_IN_SIGNS, _PLANETS_IN_HOUSES, _HOUSE_CUSPS_IN_SIGNS, _ASPECTS, _REFERENCE  # noqa: PLW0603

    raw = _load_json("natal_planets_in_signs.json")
    for key, rec in raw.items():
        _PLANETS_IN_SIGNS[key.lower()] = rec

    raw = _load_json("natal_planets_in_houses.json")
    for key, rec in raw.items():
        _PLANETS_IN_HOUSES[key.lower()] = rec

    raw = _load_json("natal_house_cusps_in_signs.json")
    for key, rec in raw.items():
        _HOUSE_CUSPS_IN_SIGNS[key.lower()] = rec

    raw = _load_json("natal_aspects.json")
    for key, rec in raw.items():
        _ASPECTS[key.lower()] = rec

    _REFERENCE.update(_load_json("natal_reference.json"))

    total = (
        len(_PLANETS_IN_SIGNS)
        + len(_PLANETS_IN_HOUSES)
        + len(_HOUSE_CUSPS_IN_SIGNS)
        + len(_ASPECTS)
    )
    logger.info("Loaded %d natal interpretation entries", total)


# Eager load on import
_load_all()


def get_planet_in_sign(planet: str, sign: str, lang: str = "en") -> dict[str, Any]:
    key = f"{planet}_in_{sign}".lower()
    rec = _PLANETS_IN_SIGNS.get(key)
    if rec:
        return _extract_lang(rec, lang)
    return {"meaning": "", "keywords": []}


def get_planet_in_house(planet: str, house: int, lang: str = "en") -> dict[str, Any]:
    key = f"{planet}_in_house_{house}".lower()
    rec = _PLANETS_IN_HOUSES.get(key)
    if rec:
        return _extract_lang(rec, lang)
    return {"meaning": "", "keywords": []}


def get_house_cusp_in_sign(house: int, sign: str, lang: str = "en") -> dict[str, Any]:
    key = f"house_{house}_in_{sign}".lower()
    rec = _HOUSE_CUSPS_IN_SIGNS.get(key)
    if rec:
        return _extract_lang(rec, lang)
    return {"meaning": "", "keywords": []}


def get_natal_aspect(
    p1: str, aspect: str, p2: str, lang: str = "en",
) -> dict[str, Any]:
    key = f"{p1}_{aspect}_{p2}".lower()
    rec = _ASPECTS.get(key)
    if rec:
        return _extract_lang(rec, lang)
    # Try reverse order (data is stored as Planet_aspect_SpecialBody)
    rev_key = f"{p2}_{aspect}_{p1}".lower()
    rec = _ASPECTS.get(rev_key)
    if rec:
        return _extract_lang(rec, lang)
    return {"meaning": "", "keywords": []}


def get_reference(
    category: str, key: str, lang: str = "en",
) -> dict[str, Any]:
    """Lookup from natal_reference.json.

    category: "houses" | "planets" | "signs"
    key: "house_1" | "Sun" | "Aries"
    """
    section = _REFERENCE.get(category, {})
    rec = section.get(key, {})
    if rec:
        return _extract_lang(rec, lang)
    return {"meaning": "", "keywords": []}
