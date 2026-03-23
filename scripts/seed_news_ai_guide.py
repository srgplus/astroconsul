#!/usr/bin/env python3
"""Seed the 'How to read transits with AI' blog post."""

import sys
import uuid
from datetime import date, datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import get_settings
from app.infrastructure.persistence.models import NewsPostModel
from app.infrastructure.persistence.session import database_is_enabled, session_scope


def _prompt_block(text: str) -> str:
    """Wrap text in a styled code block with copy button."""
    return (
        '<div class="prompt-block">'
        '<button type="button" class="copy-btn" onclick="copyPrompt(this)">Copy</button>'
        f"<pre>{text}</pre>"
        "</div>"
    )


DAILY_PROMPT_EN = """You are a professional transit astrologer. I'm sharing my current transit data from big3.me. Give me a practical daily analysis for today.

Here are my active transits:
[PASTE YOUR TRANSIT SCREENSHOT OR DATA HERE]

Rules for your analysis:
- Start with the overall energy of the day in one sentence (like a weather forecast)
- Rate the day's intensity from 1-10
- Focus on the 2-3 strongest transits (EXACT and STRONG only)
- For each transit, tell me: what it means practically, what to do, what to avoid
- End with one specific actionable recommendation for today
- Keep it under 300 words
- Be direct and practical, not vague
- If there are challenging aspects (squares, oppositions), frame them as opportunities not threats"""

WEEKLY_PROMPT_EN = """You are a professional transit astrologer. I'm sharing my current transit data from big3.me. Give me a weekly forecast for the next 7 days.

My natal data:
[PASTE YOUR BIG 3: Sun sign, Moon sign, Ascendant]

Here are my active transits:
[PASTE YOUR TRANSIT SCREENSHOT OR DATA HERE]

Rules for your analysis:
- Start with a 1-2 sentence weekly theme
- Break the week into 3 phases: Early week (Mon-Tue), Mid week (Wed-Thu), Late week (Fri-Sun)
- For each phase, identify the dominant transit energy and give practical advice
- Highlight the single best day and the most challenging day
- Career, relationships, and personal growth: give one insight for each
- End with a weekly mantra that captures the overall energy
- Keep it under 500 words
- Be specific to MY chart, not generic horoscope advice"""

DAILY_PROMPT_RU = """Ты профессиональный транзитный астролог. Я делюсь своими текущими транзитными данными с big3.me. Дай мне практический анализ дня на сегодня.

Вот мои активные транзиты:
[ВСТАВЬ СКРИНШОТ ИЛИ ДАННЫЕ ТРАНЗИТОВ СЮДА]

Правила для анализа:
- Начни с общей энергии дня в одном предложении (как прогноз погоды)
- Оцени интенсивность дня от 1 до 10
- Сфокусируйся на 2-3 самых сильных транзитах (только EXACT и STRONG)
- Для каждого транзита скажи: что это значит практически, что делать, чего избегать
- Заверши одной конкретной рекомендацией на сегодня
- Уложись в 300 слов
- Будь конкретным и практичным, не расплывчатым
- Если есть напряжённые аспекты (квадраты, оппозиции), подавай их как возможности, а не угрозы"""

WEEKLY_PROMPT_RU = """Ты профессиональный транзитный астролог. Я делюсь своими текущими транзитными данными с big3.me. Дай мне недельный прогноз на ближайшие 7 дней.

Мои натальные данные:
[ВСТАВЬ СВОЮ БОЛЬШУЮ ТРОЙКУ: знак Солнца, знак Луны, Асцендент]

Вот мои активные транзиты:
[ВСТАВЬ СКРИНШОТ ИЛИ ДАННЫЕ ТРАНЗИТОВ СЮДА]

Правила для анализа:
- Начни с темы недели в 1-2 предложениях
- Раздели неделю на 3 фазы: начало (Пн-Вт), середина (Ср-Чт), конец (Пт-Вс)
- Для каждой фазы определи доминирующую транзитную энергию и дай практический совет
- Выдели лучший день и самый сложный день
- Карьера, отношения, личный рост: по одному инсайту на каждую сферу
- Заверши мантрой недели, которая передаёт общую энергию
- Уложись в 500 слов
- Будь конкретным для МОЕЙ карты, а не общий гороскоп"""


POST = {
    "slug": "how-to-read-your-transits-with-ai",
    "title": "How to Get a Personalized Transit Reading Using AI",
    "subtitle": (
        "Copy your big3.me data, paste into Claude, "
        "get insights that generic horoscopes can't match"
    ),
    "date": date(2026, 3, 23),
    "author": "Victoria",
    "status": "published",
    "intro": (
        "Your big3.me transit page shows exact planetary positions, aspect types, "
        "orbs, and intensity scores — everything a professional astrologer would use "
        "for a reading. Here's how to turn that raw data into a personalized transit "
        "reading using Claude AI, in under two minutes."
    ),
    "sections": [
        # ── ENGLISH SECTION ──
        {
            "heading": "Step 1: Open Your Transits",
            "body_html": (
                '<p><span class="lang-badge">EN</span></p>'
                "<p>Go to <strong>big3.me</strong> and open your profile. "
                "Tap the <strong>Transits</strong> tab. You'll see a list of "
                "currently active transits with colored intensity badges.</p>"
                "<p>Here's what the labels mean:</p>"
                "<p><strong>EXACT</strong> — the transit is at its peak right now "
                "(orb under 1°). This is the most powerful moment of the transit. "
                "Pay the most attention to these.</p>"
                "<p><strong>STRONG</strong> — the transit is very close to exact "
                "(orb 1-3°). Still highly active and noticeable in your daily life.</p>"
                "<p><strong>APPLYING</strong> — the transit is approaching exact. "
                "The energy is building. You may feel it as anticipation, restlessness, "
                "or emerging themes.</p>"
                "<p><strong>SEPARATING</strong> — the transit has passed exact and is "
                "fading. The lesson is integrating. You're processing what happened.</p>"
                "<p>For the best AI reading, focus on your EXACT and STRONG transits — "
                "those are the ones shaping your day right now.</p>"
            ),
        },
        {
            "heading": "Step 2: Copy the Daily Prompt",
            "body_html": (
                "<p>Copy this prompt template and fill in your transit data. "
                "You can either type out the transits or simply take a screenshot "
                "of your big3.me transit page — Claude can read images.</p>"
                + _prompt_block(DAILY_PROMPT_EN)
            ),
        },
        {
            "heading": "Step 3: Paste into Claude",
            "body_html": (
                "<p>Open <strong>claude.ai</strong> (free account works). "
                "Paste the prompt. Then either:</p>"
                "<p><strong>Option A:</strong> Attach a screenshot of your big3.me "
                "transit page (use the camera/attachment icon)</p>"
                "<p><strong>Option B:</strong> Type out your top transits manually, "
                "e.g. \"Transit Saturn conjunct natal Moon, orb 0.5°, EXACT\"</p>"
                "<p>Hit send. Claude will analyze your specific transits and give you "
                "a reading tailored to your chart — not a generic Sun-sign horoscope.</p>"
            ),
        },
        {
            "heading": "Bonus: Weekly Forecast Prompt",
            "body_html": (
                "<p>Want a bigger picture? Use this weekly template instead. "
                "Include your Big 3 (Sun, Moon, Ascendant signs) for even more "
                "personalized insights.</p>"
                + _prompt_block(WEEKLY_PROMPT_EN)
            ),
        },
        {
            "heading": "Quick Version",
            "body_html": (
                "<p>Don't want to use a template? Just do this:</p>"
                "<p><strong>1.</strong> Screenshot your big3.me transits page<br>"
                "<strong>2.</strong> Open claude.ai<br>"
                "<strong>3.</strong> Attach the screenshot and type:</p>"
                + _prompt_block(
                    "What should I know about today based on these transits? "
                    "Be practical and specific."
                )
                + "<p>That's it. Claude will read the image and give you a "
                "personalized daily reading.</p>"
            ),
        },
        # ── RUSSIAN SECTION ──
        {
            "heading": "Как получить персональный разбор транзитов с помощью AI",
            "body_html": (
                '<hr class="lang-divider">'
                '<p><span class="lang-badge">RU</span></p>'
                "<p>На странице транзитов big3.me есть всё, что нужно для "
                "профессионального разбора: точные позиции планет, типы аспектов, "
                "орбы и баллы интенсивности. Вот как превратить эти данные в "
                "персональный прогноз с помощью Claude AI за пару минут.</p>"
            ),
        },
        {
            "heading": "Шаг 1: Откройте свои транзиты",
            "body_html": (
                "<p>Зайдите на <strong>big3.me</strong> и откройте свой профиль. "
                "Нажмите на вкладку <strong>Transits</strong>. Вы увидите список "
                "активных транзитов с цветными значками интенсивности.</p>"
                "<p>Что означают метки:</p>"
                "<p><strong>EXACT</strong> — транзит на пике прямо сейчас "
                "(орб менее 1°). Самый мощный момент. Обратите на него "
                "максимум внимания.</p>"
                "<p><strong>STRONG</strong> — транзит очень близок к точному "
                "(орб 1-3°). Всё ещё очень активен.</p>"
                "<p><strong>APPLYING</strong> — транзит приближается к точному. "
                "Энергия нарастает.</p>"
                "<p><strong>SEPARATING</strong> — транзит прошёл точку и затухает. "
                "Идёт интеграция опыта.</p>"
            ),
        },
        {
            "heading": "Шаг 2: Скопируйте промпт для дневного прогноза",
            "body_html": (
                "<p>Скопируйте этот шаблон и вставьте свои данные. "
                "Можно просто сделать скриншот страницы транзитов — "
                "Claude умеет читать изображения.</p>"
                + _prompt_block(DAILY_PROMPT_RU)
            ),
        },
        {
            "heading": "Шаг 3: Вставьте в Claude",
            "body_html": (
                "<p>Откройте <strong>claude.ai</strong> (бесплатный аккаунт подойдёт). "
                "Вставьте промпт. Затем:</p>"
                "<p><strong>Вариант А:</strong> Прикрепите скриншот страницы "
                "транзитов big3.me</p>"
                "<p><strong>Вариант Б:</strong> Напишите транзиты вручную, "
                "например: \"Транзитный Сатурн в соединении с натальной Луной, орб 0.5°, EXACT\"</p>"
                "<p>Нажмите отправить. Claude проанализирует именно ваши транзиты "
                "и даст персональный разбор.</p>"
            ),
        },
        {
            "heading": "Бонус: Промпт для недельного прогноза",
            "body_html": (
                "<p>Хотите более широкую картину? Используйте недельный шаблон. "
                "Включите вашу Большую Тройку (знаки Солнца, Луны, Асцендента) "
                "для максимально персонализированного прогноза.</p>"
                + _prompt_block(WEEKLY_PROMPT_RU)
            ),
        },
        {
            "heading": "Быстрая версия",
            "body_html": (
                "<p>Не хотите использовать шаблон? Просто сделайте так:</p>"
                "<p><strong>1.</strong> Сделайте скриншот страницы транзитов big3.me<br>"
                "<strong>2.</strong> Откройте claude.ai<br>"
                "<strong>3.</strong> Прикрепите скриншот и напишите:</p>"
                + _prompt_block(
                    "Что мне нужно знать о сегодняшнем дне на основе этих транзитов? "
                    "Будь практичным и конкретным."
                )
                + "<p>Всё. Claude прочитает изображение и даст персональный "
                "разбор дня.</p>"
            ),
        },
    ],
    "conclusion": (
        "Don't have your chart yet? Create it free at big3.me — it takes 30 seconds. "
        "Enter your birth date, time, and place, and you'll have your natal chart, "
        "active transits, and everything you need for an AI-powered reading."
    ),
    "meta_title": "How to Get a Personalized Transit Reading Using AI | big3.me",
    "meta_description": (
        "Step-by-step guide: copy your big3.me transit data, paste into Claude AI, "
        "and get a personalized astrology reading. Includes daily and weekly prompt "
        "templates in English and Russian."
    ),
    "keywords": (
        "transit reading,ai astrology,claude ai,personalized horoscope,"
        "big3.me,transit guide,astrology prompts,2026"
    ),
    "tags": "educational,guide",
    "published_at": datetime(2026, 3, 23, 9, 0, tzinfo=timezone.utc),
}


def main():
    settings = get_settings()
    if not database_is_enabled(settings):
        print("Database not enabled. Set ASTRO_CONSUL_PERSISTENCE_BACKEND=database")
        return

    now = datetime.now(timezone.utc)

    with session_scope(settings) as session:
        from sqlalchemy import select

        existing = session.execute(
            select(NewsPostModel).where(NewsPostModel.slug == POST["slug"])
        ).scalar_one_or_none()

        if existing:
            print(f"  SKIP (exists): {POST['slug']}")
            return

        sections_list = POST.pop("sections")
        post = NewsPostModel(
            id=str(uuid.uuid4()),
            **POST,
            sections=sections_list,
            created_at=now,
            updated_at=now,
        )
        session.add(post)
        print(f"  ADDED: {POST['slug']}")

    print("Done. Visit /news/how-to-read-your-transits-with-ai")


if __name__ == "__main__":
    main()
