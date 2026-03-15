"""Transit aspect descriptions lookup.

Loads transit_aspects.json once at import time into a dict keyed by
``"{transit_planet}_{aspect_type}_{natal_point}"`` (all lowercase).

Supports both flat format and i18n format (``{"en": {...}, "ru": {...}}``).

Usage::

    from app.data.transit_aspects_lookup import get_aspect_description

    desc = get_aspect_description("Sun", "conjunction", "Moon")
    # {"meaning": "...", "action": "...", "keywords": [...]}

    desc_ru = get_aspect_description("Sun", "conjunction", "Moon", lang="ru")
    # {"meaning": "...(Russian)...", "action": "...", "keywords": [...]}
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

_DATA_PATH = Path(__file__).with_name("transit_aspects.json")

_LOOKUP: dict[str, dict[str, Any]] = {}


def _build_key(transit: str, aspect: str, natal: str) -> str:
    return f"{transit}_{aspect}_{natal}".lower()


def _extract_lang(rec: dict[str, Any], lang: str = "en") -> dict[str, Any]:
    """Extract a language-specific block from a record.

    Handles both i18n format (``{"en": {...}, "ru": {...}}``) and
    flat format (``{"meaning": ..., "action": ..., "keywords": [...]}``).
    Falls back to ``"en"`` if the requested language is not available.
    """
    if "en" in rec and isinstance(rec["en"], dict):
        # i18n format
        lang_block = rec.get(lang) or rec.get("en", {})
        return {
            "meaning": lang_block.get("meaning", ""),
            "action": lang_block.get("action"),
            "keywords": lang_block.get("keywords", []),
        }
    # Flat format (legacy)
    return {
        "meaning": rec.get("meaning", ""),
        "action": rec.get("action"),
        "keywords": rec.get("keywords", []),
    }


def _load() -> None:
    global _LOOKUP  # noqa: PLW0603
    _LOOKUP.clear()
    try:
        data = json.loads(_DATA_PATH.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            # Compact format: {"Sun_conjunction_Sun": {...}, ...}
            for composite_key, rec in data.items():
                _LOOKUP[composite_key.lower()] = rec
        elif isinstance(data, list):
            # Legacy list format: [{transit_planet, aspect_type, natal_point, ...}, ...]
            for rec in data:
                key = _build_key(rec["transit_planet"], rec["aspect_type"], rec["natal_point"])
                _LOOKUP[key] = rec
        logger.info("Loaded %d transit aspect descriptions", len(_LOOKUP))
    except Exception:
        logger.exception("Failed to load transit aspect descriptions from %s", _DATA_PATH)


# Eager load on import
_load()


def get_aspect_description(
    transit_planet: str,
    aspect_type: str,
    natal_point: str,
    lang: str = "en",
) -> dict[str, Any]:
    """Return meaning/action/keywords for an aspect, with fallback.

    Parameters
    ----------
    transit_planet : str
        Name of the transiting planet (e.g. "Sun").
    aspect_type : str
        Aspect name (e.g. "conjunction").
    natal_point : str
        Natal chart point (e.g. "Moon", "ASC", "MC").
    lang : str
        Language code — ``"en"`` (default) or ``"ru"``.
    """
    key = _build_key(transit_planet, aspect_type, natal_point)
    if key in _LOOKUP:
        return _extract_lang(_LOOKUP[key], lang)
    # Fallback
    if lang == "ru":
        return {
            "meaning": f"{transit_planet} {aspect_type} {natal_point}. Обрати внимание на эту область.",
            "action": None,
            "keywords": [],
        }
    return {
        "meaning": f"{transit_planet} {aspect_type} {natal_point}. Pay attention to this area.",
        "action": None,
        "keywords": [],
    }
