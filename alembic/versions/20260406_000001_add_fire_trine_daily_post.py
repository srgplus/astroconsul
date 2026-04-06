"""Add daily cosmic weather post: Moon trine Saturn exact + Pluto stations — April 6, 2026

Revision ID: 20260406_000001
Revises: 20260330_000001
Create Date: 2026-04-06
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import json
import uuid
from datetime import date, datetime, timezone

revision: str = "20260406_000001"
down_revision: str = "20260330_000001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SLUG = "cosmic-weather-fire-trine-stability-april-6-2026"


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
            "heading": "Moon Trine Saturn: The Day\u2019s Emotional Anchor",
            "body_html": (
                "<p><strong>Moon at 6\u00b012' Sagittarius</strong> trine <strong>Saturn at 6\u00b013' Aries</strong> \u2014 "
                "orb 0.02\u00b0. This is the tightest aspect in today\u2019s sky by a wide margin.</p>"
                "<p>Moon-Saturn trines aren\u2019t glamorous. They don\u2019t promise magic or passion. "
                "What they offer is rarer: <em>emotional ground you can stand on</em>. "
                "In fire signs, this isn\u2019t cold discipline \u2014 it\u2019s the calm confidence of someone "
                "who knows exactly where they stand and isn\u2019t performing it for anyone.</p>"
                "<p>Sagittarius Moon wants meaning, perspective, the big picture. "
                "Saturn in Aries wants action with structure, courage with accountability. "
                "The trine makes them allies: your instincts and your responsibilities "
                "are pointing in the same direction today.</p>"
                "<p>What this transit supports:</p>"
                "<ul>"
                "<li><strong>Difficult decisions</strong> \u2014 you\u2019ll feel both the emotion and the logic simultaneously, which is rare</li>"
                "<li><strong>Honest conversations</strong> \u2014 Saturn provides the backbone; Sagittarius Moon provides the directness</li>"
                "<li><strong>Long-term planning</strong> \u2014 emotions aren\u2019t clouding your judgment today, they\u2019re informing it</li>"
                "<li><strong>Teaching or mentoring</strong> \u2014 Sagittarius Moon + Saturn in Aries = authoritative warmth</li>"
                "</ul>"
                "<p>The Moon also forms a sextile to <strong>Pluto at 5\u00b017' Aquarius</strong> (orb 0.91\u00b0), "
                "connecting your emotional awareness directly to the deepest transformational energy in the sky. "
                "Feelings today aren\u2019t surface-level \u2014 they arrive with roots.</p>"
            ),
        },
        {
            "heading": "Sun Square Jupiter: The Tension That Matters",
            "body_html": (
                "<p><strong>Sun at 16\u00b041' Aries</strong> square <strong>Jupiter at 16\u00b010' Cancer</strong> \u2014 "
                "orb 0.51\u00b0. This is the day\u2019s most important tension.</p>"
                "<p>Sun-Jupiter squares are the aspect of <em>too much</em>. Too much confidence. "
                "Too much optimism. Too many yeses when one good no would serve you better. "
                "In Aries-Cancer, the tension is between personal ambition (Sun in Aries charging forward) "
                "and emotional security (Jupiter in Cancer expanding what feels safe).</p>"
                "<p>The risk: overcommitting because something <em>feels</em> right without checking "
                "whether it\u2019s actually sustainable. Jupiter in Cancer makes everything seem nurturing and blessed. "
                "Sun in Aries makes everything seem urgent and destined. Together, they can inflate "
                "a good idea into a grandiose one.</p>"
                "<p>The gift: this square generates <em>energy</em>. Squares are the engine of the zodiac \u2014 "
                "they create friction that demands movement. If you channel this into something concrete "
                "(Moon-Saturn trine helps here), the result can be genuinely expansive.</p>"
                "<p><strong>Best use of Sun square Jupiter today:</strong></p>"
                "<ul>"
                "<li>Launch the project you\u2019ve been planning \u2014 but cut scope by 30%</li>"
                "<li>Have the big conversation \u2014 but listen as much as you speak</li>"
                "<li>Take the risk \u2014 but set a limit before you start, not after</li>"
                "</ul>"
                "<p><strong>Who feels this most:</strong> anyone with natal planets at 14\u00b0\u201319\u00b0 of cardinal signs "
                "(Aries, Cancer, Libra, Capricorn). Check your chart at <a href='https://big3.me'>big3.me</a>.</p>"
            ),
        },
        {
            "heading": "Pluto Stationary: Transformation Holds Its Breath",
            "body_html": (
                "<p><strong>Pluto at 5\u00b017' Aquarius</strong> \u2014 daily motion 0.01\u00b0. "
                "For all practical purposes, Pluto is standing still.</p>"
                "<p>When planets station, their themes intensify. A moving planet distributes its energy "
                "across degrees. A stationary planet concentrates it like a magnifying glass on one point. "
                "Pluto stationary means: whatever you\u2019ve been avoiding transforming is now impossible to ignore.</p>"
                "<p>At 5\u00b0 Aquarius, Pluto\u2019s transformation is collective and structural \u2014 "
                "how we organize, who holds power, what systems we trust. But personally, "
                "it hits wherever early Aquarius falls in your chart.</p>"
                "<p>Today, stationary Pluto is part of a web:</p>"
                "<ul>"
                "<li><strong>Saturn sextile Pluto</strong> (0.93\u00b0 orb) \u2014 the disciplined transformation aspect "
                "that\u2019s been running for weeks. Saturn at 6\u00b013' Aries builds frameworks for what Pluto tears down and rebuilds</li>"
                "<li><strong>Moon sextile Pluto</strong> (0.91\u00b0 orb) \u2014 emotional access to deep change. "
                "Today you can <em>feel</em> what usually stays in the unconscious</li>"
                "<li><strong>Venus square Pluto</strong> (3.10\u00b0 orb, applying) \u2014 desire, jealousy, "
                "and intensity in relationships and finances. Venus at 8\u00b024' Taurus wants stability; "
                "Pluto says nothing is stable until it\u2019s been tested</li>"
                "<li><strong>Neptune sextile Pluto</strong> (2.89\u00b0 orb) \u2014 the slow generational backdrop, "
                "spiritual evolution meeting structural transformation</li>"
                "</ul>"
                "<p>A stationary Pluto day isn\u2019t subtle. It\u2019s the day you look at something honestly "
                "and realize you can\u2019t unsee it.</p>"
            ),
        },
        {
            "heading": "Venus, Mars, and Mercury: The Supporting Cast",
            "body_html": (
                "<p>Three personal planets are weaving through supportive aspects today, "
                "adding texture to the Moon-Saturn stability and Pluto intensity.</p>"
                "<p><strong>Venus at 8\u00b024' Taurus sextile North Node at 8\u00b015' Pisces</strong> \u2014 "
                "orb 0.14\u00b0. This is the second-tightest aspect today. Venus in her home sign, "
                "connecting with the karmic direction of the North Node. "
                "What you value, what you find beautiful, what you\u2019re willing to invest in \u2014 "
                "these are aligned with your deeper path right now. Trust your taste today. "
                "The things that attract you aren\u2019t random; they\u2019re directional.</p>"
                "<p><strong>Mars at 27\u00b024' Pisces sextile Uranus at 29\u00b000' Taurus</strong> \u2014 "
                "orb 1.59\u00b0. Action meets innovation. Mars in Pisces acts on intuition; "
                "Uranus in late Taurus disrupts material comfort zones. "
                "This sextile is excellent for creative problem-solving \u2014 "
                "the solution that arrives from a direction you weren\u2019t looking.</p>"
                "<p><strong>Mercury at 19\u00b005' Pisces trine Jupiter at 16\u00b010' Cancer</strong> \u2014 "
                "orb 2.91\u00b0. A water trine between the planet of thinking and the planet of expansion. "
                "Mercury in Pisces thinks in images, metaphors, and feelings. "
                "Jupiter in Cancer amplifies emotional intelligence. "
                "This is the transit for writing, therapy, deep conversations, "
                "and understanding something you\u2019ve only been sensing.</p>"
                "<p>Together, these three say: <em>follow the intuition, express the feeling, "
                "and what you build today will be aligned with where you\u2019re headed</em>.</p>"
            ),
        },
        {
            "heading": "How to Work With Today\u2019s Sky",
            "body_html": (
                "<p>April 6 is a day of <strong>structured intensity</strong>. "
                "The Moon-Saturn fire trine provides emotional steadiness. "
                "Pluto stationary provides depth. Sun square Jupiter provides momentum "
                "(and a warning about overreach). The personal planets \u2014 Venus, Mars, Mercury \u2014 "
                "are all in supportive aspects that reward intuition and creativity.</p>"
                "<p><strong>Best for:</strong></p>"
                "<ul>"
                "<li>Making a decision you\u2019ve been sitting on \u2014 Moon trine Saturn says your instincts are reliable today</li>"
                "<li>Deep work and research \u2014 Pluto stationary + Mercury trine Jupiter = ability to go deep and make connections</li>"
                "<li>Creative projects \u2014 Mars sextile Uranus sparks innovation; Mercury trine Jupiter expands the vision</li>"
                "<li>Financial planning \u2014 Venus in Taurus sextile North Node is practical destiny; just watch the Pluto square for compulsive spending</li>"
                "<li>Relationship clarity \u2014 Venus-Pluto square surfaces what\u2019s real; Moon-Saturn helps you handle it</li>"
                "</ul>"
                "<p><strong>Watch out for:</strong></p>"
                "<ul>"
                "<li>Overcommitting under Sun square Jupiter \u2014 enthusiasm isn\u2019t the same as capacity</li>"
                "<li>Power struggles with Pluto stationary \u2014 the urge to control intensifies when Pluto stops moving</li>"
                "<li>Emotional intensity that feels disproportionate \u2014 that\u2019s Pluto concentrating its beam. Breathe through it</li>"
                "</ul>"
                "<p>Waning Gibbous Moon (229\u00b0) \u2014 this is a release and integration phase. "
                "Not the time to start something entirely new, but ideal for deepening, "
                "refining, and clearing away what\u2019s no longer serving the vision. "
                "Track how these transits interact with your personal chart at "
                "<a href='https://big3.me'>big3.me</a>.</p>"
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
            "title": "Moon Trine Saturn at 0.02\u00b0: Fire Trine Stability While Pluto Stations",
            "subtitle": "The sky\u2019s tightest aspect today is a near-perfect fire trine between Moon and Saturn \u2014 a rare moment of emotional certainty while Pluto slows to a crawl before retrograde",
            "date": "2026-04-06",
            "author": "Victoria",
            "status": "published",
            "intro": (
                "Moon at 6\u00b012' Sagittarius trine Saturn at 6\u00b013' Aries \u2014 orb 0.02\u00b0. "
                "That\u2019s not a typo. Today\u2019s tightest aspect is accurate to the arc-minute, "
                "a fire trine so precise it hums. Emotional clarity meets structural discipline "
                "in the boldest element. Meanwhile, Pluto at 5\u00b017' Aquarius has slowed to 0.01\u00b0 per day \u2014 "
                "effectively stationary, preparing to turn retrograde. When the planet of transformation "
                "pauses, everything it touches intensifies. And today, it touches almost everything."
            ),
            "sections": json.dumps(sections, ensure_ascii=False),
            "conclusion": (
                "Today\u2019s sky is built on a rare foundation: Moon trine Saturn at 0.02\u00b0 orb "
                "in fire signs, giving you emotional clarity and structural confidence simultaneously. "
                "Pluto stationary at 5\u00b017' Aquarius intensifies everything it touches \u2014 "
                "and with Saturn sextile Pluto at 0.93\u00b0, the transformation has a blueprint. "
                "Sun square Jupiter (0.51\u00b0) provides the spark and the caution: "
                "dream big, but build to scale. Venus sextile North Node (0.14\u00b0) whispers "
                "that what you\u2019re drawn to today isn\u2019t a distraction \u2014 it\u2019s the direction. "
                "Mercury trine Jupiter opens the mind. Mars sextile Uranus opens the path. "
                "The only retrograde is the North Node \u2014 and the Nodes are always retrograde. "
                "Everything else is moving forward. The question isn\u2019t whether to act. "
                "It\u2019s whether you\u2019ll match the sky\u2019s precision with your own."
            ),
            "tags": "transit,daily",
            "keywords": "moon trine saturn,sun square jupiter,pluto stationary,pluto retrograde 2026,saturn sextile pluto,venus north node,cosmic weather april 2026,daily astrology april 6",
            "meta_title": "Moon Trine Saturn Exact + Pluto Stations \u2014 April 6, 2026 | big3.me",
            "meta_description": "Moon trine Saturn at 0.02\u00b0 orb in fire signs. Sun square Jupiter exact. Pluto stationary before retrograde. Cosmic weather for April 6, 2026.",
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
