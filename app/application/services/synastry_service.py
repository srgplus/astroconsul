"""Synastry report service — computes inter-chart compatibility."""

from __future__ import annotations

import logging
from typing import Any

from app.data.synastry_aspects_lookup import get_synastry_description
from synastry_engine import (
    _score_label_ru,
    compute_synastry_aspects,
    compute_synastry_scores,
)

logger = logging.getLogger(__name__)


class SynastryService:
    def build_report(
        self,
        profile_a_id: str,
        profile_b_id: str,
        *,
        lang: str = "en",
        profile_repository: Any,
        chart_repository: Any,
    ) -> dict[str, Any]:
        """Build a full synastry report between two profiles."""
        # Load both profiles
        profile_a = profile_repository.load_profile(profile_a_id)
        profile_b = profile_repository.load_profile(profile_b_id)

        # Load charts (load_chart returns (reference, chart_dict) tuple)
        _, chart_a = chart_repository.load_chart(profile_a["chart_id"])
        _, chart_b = chart_repository.load_chart(profile_b["chart_id"])

        # Extract positions
        a_positions = chart_a.get("natal_positions", [])
        b_positions = chart_b.get("natal_positions", [])
        b_angles = {
            "asc": chart_b.get("asc"),
            "mc": chart_b.get("mc"),
        }
        # Clean None values from angles
        b_angles = {k: v for k, v in b_angles.items() if v is not None}

        # Also add A's angles as positions for cross-comparison
        a_angles = {
            "asc": chart_a.get("asc"),
            "mc": chart_a.get("mc"),
        }
        a_angles = {k: v for k, v in a_angles.items() if v is not None}

        # Compute aspects both ways and merge (A→B and B→A with A's angles)
        aspects_a_to_b = compute_synastry_aspects(a_positions, b_positions, b_angles)

        # Enrich with interpretations
        for asp in aspects_a_to_b:
            desc = get_synastry_description(
                asp["person_a_object"],
                asp["aspect"],
                asp["person_b_object"],
                lang=lang,
            )
            asp["meaning"] = desc["meaning"]
            asp["keywords"] = desc["keywords"]

        # Compute scores
        scores = compute_synastry_scores(aspects_a_to_b)

        # Localize label
        if lang == "ru":
            scores["overall_label"] = _score_label_ru(scores["overall"])

        # Count exact/strong
        exact_count = sum(1 for a in aspects_a_to_b if a["strength"] == "exact")
        strong_count = sum(1 for a in aspects_a_to_b if a["strength"] in ("exact", "strong"))

        # Build person summaries
        person_a = _person_summary(profile_a, chart_a)
        person_b = _person_summary(profile_b, chart_b)

        # Overall reading
        overall_reading = _generate_overall_reading(aspects_a_to_b, scores, lang)

        # Lightweight positions for display in aspect cards
        def _slim_positions(positions: list[dict]) -> list[dict]:
            return [
                {
                    "id": p["id"],
                    "sign": p.get("sign", ""),
                    "degree": p.get("degree", 0),
                    "minute": p.get("minute", 0),
                    "house": p.get("house"),
                    "retrograde": p.get("retrograde", False),
                }
                for p in positions
            ]

        return {
            "person_a": person_a,
            "person_b": person_b,
            "scores": scores,
            "aspects": aspects_a_to_b,
            "aspect_count": len(aspects_a_to_b),
            "exact_count": exact_count,
            "strong_count": strong_count,
            "overall_reading": overall_reading,
            "positions_a": _slim_positions(a_positions),
            "positions_b": _slim_positions(b_positions),
        }


def _person_summary(profile: dict, chart: dict) -> dict:
    """Build a summary dict for a person in synastry."""
    return {
        "name": profile.get("display_name") or profile.get("handle", ""),
        "handle": profile.get("handle", ""),
        "profile_id": profile.get("id", ""),
        "natal_summary": chart.get("natal_summary"),
    }


def _generate_overall_reading(
    aspects: list[dict], scores: dict, lang: str
) -> str:
    """Generate a template-based overall synastry reading."""
    overall = scores["overall"]
    top_aspects = [a for a in aspects if a["strength"] in ("exact", "strong")][:5]

    if lang == "ru":
        return _reading_ru(overall, scores, top_aspects)
    return _reading_en(overall, scores, top_aspects)


def _reading_en(overall: int, scores: dict, top_aspects: list[dict]) -> str:
    parts: list[str] = []

    # Opening based on overall score
    if overall >= 86:
        parts.append(
            "This is a deeply resonant connection — the kind that feels instantly familiar. "
            "The charts align with rare precision, suggesting a bond that transcends the ordinary."
        )
    elif overall >= 71:
        parts.append(
            "This is a magnetic synastry with strong emotional, mental, and physical connections. "
            "The attraction is real and multi-layered — this relationship has depth."
        )
    elif overall >= 51:
        parts.append(
            "This is a harmonious connection with genuine compatibility across key areas. "
            "There's enough resonance to build something real, with manageable friction."
        )
    elif overall >= 31:
        parts.append(
            "This is a complex synastry with both strong attraction and real challenges. "
            "The connection is intense but requires awareness and effort from both sides."
        )
    else:
        parts.append(
            "This is a challenging synastry that demands significant adaptation. "
            "The connection exists but manifests through tension and growth rather than ease."
        )

    # Category highlights
    highlights: list[str] = []
    if scores["emotional"] >= 75:
        highlights.append("emotional depth")
    if scores["mental"] >= 75:
        highlights.append("intellectual connection")
    if scores["physical"] >= 75:
        highlights.append("physical chemistry")
    if scores["karmic"] >= 75:
        highlights.append("karmic significance")
    if highlights:
        parts.append(
            f"Particularly strong in: {', '.join(highlights)}."
        )

    # Key aspects
    if top_aspects:
        aspect_names = [
            f"{a['person_a_object']} {a['aspect']} {a['person_b_object']}"
            for a in top_aspects[:3]
        ]
        parts.append(
            f"Key aspects driving this connection: {'; '.join(aspect_names)}."
        )

    return " ".join(parts)


def _reading_ru(overall: int, scores: dict, top_aspects: list[dict]) -> str:
    parts: list[str] = []

    if overall >= 86:
        parts.append(
            "Это глубоко резонирующая связь — из тех, что сразу ощущается как знакомая. "
            "Карты совпадают с редкой точностью, предполагая связь за пределами обычного."
        )
    elif overall >= 71:
        parts.append(
            "Это магнетическая синастрия с сильными эмоциональными, ментальными и физическими связями. "
            "Притяжение реальное и многослойное — в этих отношениях есть глубина."
        )
    elif overall >= 51:
        parts.append(
            "Это гармоничная связь с настоящей совместимостью в ключевых областях. "
            "Достаточно резонанса, чтобы построить что-то настоящее, с управляемым трением."
        )
    elif overall >= 31:
        parts.append(
            "Это сложная синастрия с сильным притяжением и реальными вызовами. "
            "Связь интенсивна, но требует осознанности и усилий с обеих сторон."
        )
    else:
        parts.append(
            "Это непростая синастрия, требующая значительной адаптации. "
            "Связь проявляется через напряжение и рост, а не через лёгкость."
        )

    highlights: list[str] = []
    if scores["emotional"] >= 75:
        highlights.append("эмоциональная глубина")
    if scores["mental"] >= 75:
        highlights.append("интеллектуальная связь")
    if scores["physical"] >= 75:
        highlights.append("физическая химия")
    if scores["karmic"] >= 75:
        highlights.append("кармическое значение")
    if highlights:
        parts.append(f"Особенно сильно: {', '.join(highlights)}.")

    if top_aspects:
        aspect_names = [
            f"{a['person_a_object']} {a['aspect']} {a['person_b_object']}"
            for a in top_aspects[:3]
        ]
        parts.append(f"Ключевые аспекты: {'; '.join(aspect_names)}.")

    return " ".join(parts)
