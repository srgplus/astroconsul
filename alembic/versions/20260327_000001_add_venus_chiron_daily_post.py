"""Add daily cosmic weather post: Venus Conjunct Chiron in Aries — March 27, 2026

Revision ID: 20260327_000001
Revises: 20260325_000001
Create Date: 2026-03-27
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import json
import uuid
from datetime import date, datetime, timezone

revision: str = "20260327_000001"
down_revision: str = "20260325_000001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SLUG = "cosmic-weather-venus-chiron-aries-march-27-2026"


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
            "heading": "Venus Conjunct Chiron at 25\u00b0\u201326\u00b0 Aries: The Wound That Teaches Love",
            "body_html": (
                "<p><strong>Venus at 26\u00b005' Aries</strong> conjunct <strong>Chiron at 25\u00b026' Aries</strong> \u2014 "
                "orb 0.65\u00b0. This is today's most personal transit.</p>"
                "<p>Chiron is the wound that doesn't fully close but teaches you to heal others. "
                "When Venus crosses it, the wound speaks in the language of love and self-worth. "
                "Old patterns surface: the relationship where you dimmed yourself, "
                "the compliment you couldn't accept, the way you confuse being needed with being loved.</p>"
                "<p>In Aries, this conjunction has an edge. Aries doesn't sit with pain \u2014 it charges through. "
                "Venus-Chiron in Aries says: <em>the bravest thing you can do today is be soft</em>. "
                "Not armored. Not performing strength. Actually vulnerable.</p>"
                "<p>What Venus conjunct Chiron can bring:</p>"
                "<ul>"
                "<li><strong>Healing conversations</strong> \u2014 the kind where you say the thing you've rehearsed for years</li>"
                "<li><strong>Attraction to what heals</strong> \u2014 people, art, music that touches the exact right nerve</li>"
                "<li><strong>Self-worth recalibration</strong> \u2014 seeing where you've underpriced yourself emotionally</li>"
                "<li><strong>Creative breakthroughs</strong> \u2014 pain channeled into beauty (Venus's specialty)</li>"
                "</ul>"
                "<p><strong>Who feels this most:</strong> anyone with natal planets at 23\u00b0\u201328\u00b0 of cardinal signs "
                "(Aries, Cancer, Libra, Capricorn), or a natal Venus-Chiron aspect. "
                "Check your chart at <a href='https://big3.me'>big3.me</a>.</p>"
            ),
        },
        {
            "heading": "Moon Sextile Uranus: Emotional Lightning in Late Cancer",
            "body_html": (
                "<p><strong>Moon at 28\u00b045' Cancer</strong> sextile <strong>Uranus at 28\u00b034' Taurus</strong> \u2014 "
                "orb just 0.19\u00b0. The second-tightest aspect today, and the fastest.</p>"
                "<p>Moon-Uranus contacts are the sky's way of jolting you out of emotional autopilot. "
                "Sextiles are cooperative \u2014 this isn't a shock, it's an insight. "
                "Something you've been feeling in the background suddenly clicks into focus.</p>"
                "<p>The Moon is in the final degrees of Cancer \u2014 her home sign \u2014 about to cross into Leo. "
                "There's a quality of emotional completion here. The last 2.5 days of Cancer Moon "
                "have been about nurturing, family, inner security. Now Uranus says: "
                "<em>what if the thing you're clinging to for safety is the thing keeping you stuck?</em></p>"
                "<p>This is a brief transit (Moon moves fast), but it can catalyze:</p>"
                "<ul>"
                "<li>A sudden honest conversation with family or a close friend</li>"
                "<li>An emotional 'aha' moment about a pattern you've repeated</li>"
                "<li>The courage to change a domestic situation you've outgrown</li>"
                "<li>Unexpected warmth from an unlikely source</li>"
                "</ul>"
                "<p>Moon also squares Venus-Chiron (2.66\u00b0 orb), creating a brief T-square: "
                "emotional comfort (Moon in Cancer) pulled between vulnerability in love (Venus-Chiron in Aries) "
                "and the need for stability (Uranus in Taurus). The tension is productive \u2014 it forces a choice.</p>"
            ),
        },
        {
            "heading": "Saturn Sextile Pluto: Day Three of the Tightest Aspect in the Sky",
            "body_html": (
                "<p><strong>Saturn at 4\u00b059' Aries</strong> sextile <strong>Pluto at 5\u00b008' Aquarius</strong> \u2014 "
                "orb 0.15\u00b0. For the third consecutive day, this is the tightest major aspect overhead.</p>"
                "<p>If you've been reading the cosmic weather this week, you know this one. "
                "Saturn-Pluto aspects mark structural turning points \u2014 not in a single day, "
                "but across months. The sextile is the constructive version: "
                "it builds where the conjunction and square tear down.</p>"
                "<p>What's different today: the Sun has moved to 6\u00b049' Aries, now 1.84\u00b0 past Saturn "
                "and 1.69\u00b0 from Pluto. The Sun is <em>carrying</em> the Saturn-Pluto sextile's energy \u2014 "
                "illuminating it, making it conscious. Yesterday it was structural. Today it's personal.</p>"
                "<p>Combined with Venus-Chiron, there's a theme: <strong>rebuilding from the wound</strong>. "
                "Saturn-Pluto provides the architecture. Venus-Chiron provides the reason. "
                "You're not just healing \u2014 you're building something stronger where the break was.</p>"
                "<p>Saturn also remains conjunct Neptune (2.95\u00b0 orb) \u2014 the vision-meets-discipline aspect "
                "that defines early Aries season 2026. Dreams need scaffolding. Saturn in Aries is building it.</p>"
            ),
        },
        {
            "heading": "Mars Trine Jupiter: The Action Channel Opens",
            "body_html": (
                "<p><strong>Mars at 19\u00b035' Pisces</strong> trine <strong>Jupiter at 15\u00b031' Cancer</strong> \u2014 "
                "orb 4.08\u00b0. This is a wide aspect but applying (getting tighter over the coming days), "
                "and in water signs, it flows more than it pushes.</p>"
                "<p>Mars-Jupiter trines are the sky's green light. In water signs, the action is intuitive "
                "rather than aggressive. You don't bulldoze \u2014 you navigate. You don't force \u2014 you flow toward "
                "the opening.</p>"
                "<p>Practical applications today:</p>"
                "<ul>"
                "<li><strong>Creative projects</strong> \u2014 Mars in Pisces has vision; Jupiter in Cancer has heart. Together, the work feels meaningful.</li>"
                "<li><strong>Emotional courage</strong> \u2014 pairs well with Venus-Chiron. You have the energy to go toward the hard conversation, not away from it.</li>"
                "<li><strong>Financial decisions</strong> \u2014 Jupiter in Cancer favors security-building; Mars gives the push to actually move money, sign papers, commit.</li>"
                "</ul>"
                "<p>This trine will tighten over the next week. Today is the warm-up \u2014 the impulse to act. "
                "Let it build.</p>"
            ),
        },
        {
            "heading": "How to Work With Today's Sky",
            "body_html": (
                "<p>March 27 is a day about <strong>courageous tenderness</strong>. "
                "Venus-Chiron says the healing is in the vulnerability. "
                "Moon-Uranus says the breakthrough comes from letting go of what's familiar. "
                "Saturn-Pluto says the ground will hold.</p>"
                "<p><strong>Best for:</strong></p>"
                "<ul>"
                "<li>Honest conversations about feelings \u2014 especially the ones you've avoided</li>"
                "<li>Therapy, journaling, or any practice that names the wound</li>"
                "<li>Creative work \u2014 write, paint, compose. Venus-Chiron in Aries makes beautiful art from real pain</li>"
                "<li>Repairing a relationship that frayed \u2014 the sky supports reconciliation today</li>"
                "<li>Starting something that scares you \u2014 Mars trine Jupiter gives momentum</li>"
                "</ul>"
                "<p><strong>Watch out for:</strong></p>"
                "<ul>"
                "<li>Reopening old wounds without a plan to heal them \u2014 Venus-Chiron can be raw</li>"
                "<li>Confusing sympathy with love \u2014 Chiron can attract rescuer dynamics</li>"
                "<li>Emotional decisions made in the Moon-Uranus flash \u2014 let the insight settle before acting</li>"
                "</ul>"
                "<p>All planets remain direct. The energy is forward-moving, even when the work is inward. "
                "Track how these transits hit your personal chart at "
                "<a href='https://big3.me'>big3.me</a> \u2014 especially if you have natal placements "
                "near 26\u00b0 Aries or 5\u00b0 Aries/Aquarius.</p>"
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
            "title": "Venus Conjunct Chiron in Aries: Love Where It Hurts",
            "subtitle": "The sky's most personal transit today asks you to stay open where you've learned to protect \u2014 while Saturn and Pluto hold the ground beneath you",
            "date": "2026-03-27",
            "author": "Victoria",
            "status": "published",
            "intro": (
                "Venus at 26\u00b005' Aries meets Chiron at 25\u00b026' \u2014 orb just 0.65\u00b0. "
                "This is the kind of transit that doesn't shout. It aches. "
                "Venus-Chiron conjunctions expose the tender spots in how we love, "
                "what we value, and where we've built armor instead of bridges. "
                "In Aries, the healing isn't passive \u2014 it requires you to go first. "
                "Meanwhile, Saturn sextile Pluto holds at a razor-thin 0.15\u00b0 orb, "
                "offering structural power to anyone willing to rebuild."
            ),
            "sections": json.dumps(sections, ensure_ascii=False),
            "conclusion": (
                "Today the sky asks you to be brave in a way that doesn't look brave. "
                "Venus conjunct Chiron at 0.65\u00b0 orb is the day's emotional center of gravity \u2014 "
                "it's where the tenderness meets the edge. "
                "Saturn sextile Pluto (0.15\u00b0) continues its quiet renovation of foundations. "
                "Moon sextile Uranus (0.19\u00b0) sends a flash of clarity before the Moon exits Cancer. "
                "Mars trine Jupiter whispers: the path forward is open, if you'll trust the current. "
                "No retrogrades. No excuses. Just the question Venus-Chiron always asks: "
                "can you love the part of yourself you've been hiding?"
            ),
            "tags": "transit,daily",
            "keywords": "venus conjunct chiron,chiron aries 2026,saturn sextile pluto,moon sextile uranus,cosmic weather march 2026,venus chiron conjunction,daily astrology,healing transits",
            "meta_title": "Venus Conjunct Chiron in Aries \u2014 Cosmic Weather March 27 | big3.me",
            "meta_description": "Venus conjunct Chiron at 26\u00b0 Aries (0.65\u00b0 orb) \u2014 healing through courageous love. Saturn sextile Pluto exact at 0.15\u00b0. Cosmic weather for March 27, 2026.",
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
