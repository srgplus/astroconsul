"""Add daily cosmic weather post: Aries Stellium — March 23, 2026

Revision ID: 20260323_000004
Revises: 20260323_000003
Create Date: 2026-03-23
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import json
import uuid
from datetime import date, datetime, timezone

revision: str = "20260323_000004"
down_revision: str = "20260323_000003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SLUG = "cosmic-weather-aries-stellium-march-23-2026"


def upgrade() -> None:
    conn = op.get_bind()

    # Check for existing post with this slug
    result = conn.execute(
        sa.text("SELECT id FROM news_posts WHERE slug = :slug"),
        {"slug": SLUG},
    )
    if result.fetchone():
        return  # Already exists

    now = datetime.now(timezone.utc).isoformat()
    post_id = str(uuid.uuid4())

    sections = [
        {
            "heading": "The Sky Today: Aries Stellium",
            "body_html": (
                "<p>Here\u2019s what\u2019s clustered in early Aries right now:</p>"
                "<ul>"
                "<li><strong>Sun</strong> at 2\u00b051\u2032 Aries</li>"
                "<li><strong>Neptune</strong> at 1\u00b052\u2032 Aries</li>"
                "<li><strong>Saturn</strong> at 4\u00b029\u2032 Aries</li>"
                "</ul>"
                "<p>The Sun-Neptune conjunction is <strong>exact within 0.98\u00b0</strong> \u2014 "
                "the tightest major aspect of the day. "
                "When the Sun meets Neptune, the boundary between what\u2019s real and what\u2019s imagined dissolves. "
                "Pair that with Saturn \u2014 the planet of hard limits \u2014 sitting just 2.6\u00b0 away, "
                "and you get a paradox: the urge to dream meets the demand to build something concrete.</p>"
                "<p>Saturn and Neptune haven\u2019t shared the same sign since the late 1980s. "
                "Their conjunction in Aries means a generation-defining cycle is resetting \u2014 "
                "structures around spirituality, institutions, and collective ideals are being torn down "
                "and rebuilt from zero degrees. "
                "The Sun\u2019s presence today pulls this background hum into your conscious awareness.</p>"
                "<p>The Moon is a <strong>waxing crescent in Gemini</strong> (2\u00b013\u2032), "
                "sextile both the Sun and Neptune. "
                "There\u2019s a restless curiosity in the air \u2014 you want to talk about what you\u2019re sensing, "
                "even if you can\u2019t quite name it yet.</p>"
            ),
        },
        {
            "heading": "Saturn Sextile Pluto: Structural Renewal",
            "body_html": (
                "<p>Saturn at 4\u00b029\u2032 Aries forms an <strong>exact sextile to Pluto "
                "at 5\u00b003\u2032 Aquarius</strong> \u2014 orb just 0.58\u00b0. "
                "This is the tightest outer-planet aspect active today.</p>"
                "<p>Sextiles are opportunities, not guarantees. Saturn-Pluto in cooperative aspect says: "
                "power structures can be reformed without blowing everything up. "
                "If you\u2019ve been chipping away at a systemic change \u2014 "
                "in your career, community, or personal habits \u2014 "
                "today\u2019s geometry supports real progress.</p>"
                "<p>Pluto in Aquarius is reshaping collective power dynamics "
                "(think technology governance, social networks, decentralization). "
                "Saturn in Aries provides the grit to actually execute. "
                "This sextile will be active for weeks, but today the Sun lights it up "
                "indirectly through Saturn.</p>"
            ),
        },
        {
            "heading": "Mercury Conjunct North Node: Fated Messages",
            "body_html": (
                "<p>Mercury at 8\u00b050\u2032 Pisces sits <strong>exactly conjunct the North Node "
                "at 8\u00b045\u2032 Pisces</strong> \u2014 orb 0.07\u00b0. "
                "This is nearly a perfect overlap.</p>"
                "<p>Mercury-North Node conjunctions happen a few times a year, but in Pisces "
                "they carry a different weight. The message that reaches you today might not come "
                "through words \u2014 it could be a song, a dream, an image, or a feeling that "
                "won\u2019t leave you alone. Pisces communication is non-linear.</p>"
                "<p>If you need to have a difficult conversation, this aspect favors compassion "
                "over precision. Say what you mean, but lead with empathy. "
                "The North Node suggests this isn\u2019t random \u2014 there\u2019s a "
                "\u2018meant to be\u2019 quality to today\u2019s exchanges.</p>"
            ),
        },
        {
            "heading": "Mars Trine Jupiter: Bold Action Rewarded",
            "body_html": (
                "<p>Mars at 16\u00b027\u2032 Pisces trines Jupiter at 15\u00b020\u2032 Cancer \u2014 "
                "<strong>orb 1.12\u00b0, STRONG and applying</strong>.</p>"
                "<p>This is the best \u2018get things done\u2019 aspect of the day. "
                "Mars in Pisces often struggles with direction \u2014 energy diffuses instead of focusing. "
                "But Jupiter in Cancer catches that scattered drive and channels it into something "
                "protective and generous. Think: creative projects, caring for family, "
                "emotional breakthroughs in therapy, or simply having the courage to be vulnerable.</p>"
                "<p>If the Aries stellium makes you feel foggy (that\u2019s Neptune\u2019s influence), "
                "the Mars-Jupiter trine in water signs gives you a compass. "
                "Follow what feels right in your gut \u2014 your instincts are sharp today.</p>"
            ),
        },
        {
            "heading": "How to Work With Today\u2019s Energy",
            "body_html": (
                "<p>With four planets in Aries and a stellium this dense, the temptation is to rush. "
                "Don\u2019t. Neptune is the brake pedal today \u2014 it slows things down and asks you "
                "to <em>feel</em> before you act.</p>"
                "<p><strong>Best for:</strong></p>"
                "<ul>"
                "<li>Journaling or meditation \u2014 Sun-Neptune opens intuition wide</li>"
                "<li>Strategic planning \u2014 Saturn sextile Pluto supports long-term restructuring</li>"
                "<li>Important conversations \u2014 Mercury conjunct North Node makes words stick</li>"
                "<li>Creative work \u2014 Mars trine Jupiter in water signs fuels imagination with purpose</li>"
                "</ul>"
                "<p><strong>Watch out for:</strong></p>"
                "<ul>"
                "<li>Confusion about boundaries (Sun-Neptune can blur what\u2019s yours and what\u2019s not)</li>"
                "<li>Overcommitting under Mars-Jupiter\u2019s optimism</li>"
                "<li>Taking foggy feelings as signs that something is wrong \u2014 "
                "it\u2019s just Neptune passing through</li>"
                "</ul>"
                '<p>Check your personal transits at <a href="https://big3.me">big3.me</a> to see '
                "how this Aries stellium hits your natal chart \u2014 especially if you have planets "
                "in the first 5\u00b0 of any cardinal sign (Aries, Cancer, Libra, Capricorn).</p>"
            ),
        },
    ]

    conn.execute(
        sa.text("""
            INSERT INTO news_posts (
                id, slug, title, subtitle, date, author, status,
                intro, sections, conclusion,
                tags, keywords, meta_title, meta_description,
                published_at, created_at, updated_at
            ) VALUES (
                :id, :slug, :title, :subtitle, :date, :author, :status,
                :intro, :sections, :conclusion,
                :tags, :keywords, :meta_title, :meta_description,
                :published_at, :created_at, :updated_at
            )
        """),
        {
            "id": post_id,
            "slug": SLUG,
            "title": "Aries Stellium Ignites: Sun Meets Neptune and Saturn in the First Degree",
            "subtitle": "A once-in-36-years conjunction lights up \u2014 with the Sun standing right in the middle of it",
            "date": "2026-03-23",
            "author": "Victoria",
            "status": "published",
            "intro": (
                "Three planets crowd the first five degrees of Aries today. "
                "The Sun at 2\u00b051\u2032 sits less than a degree from Neptune at 1\u00b052\u2032 \u2014 "
                "and just 1.6\u00b0 from Saturn at 4\u00b029\u2032. "
                "This is the Saturn-Neptune conjunction in Aries, a transit that hasn\u2019t happened since 1989. "
                "The Sun lighting it up makes March 23 a day you\u2019ll feel in your bones."
            ),
            "sections": json.dumps(sections),
            "conclusion": (
                "March 23 packs more into one day than most weeks deliver. "
                "A Saturn-Neptune conjunction resetting in Aries, lit up by the Sun, "
                "with an exact Mercury-North Node alignment delivering fated messages \u2014 "
                "this is the kind of sky that marks a turning point. "
                "You don\u2019t have to do anything dramatic. Just pay attention. "
                "What surfaces today has been building for a long time."
            ),
            "tags": "transit,daily",
            "keywords": "aries stellium,sun conjunct neptune,saturn neptune conjunction 2026,mercury north node,mars trine jupiter,daily cosmic weather,march 2026 astrology",
            "meta_title": "Aries Stellium: Sun Meets Neptune & Saturn \u2014 March 23 | big3.me",
            "meta_description": "Sun conjunct Neptune (0.98\u00b0) and Saturn in early Aries \u2014 the Saturn-Neptune conjunction lights up. Plus Mercury exact on the North Node and Mars trine Jupiter.",
            "published_at": now,
            "created_at": now,
            "updated_at": now,
        },
    )


def downgrade() -> None:
    op.get_bind().execute(
        sa.text("DELETE FROM news_posts WHERE slug = :slug"),
        {"slug": SLUG},
    )
