"""Add daily cosmic weather post: Venus at 29 Aries — March 30, 2026

Revision ID: 20260330_000001
Revises: 20260327_000001
Create Date: 2026-03-30
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import json
import uuid
from datetime import date, datetime, timezone

revision: str = "20260330_000001"
down_revision: str = "20260327_000001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SLUG = "cosmic-weather-venus-anaretic-aries-march-30-2026"


def upgrade() -> None:
    conn = op.get_bind()

    # Check for existing post with this slug
    result = conn.execute(
        sa.text("SELECT id FROM news_posts WHERE slug = :slug"),
        {"slug": SLUG},
    )
    if result.fetchone():
        return  # Already exists, skip

    now = datetime.now(timezone.utc).isoformat()
    post_id = str(uuid.uuid4())

    sections = [
        {
            "heading": "Venus at 29\u00b047' Aries: The Anaretic Degree",
            "body_html": (
                "<p><strong>Venus at 29\u00b047' Aries</strong> \u2014 moving at 1.23\u00b0/day, "
                "she'll cross into Taurus within hours. The 29th degree of any sign "
                "is called the <em>anaretic degree</em> \u2014 a point of culmination, urgency, "
                "and unfinished business.</p>"
                "<p>Venus has been in Aries since early March \u2014 in the sign of her detriment, "
                "where love is impulsive, desire is impatient, and self-worth gets tangled "
                "with conquest. Aries Venus doesn't wait to be chosen. She chooses. "
                "The problem is she sometimes chooses before she knows what she actually wants.</p>"
                "<p>At 29\u00b0, that energy reaches its peak. The anaretic degree carries the weight "
                "of everything this Venus-in-Aries transit stirred up:</p>"
                "<ul>"
                "<li><strong>Relationships tested by independence</strong> \u2014 did wanting space "
                "become creating distance?</li>"
                "<li><strong>Desires that burned fast</strong> \u2014 what you chased in early March "
                "may look different now</li>"
                "<li><strong>Self-worth tied to action</strong> \u2014 Aries Venus proves her value "
                "by doing, not being. That's exhausting.</li>"
                "</ul>"
                "<p>Tomorrow, Venus enters Taurus \u2014 her home sign \u2014 and the energy shifts "
                "completely. Taurus Venus builds slowly, savors, commits. She values comfort "
                "over excitement, loyalty over novelty. The transition is like exhaling "
                "after holding your breath for a month.</p>"
                "<p><strong>Today's task:</strong> notice what Venus in Aries started that needs "
                "to be completed or released before the sign change. A conversation, a decision "
                "about what you value, a pattern you've been repeating. "
                "The 29th degree says: <em>finish it now, or carry it forward unresolved.</em></p>"
                "<p><strong>Who feels this most:</strong> anyone with natal planets at 27\u00b0\u201302\u00b0 "
                "of fixed signs (Taurus, Leo, Scorpio, Aquarius) \u2014 you're about to feel "
                "Venus arrive. Check your chart at <a href='https://big3.me'>big3.me</a>.</p>"
            ),
        },
        {
            "heading": "Saturn Sextile Pluto: Day Six at 0.17\u00b0",
            "body_html": (
                "<p><strong>Saturn at 5\u00b021' Aries</strong> sextile <strong>Pluto at 5\u00b011' Aquarius</strong> \u2014 "
                "orb 0.17\u00b0. This has been the tightest major aspect in the sky for nearly a week, "
                "and it's barely moved.</p>"
                "<p>Saturn-Pluto aspects are generational markers. The last conjunction (2020) "
                "restructured the world. The current sextile is the constructive follow-up: "
                "it doesn't tear down, it rebuilds with awareness of what collapsed.</p>"
                "<p>At 5\u00b0 Aries/Aquarius, this sextile connects:</p>"
                "<ul>"
                "<li><strong>Saturn in Aries</strong> \u2014 new structures, pioneering discipline, "
                "taking responsibility for what you initiate</li>"
                "<li><strong>Pluto in Aquarius</strong> \u2014 deep transformation in systems, technology, "
                "collective power, decentralized authority</li>"
                "</ul>"
                "<p>The sextile is an <em>opportunity</em> aspect \u2014 it doesn't force change, "
                "it makes change available. The people leveraging this transit are the ones "
                "building new systems: restructuring businesses, committing to long-term goals, "
                "doing the difficult foundational work that won't pay off for months but will pay off "
                "for years.</p>"
                "<p>Saturn also remains within orb of Neptune (3.21\u00b0 conjunction in Aries) \u2014 "
                "the dreams-meet-discipline signature that defines 2026. "
                "The sextile to Pluto adds power to that vision. This isn't just dreaming. "
                "It's building something that transforms.</p>"
            ),
        },
        {
            "heading": "Mercury Trine Jupiter: The Conversation That Expands",
            "body_html": (
                "<p><strong>Mercury at 12\u00b029' Pisces</strong> trine <strong>Jupiter at 15\u00b041' Cancer</strong> \u2014 "
                "orb 3.19\u00b0, applying. Both in water signs, both leaning into intuition over logic.</p>"
                "<p>Mercury-Jupiter trines are the sky's best aspect for communication. "
                "Ideas flow bigger, conversations go deeper, and the thing you've been trying "
                "to articulate suddenly finds its words. In water signs, this isn't intellectual "
                "brilliance \u2014 it's emotional intelligence.</p>"
                "<p>Mercury in Pisces thinks in images, metaphors, feelings. "
                "Jupiter in Cancer amplifies through nurturing, memory, and belonging. "
                "Together they favor:</p>"
                "<ul>"
                "<li><strong>Meaningful conversations</strong> \u2014 the kind where you say something "
                "you didn't know you felt until you heard yourself say it</li>"
                "<li><strong>Creative writing or storytelling</strong> \u2014 water-sign Mercury-Jupiter "
                "has a gift for narrative that moves people</li>"
                "<li><strong>Decisions guided by gut feeling</strong> \u2014 your intuition is sharper "
                "than your spreadsheet today</li>"
                "<li><strong>Teaching and learning</strong> \u2014 Jupiter expands Mercury's reach; "
                "ideas land in hearts, not just heads</li>"
                "</ul>"
                "<p>The Moon in Virgo opposes Mercury (3.46\u00b0), adding a note of practical scrutiny. "
                "Virgo Moon says: <em>the feeling is real, but check the details before you commit.</em> "
                "Good advice \u2014 Mercury in Pisces can promise more than it can deliver.</p>"
            ),
        },
        {
            "heading": "Waxing Gibbous Moon in Virgo: Refine Before the Full Moon",
            "body_html": (
                "<p><strong>Moon at 9\u00b002' Virgo</strong> \u2014 waxing gibbous phase (149\u00b0 from the Sun). "
                "The Full Moon is approaching in a few days, and the gibbous phase is about "
                "refinement, adjustment, and attention to what's not quite right.</p>"
                "<p>Virgo Moon is the sky's quality control. She notices the gap between "
                "intention and execution. Paired with today's Venus anaretic degree, "
                "there's a useful synergy: Venus says <em>finish what you started</em>, "
                "and the Virgo Moon says <em>finish it properly.</em></p>"
                "<p>The Moon also opposes Mercury in Pisces (3.46\u00b0), creating a polarity "
                "between Virgo's precision and Pisces' flow:</p>"
                "<ul>"
                "<li><strong>Morning:</strong> Virgo Moon energy is high \u2014 good for organizing, "
                "editing, cleaning, health routines, practical tasks</li>"
                "<li><strong>Afternoon/evening:</strong> Mercury-Jupiter trine pulls you toward "
                "bigger thinking \u2014 let the details fuel the vision, not replace it</li>"
                "</ul>"
                "<p>The gibbous phase asks: <em>what adjustments do I need to make before "
                "this cycle peaks?</em> With the Full Moon coming in Libra (relationship axis), "
                "the adjustments are likely about how you show up for other people \u2014 "
                "and whether the balance is working.</p>"
            ),
        },
        {
            "heading": "How to Work With Today's Sky",
            "body_html": (
                "<p>March 30 is a threshold day. Venus stands at the edge between two signs, "
                "two modes of loving, two definitions of value. Saturn-Pluto holds the structural "
                "foundation. Mercury-Jupiter opens the conversation. The Virgo Moon sharpens the details.</p>"
                "<p><strong>Best for:</strong></p>"
                "<ul>"
                "<li>Finishing what Venus in Aries started \u2014 the relationship talk, the bold move, "
                "the thing you wanted but didn't commit to</li>"
                "<li>Financial and value decisions \u2014 Venus changes how you relate to money, beauty, "
                "and pleasure when she changes signs</li>"
                "<li>Writing, journaling, or any creative expression that needs emotional depth "
                "(Mercury trine Jupiter)</li>"
                "<li>Organizing and refining plans before the Full Moon (Virgo Moon)</li>"
                "<li>Long-term structural commitments \u2014 Saturn-Pluto sextile rewards foundations "
                "built today</li>"
                "</ul>"
                "<p><strong>Watch out for:</strong></p>"
                "<ul>"
                "<li>Anaretic degree restlessness \u2014 the urge to force a decision before you're ready. "
                "Venus at 29\u00b0 creates urgency, but not everything needs to be resolved today</li>"
                "<li>Over-promising \u2014 Mercury in Pisces trine Jupiter can make everything feel possible. "
                "The Virgo Moon is your reality check</li>"
                "<li>Perfectionism paralysis \u2014 Virgo Moon can over-edit. At some point, "
                "done is better than perfect</li>"
                "</ul>"
                "<p>All planets remain direct. The energy is forward-moving and purposeful. "
                "Track how these transits hit your personal chart at "
                "<a href='https://big3.me'>big3.me</a> \u2014 especially if you have natal placements "
                "near 29\u00b0 Aries/0\u00b0 Taurus or 5\u00b0 Aries/Aquarius.</p>"
            ),
        },
    ]

    conn.execute(
        sa.text("""
            INSERT INTO news_posts (id, slug, title, subtitle, date, author, status, intro, sections, conclusion, tags, keywords, meta_title, meta_description, published_at, created_at, updated_at)
            VALUES (:id, :slug, :title, :subtitle, :date, :author, :status, :intro, :sections, :conclusion, :tags, :keywords, :meta_title, :meta_description, :published_at, :created_at, :updated_at)
        """),
        {
            "id": post_id,
            "slug": SLUG,
            "title": "Venus at 29\u00b0 Aries: The Last Degree Before Home",
            "subtitle": "Venus spends her final hours in Aries \u2014 the sign of her discomfort \u2014 before crossing into Taurus, where she rules. Saturn sextile Pluto holds exact at 0.17\u00b0.",
            "date": "2026-03-30",
            "author": "Victoria",
            "status": "published",
            "intro": (
                "Venus sits at 29\u00b047' Aries \u2014 the anaretic degree, "
                "the most urgent point in any sign. Tomorrow she enters Taurus, "
                "the sign she rules, where love stops fighting and starts building. "
                "But today she's still in Aries, and the 29th degree demands you finish something "
                "before the door closes. Meanwhile, Saturn sextile Pluto holds at a razor-thin 0.17\u00b0 orb "
                "for the sixth consecutive day, quietly restructuring foundations. "
                "The Waxing Gibbous Moon in Virgo sharpens your eye for what needs fixing."
            ),
            "sections": json.dumps(sections, ensure_ascii=False),
            "conclusion": (
                "Today the sky is in transition \u2014 and so might you be. "
                "Venus at 29\u00b047' Aries is living her last hours in the sign that pushed her "
                "to want things loudly. Tomorrow in Taurus, she'll want them quietly and deeply. "
                "Saturn sextile Pluto at 0.17\u00b0 keeps building the invisible architecture "
                "beneath everything. Mercury trine Jupiter says the words will come "
                "if you trust what you feel before you analyze it. "
                "The Virgo Moon asks only that you pay attention to the details that matter. "
                "No retrogrades. No resistance. Just Venus at the threshold, asking: "
                "what do you actually value \u2014 and are you ready to commit to it?"
            ),
            "tags": "transit,daily",
            "keywords": "venus anaretic degree,venus 29 aries,venus enters taurus 2026,saturn sextile pluto,mercury trine jupiter,cosmic weather march 2026,daily astrology,waxing gibbous virgo",
            "meta_title": "Venus at 29\u00b0 Aries: The Last Degree Before Home \u2014 Cosmic Weather March 30 | big3.me",
            "meta_description": "Venus at 29\u00b047' Aries \u2014 anaretic degree before entering Taurus. Saturn sextile Pluto exact at 0.17\u00b0. Mercury trine Jupiter in water signs. March 30, 2026.",
            "published_at": now,
            "created_at": now,
            "updated_at": now,
        },
    )


def downgrade() -> None:
    conn = op.get_bind()
    conn.execute(
        sa.text("DELETE FROM news_posts WHERE slug = :slug"),
        {"slug": SLUG},
    )
