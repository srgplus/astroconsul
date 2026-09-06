#!/usr/bin/env python3
"""Seed 3 sample news posts into the database.

All transit claims verified against Swiss Ephemeris (pyswisseph) on 2026-03-23.
Natal positions computed at noon (houses/Moon approximate without verified birth time).
"""

import sys
import uuid
from datetime import UTC, date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import get_settings
from app.infrastructure.persistence.models import NewsPostModel
from app.infrastructure.persistence.session import database_is_enabled, session_scope

SEED_POSTS = [
    # ── Post 1: Zendaya ── verified against ephemeris for 2026-03-15
    # Transit Saturn 3°29' Aries conjunct her natal Saturn 5°49' Aries (orb ~2.3°)
    # Transit Pluto 4°53' Aquarius sextile natal Saturn 5°49' Aries (orb ~0.9°)
    # Transit Mercury Rx 9°56' Pisces opposite natal Sun 9°19' Virgo (orb ~0.6°)
    # Transit Mars 10°09' Pisces opposite natal Sun 9°19' Virgo (orb ~0.85°)
    # Transit Neptune 1°34' Aries approaching natal Saturn 5°49' Aries (orb ~4.2°)
    {
        "slug": "zendaya-wedding-transits-2026",
        "title": "Zendaya's Wedding Transits: Saturn Return and the Architecture of Commitment",
        "subtitle": "Her Saturn return in Aries coincides with one of Hollywood's biggest engagements",
        "date": date(2026, 3, 15),
        "author": "Victoria",
        "status": "published",
        "intro": (
            "When Zendaya and Tom Holland's engagement made headlines, astrologers immediately "
            "noticed the timing. Transit Saturn at 3 degrees Aries is closing in on her natal "
            "Saturn at 5 degrees Aries. She is entering her Saturn return. This is the transit "
            "that asks: are you ready to commit to who you actually are? For Zendaya, the "
            "answer appears to be a resounding yes."
        ),
        "sections": [
            {
                "heading": "Saturn Return in Aries: Building on Your Own Terms",
                "body": (
                    "Transit Saturn at 3 degrees Aries is approaching Zendaya's natal Saturn "
                    "at 5 degrees Aries, with the exact conjunction due in the coming weeks. "
                    "The Saturn return is the most talked-about milestone transit in astrology. "
                    "It arrives around age 29 and demands a reckoning with adulthood. In Aries, "
                    "this return is about identity, independence, and self-definition. It is not "
                    "enough to be talented. Saturn in Aries wants to know: who are you when no "
                    "one is directing the scene? An engagement during a Saturn return is one of "
                    "the most classically significant astrological timings for commitment."
                ),
            },
            {
                "heading": "Pluto Sextile Natal Saturn: Deep Structural Support",
                "body": (
                    "Transit Pluto at 4 degrees Aquarius is forming a near-exact sextile to "
                    "her natal Saturn at 5 degrees Aries, with an orb under one degree. This "
                    "is quiet but powerful. Pluto sextile Saturn is the aspect of transformation "
                    "that sticks. It is not dramatic upheaval. It is deep, irreversible evolution. "
                    "The structures she builds now, in relationships and career, have Pluto's "
                    "backing. They are meant to endure."
                ),
            },
            {
                "heading": "Mercury Retrograde and Mars Opposing Her Sun: The Inner Work",
                "body": (
                    "Transit Mercury retrograde at 9 degrees Pisces and transit Mars at 10 "
                    "degrees Pisces are both opposing her natal Sun at 9 degrees Virgo. This "
                    "is a double opposition with orbs under one degree. Mercury retrograde "
                    "opposite her Sun brings deep reflection about identity and self-expression. "
                    "Mars adds urgency. This is not a quiet engagement. There is an internal "
                    "intensity to this period, a push-pull between public perception and private "
                    "truth. The Pisces-Virgo axis asks her to balance the dream with the details."
                ),
            },
        ],
        "conclusion": (
            "Zendaya's chart in March 2026 is defined by her approaching Saturn return in "
            "Aries, reinforced by Pluto's sextile and sharpened by Mercury retrograde and "
            "Mars opposing her Sun. This is not a fairy tale engagement. It is a grown-up "
            "one. Saturn return commitments tend to be the ones that last, precisely because "
            "they are made with open eyes."
        ),
        "celebrity_name": "Zendaya",
        "celebrity_event": "Engagement and wedding planning",
        "meta_title": "Zendaya Wedding Transits 2026: Saturn Return Analysis | big3.me",
        "meta_description": (
            "Astrology analysis of Zendaya's engagement transits in March 2026. "
            "Saturn return in Aries, Pluto sextile Saturn, Mercury Rx opposite Sun. "
            "Full transit breakdown with verified ephemeris data."
        ),
        "keywords": "zendaya,wedding,transits,saturn return,aries,astrology,2026",
        "tags": "celebrity,transit",
        "published_at": datetime(2026, 3, 15, 9, 0, tzinfo=UTC),
    },
    # ── Post 2: Aries Season ── verified against ephemeris for 2026-03-20
    # Sun 29°53' Pisces (ingress to Aries within hours)
    # Mars 14°05' Pisces trine Jupiter 15°13' Cancer (orb 1.13°)
    # Mercury Rx 8°29' Pisces (stationing direct ~Mar 27)
    # Saturn 4°06' Aries conjunct Neptune 1°46' Aries (orb 2.34°)
    # Venus 17°26' Aries conjunct Moon 18°51' Aries (orb 1.42°)
    # Saturn sextile Pluto 5°00' Aquarius (orb 0.89°)
    {
        "slug": "aries-season-2026-what-to-expect",
        "title": "Aries Season 2026: Saturn Meets Neptune and Mercury Stations Direct",
        "subtitle": "The astrological new year begins March 20 with a rare Saturn-Neptune conjunction in Aries.",
        "date": date(2026, 3, 20),
        "author": "Victoria",
        "status": "published",
        "intro": (
            "Aries season marks the astrological new year. The Sun reaches 29 degrees 53 "
            "minutes of Pisces on March 20 and crosses into Aries within hours. But this "
            "year the ingress is overshadowed by something bigger: Saturn and Neptune are "
            "conjunct in early Aries, Mercury is stationing direct after weeks of retrograde "
            "in Pisces, and Mars in Pisces is forming a water trine to Jupiter in Cancer. "
            "This is not a simple fresh start. It is a recalibration."
        ),
        "sections": [
            {
                "heading": "Saturn Conjunct Neptune in Aries: The Generational Shift",
                "body": (
                    "The headline transit of spring 2026 is Saturn at 4 degrees Aries conjunct "
                    "Neptune at 1 degree Aries, with an orb of about 2.3 degrees. This is a "
                    "generational aspect. Saturn and Neptune meet roughly every 36 years, and "
                    "their conjunction in Aries has not happened since the 1700s. Saturn brings "
                    "structure, limits, and reality. Neptune dissolves, dreams, and transcends. "
                    "In Aries, the sign of new beginnings, this conjunction is rewriting the "
                    "rules of what is possible. Expect new cultural movements, shifts in how "
                    "institutions operate, and a collective renegotiation of idealism versus "
                    "pragmatism. This is also sextile Pluto at 5 degrees Aquarius with an orb "
                    "under one degree, adding transformative power to the restructuring."
                ),
            },
            {
                "heading": "Mercury Stations Direct in Pisces: Clarity After the Fog",
                "body": (
                    "Mercury has been retrograde in Pisces since early March. On March 20, it "
                    "sits at 8 degrees Pisces with a speed near zero, essentially stationary. "
                    "By late March it turns direct and begins picking up speed. Mercury retrograde "
                    "in Pisces is one of the more disorienting retrogrades. Communication goes "
                    "nonlinear, details slip, intuition overrides logic. As it stations direct "
                    "during the Aries ingress, expect a wave of clarity. Decisions delayed since "
                    "early March suddenly resolve. But give it a few days. The station itself is "
                    "the muddiest point."
                ),
            },
            {
                "heading": "Mars in Pisces Trine Jupiter in Cancer: Water Fuels the Fire",
                "body": (
                    "Mars at 14 degrees Pisces is forming a trine to Jupiter at 15 degrees "
                    "Cancer with an orb of just 1.1 degrees. This is not Aries-season fire. "
                    "This is a water trine: intuitive, emotionally intelligent, creatively "
                    "fertile. Mars in Pisces acts through compassion and imagination rather "
                    "than force. Jupiter in Cancer expands emotional security and nurturing "
                    "instincts. Together, they support projects rooted in empathy, art, "
                    "caregiving, and spiritual practice. If you have planets in water signs, "
                    "this trine hits your chart directly."
                ),
            },
        ],
        "conclusion": (
            "Aries season 2026 opens with rare energy. The Saturn-Neptune conjunction in "
            "Aries redefines the backdrop of the entire year. Mercury stationing direct "
            "clears the mental fog. And Mars trine Jupiter in water signs provides the "
            "emotional fuel to act on new insights. Check which house early Aries rules "
            "in your natal chart. That is where the restructuring lands hardest."
        ),
        "meta_title": "Aries Season 2026: Saturn-Neptune Conjunction and Transit Guide | big3.me",
        "meta_description": (
            "Complete guide to Aries season 2026. Saturn conjunct Neptune in Aries, "
            "Mercury stations direct, Mars trine Jupiter. Verified transit analysis."
        ),
        "keywords": "aries season,2026,astrology,saturn,neptune,conjunction,mercury retrograde,transits",
        "tags": "transit,educational",
        "published_at": datetime(2026, 3, 20, 9, 0, tzinfo=UTC),
    },
    # ── Post 3: Michael B. Jordan ── verified against ephemeris for 2026-03-10
    # His natal: Sun 20°11' Aquarius, Mercury 7°58' Pisces, Moon ~2° Cancer,
    #   Mars 22°18' Aries, Jupiter 25°07' Pisces, Saturn 19°10' Sag,
    #   Neptune 7°03' Cap, North Node 13°06' Aries
    # Transit North Node 8°53' Pisces conjunct natal Mercury 7°58' Pisces (orb 0.92°)
    # Transit Mars 6°13' Pisces conjunct natal Mercury 7°58' Pisces (orb 1.74°)
    # Transit Neptune 1°23' Aries square natal Moon ~2° Cancer (orb ~0.6°)
    # Transit Saturn 2°52' Aries square natal Moon ~2° Cancer (orb ~0.9°)
    # Transit Mercury Rx 13°50' Pisces conjunct natal North Node 13°06' Aries? No, NN is Aries
    # Actually transit Mercury Rx (343.84°) near natal Mercury (337.97°) → orb 5.87° (wide)
    {
        "slug": "michael-b-jordan-oscar-transits",
        "title": "Michael B. Jordan's Oscar Nomination: North Node on Mercury and the Voice of a Director",
        "subtitle": "His directorial debut earned critical acclaim. The transits show why the timing was fated.",
        "date": date(2026, 3, 10),
        "author": "Victoria",
        "status": "published",
        "intro": (
            "Michael B. Jordan's directorial debut receiving an Oscar nomination surprised "
            "some critics but not astrologers. In March 2026, the transit North Node at 8 "
            "degrees Pisces is sitting almost exactly on his natal Mercury at 7 degrees "
            "Pisces. The North Node on Mercury is one of the clearest signatures of fated "
            "communication: a message the world was meant to hear. For a first-time "
            "director, this is the transit of finding your voice."
        ),
        "sections": [
            {
                "heading": "North Node Conjunct Natal Mercury: A Destined Message",
                "body": (
                    "The transit North Node at 8 degrees 53 minutes Pisces is conjunct his "
                    "natal Mercury at 7 degrees 58 minutes Pisces, with an orb under one "
                    "degree. The North Node represents destiny, karmic direction, what you "
                    "are growing toward. Mercury is voice, vision, storytelling. When the "
                    "North Node crosses your Mercury, the universe amplifies your message. "
                    "For Michael B. Jordan, that message took the form of a film. The "
                    "nomination is not a surprise in this light. It is the North Node "
                    "saying: this is what you were meant to communicate."
                ),
            },
            {
                "heading": "Mars Conjunct Natal Mercury: Action Meets Expression",
                "body": (
                    "Transit Mars at 6 degrees Pisces is also conjunct his natal Mercury "
                    "at 7 degrees Pisces, with an orb of 1.7 degrees. Mars energizes "
                    "whatever it touches. On Mercury, it makes communication forceful, "
                    "direct, and impossible to ignore. Mars conjunct Mercury in Pisces "
                    "channels that force through emotion and intuition rather than "
                    "aggression. This is the aspect of a director who leads with empathy "
                    "but does not hesitate to make bold choices. Combined with the North "
                    "Node conjunction, this is a rare double activation of his natal "
                    "Mercury. His creative voice is operating at full power."
                ),
            },
            {
                "heading": "Saturn and Neptune Square Moon: Emotional Pressure as Fuel",
                "body": (
                    "Transit Saturn at 2 degrees Aries and transit Neptune at 1 degree "
                    "Aries are both forming squares to his natal Moon at approximately 2 "
                    "degrees Cancer. Saturn square Moon is emotional discipline, "
                    "responsibility, and the weight of public expectation. Neptune square "
                    "Moon dissolves emotional defenses and heightens sensitivity. Together, "
                    "these squares create intense inner pressure. For an artist, this kind "
                    "of pressure is raw material. Saturn provides the structure. Neptune "
                    "provides the vision. The Moon channels it into something audiences feel."
                ),
            },
        ],
        "conclusion": (
            "Michael B. Jordan's transits in March 2026 tell a clear story. The North Node "
            "and Mars converging on his natal Mercury activated his directorial voice at "
            "exactly the right moment. Saturn and Neptune squaring his Moon provided the "
            "emotional intensity that makes art resonate. This Oscar nomination is not a "
            "peak. It is a beginning. The North Node does not point backward."
        ),
        "celebrity_name": "Michael B. Jordan",
        "celebrity_event": "Oscar nomination for directing debut",
        "meta_title": "Michael B. Jordan Oscar Transits: North Node on Mercury Analysis | big3.me",
        "meta_description": (
            "Astrology analysis of Michael B. Jordan's Oscar nomination. North Node "
            "conjunct Mercury, Mars conjunct Mercury, Saturn-Neptune square Moon. "
            "Verified transit data from Swiss Ephemeris."
        ),
        "keywords": "michael b jordan,oscar,north node,mercury,transits,astrology,2026",
        "tags": "celebrity,transit",
        "published_at": datetime(2026, 3, 10, 9, 0, tzinfo=UTC),
    },
]


def main():
    settings = get_settings()
    if not database_is_enabled(settings):
        print("Database not enabled. Set ASTRO_CONSUL_PERSISTENCE_BACKEND=database")
        return

    now = datetime.now(UTC)

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
