"""Synastry aspect descriptions lookup.

Loads synastry_aspects.json once at import time into a dict keyed by
``"{planet_a}_{aspect_type}_{planet_b}"`` (all lowercase).

Usage::

    from app.data.synastry_aspects_lookup import get_synastry_description

    desc = get_synastry_description("Venus", "opposition", "Moon")
    # {"meaning": "...", "keywords": [...]}

    desc_ru = get_synastry_description("Venus", "opposition", "Moon", lang="ru")
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

_DATA_PATH = Path(__file__).with_name("synastry_aspects.json")

_LOOKUP: dict[str, dict[str, Any]] = {}


def _build_key(planet_a: str, aspect: str, planet_b: str) -> str:
    return f"{planet_a}_{aspect}_{planet_b}".lower()


def _extract_lang(rec: dict[str, Any], lang: str = "en") -> dict[str, Any]:
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


def _load() -> None:
    global _LOOKUP  # noqa: PLW0603
    _LOOKUP.clear()
    try:
        data = json.loads(_DATA_PATH.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            for composite_key, rec in data.items():
                _LOOKUP[composite_key.lower()] = rec
        logger.info("Loaded %d synastry aspect descriptions", len(_LOOKUP))
    except Exception:
        logger.exception("Failed to load synastry aspect descriptions from %s", _DATA_PATH)


_load()


def get_synastry_description(
    planet_a: str,
    aspect_type: str,
    planet_b: str,
    lang: str = "en",
) -> dict[str, Any]:
    """Return meaning/keywords for a synastry aspect, with fallback."""
    key = _build_key(planet_a, aspect_type, planet_b)
    if key in _LOOKUP:
        return _extract_lang(_LOOKUP[key], lang)

    # Try reversed order (Sun_trine_Moon == Moon_trine_Sun in synastry)
    reverse_key = _build_key(planet_b, aspect_type, planet_a)
    if reverse_key in _LOOKUP:
        return _extract_lang(_LOOKUP[reverse_key], lang)

    # Fallback
    if lang == "ru":
        return {
            "meaning": f"{planet_a} {aspect_type} {planet_b} — значимый аспект между картами.",
            "keywords": [],
        }
    return {
        "meaning": f"{planet_a} {aspect_type} {planet_b} — a significant inter-chart aspect.",
        "keywords": [],
    }
