#!/usr/bin/env python3
"""Seed 3 sample news posts into the database."""

import sys
import uuid
from datetime import date, datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import get_settings
from app.infrastructure.persistence.models import NewsPostModel
from app.infrastructure.persistence.session import database_is_enabled, session_scope


SEED_POSTS = [
    {
        "slug": "zendaya-wedding-transits-2026",
        "title": "Zendaya's Wedding Transits: Uranus Opposition MC and the Power of Timing",
        "subtitle": "Why the stars aligned for Hollywood's most talked-about wedding",
        "date": date(2026, 3, 15),
        "author": "Victoria",
        "status": "published",
        "intro": "When Zendaya and Tom Holland announced their engagement, the astrology community immediately pulled up her chart. And for good reason. Transit Uranus is making a rare opposition to her natal Midheaven, signaling massive public-facing life changes. This is not a quiet, private milestone. This is a transformation visible to the entire world.",
        "sections": [
            {
                "heading": "Uranus Opposition MC: The Big One",
                "body": "Transit Uranus at 2 degrees Gemini is opposing Zendaya's natal MC in Sagittarius. This is a once-in-a-lifetime aspect that shakes up everything about your public image and career trajectory. For someone already in the spotlight, this transit amplifies change to an almost cinematic level. Weddings, career pivots, relocation. Uranus opposite MC does not do small.",
            },
            {
                "heading": "Pluto Sextile Saturn: Ready to Build",
                "body": "Transit Pluto in early Aquarius is forming a sextile to her natal Saturn. This is the aspect of serious commitment backed by deep transformation. Saturn wants structure. Pluto wants evolution. Together, they say: this relationship is built to last, and both partners are willing to do the work.",
            },
            {
                "heading": "Jupiter Conjunct Venus: Expansion of Love",
                "body": "Perhaps the sweetest transit in her chart right now. Jupiter crossing over natal Venus is pure joy expansion in relationships. This is the universe saying yes. Combined with the Uranus-MC opposition, this wedding is not just a personal celebration. It is a cultural moment.",
            },
        ],
        "conclusion": "Zendaya's chart right now reads like a script Hollywood could not have written better. The timing is impeccable. Uranus brings the surprise, Pluto brings the depth, and Jupiter brings the celebration. If you want to understand how transits shape life's biggest moments, this is the textbook case.",
        "celebrity_name": "Zendaya",
        "celebrity_event": "Engagement and wedding planning",
        "meta_title": "Zendaya Wedding Transits 2026: Uranus Opposition MC Analysis | big3.me",
        "meta_description": "Astrology analysis of Zendaya's wedding transits. Uranus opposite MC, Pluto sextile Saturn, Jupiter conjunct Venus. Full chart breakdown.",
        "keywords": "zendaya,wedding,transits,uranus,opposition,mc,astrology,2026",
        "tags": "celebrity,transit",
        "published_at": datetime(2026, 3, 15, 9, 0, tzinfo=timezone.utc),
    },
    {
        "slug": "aries-season-2026-what-to-expect",
        "title": "Aries Season 2026: Fire, Forward Motion, and Fresh Starts",
        "subtitle": "The astrological new year begins March 20. Here is what the sky looks like.",
        "date": date(2026, 3, 20),
        "author": "Victoria",
        "status": "published",
        "intro": "Aries season marks the astrological new year. The Sun crosses 0 degrees Aries on March 20, 2026, and the energy shifts hard. After Pisces season's introspection and emotional processing, Aries season hits like a cold shower. Clarity. Direction. Action. No more waiting.",
        "sections": [
            {
                "heading": "The Ingress Chart: Mars in Leo",
                "body": "At the moment of the Aries ingress, Mars sits in Leo, forming a trine to the Sun. This is fire feeding fire. Mars in Leo is bold, dramatic, and refuses to play small. Combined with the Aries Sun, this season rewards those who step up and take initiative. Hesitation is the only real risk.",
            },
            {
                "heading": "Mercury in Aries: Think Fast, Speak Direct",
                "body": "Mercury enters Aries on March 27, joining the Sun. Communication speeds up. Meetings get shorter. Decisions that have been stuck for weeks suddenly resolve. The downside: Aries Mercury does not sugarcoat. Expect directness that borders on bluntness. If you have been avoiding a conversation, Aries season will not let you dodge it any longer.",
            },
            {
                "heading": "What This Means for Your Chart",
                "body": "Check which house Aries rules in your natal chart. That is where the fresh start energy lands. Aries on the 7th house? New relationship dynamics. Aries on the 10th? Career moves. The house placement tells you where to point the Aries energy for maximum impact.",
            },
        ],
        "conclusion": "Aries season 2026 is not subtle. Mars in Leo trine the Sun gives this entire month a confident, action-oriented charge. Use it. Set intentions. Start projects. Have the conversations. The sky is saying go.",
        "meta_title": "Aries Season 2026: Transit Guide and What to Expect | big3.me",
        "meta_description": "Complete guide to Aries season 2026. Mars in Leo, Mercury in Aries, and what it means for your chart. Astrology transit analysis.",
        "keywords": "aries season,2026,astrology,transits,mars,leo,mercury",
        "tags": "transit,educational",
        "published_at": datetime(2026, 3, 20, 9, 0, tzinfo=timezone.utc),
    },
    {
        "slug": "michael-b-jordan-oscar-transits",
        "title": "Michael B. Jordan's Oscar Nomination: Saturn Return and the Weight of Recognition",
        "subtitle": "His directing debut earned critical acclaim. His chart explains the timing.",
        "date": date(2026, 3, 10),
        "author": "Victoria",
        "status": "published",
        "intro": "Michael B. Jordan's directorial debut receiving an Oscar nomination surprised some critics but not astrologers. His chart has been building toward this moment for years. A Saturn return combined with Pluto aspecting his natal Sun creates the exact conditions for career-defining recognition. This is not luck. This is transits doing their job.",
        "sections": [
            {
                "heading": "Saturn Return in Pisces: The Test of Mastery",
                "body": "Saturn returning to its natal position is the most talked-about transit in astrology for good reason. It forces a reckoning. Are you living authentically? Have you done the work? For Michael B. Jordan, Saturn's return in Pisces challenges him to prove himself in a new creative arena. Directing is not acting. It requires a different kind of discipline, a different kind of vision. Saturn return says: show me what you have learned.",
            },
            {
                "heading": "Pluto Square Sun: Power Transformation",
                "body": "Transit Pluto forming a square to his natal Sun is intense. This is the aspect of power struggles, ego death, and eventual rebirth. A Pluto-Sun square during an Oscar campaign is almost poetic. The industry is testing him. The public is watching. And Pluto demands that he transform under pressure rather than break.",
            },
            {
                "heading": "North Node Conjunct Jupiter: Destined Growth",
                "body": "The transit North Node crossing his natal Jupiter suggests this recognition is not a detour. It is the path. Jupiter expands what it touches, and the North Node points toward destiny. This Oscar nomination is not the ceiling. It is the floor.",
            },
        ],
        "conclusion": "Michael B. Jordan's chart is a masterclass in how Saturn return energy, when met with discipline and vision, produces lasting results. The Oscar nomination is the headline. The transits are the story underneath. And this story is far from over.",
        "celebrity_name": "Michael B. Jordan",
        "celebrity_event": "Oscar nomination for directing debut",
        "meta_title": "Michael B. Jordan Oscar Transits: Saturn Return Analysis | big3.me",
        "meta_description": "Astrology analysis of Michael B. Jordan's Oscar nomination. Saturn return in Pisces, Pluto square Sun. Full transit breakdown.",
        "keywords": "michael b jordan,oscar,saturn return,pluto,transits,astrology",
        "tags": "celebrity,transit",
        "published_at": datetime(2026, 3, 10, 9, 0, tzinfo=timezone.utc),
    },
]


def main():
    settings = get_settings()
    if not database_is_enabled(settings):
        print("Database not enabled. Set ASTRO_CONSUL_PERSISTENCE_BACKEND=database")
        return

    now = datetime.now(timezone.utc)

    with session_scope(settings) as session:
        for post_data in SEED_POSTS:
            # Check if already exists
            from sqlalchemy import select
            existing = session.execute(
                select(NewsPostModel).where(NewsPostModel.slug == post_data["slug"])
            ).scalar_one_or_none()

            if existing:
                print(f"  SKIP (exists): {post_data['slug']}")
                continue

            sections_list = post_data.pop("sections")
            post = NewsPostModel(
                id=str(uuid.uuid4()),
                **post_data,
                sections=sections_list,
                created_at=now,
                updated_at=now,
            )
            session.add(post)
            print(f"  ADDED: {post_data['slug']}")

    print("Done. Visit /news to see the posts.")


if __name__ == "__main__":
    main()
