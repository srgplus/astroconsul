"""What may not be posted, and what a report may say.

One person puts text in front of another on big3.me in two places: a
profile's display name and handle, and a chat message. There are no posts or
comments. So this is where objectionable material is stopped on the way in,
which is the first of App Review's four requirements for a social network
(guideline 1.2). The other three — report, block and published contact
details — live in the social routes, the app, and the legal pages.

Names and messages go through the same list. A message is between two people,
but its reader did not choose its words, and a slur in a chat is exactly what
the requirement is about.

The list is deliberately short and unambiguous. A filter that rejects "Dick"
or "Scunthorpe" turns real people away from their own names, which is worse
than the rare slur that gets past it and is then reported. So:

* stems that are never innocent inside another word are matched anywhere;
* words that are innocent inside other words ("rape" in "grape") are matched
  only as whole words;
* spacing, underscores, dots and the usual digit-for-letter swaps are undone
  first, so "f_u_c_k" and "sh1t" do not walk around it.
"""

from __future__ import annotations

import re

# Matched anywhere in the collapsed text. Latin and Cyrillic. Each stem was
# checked against ordinary words it could hide in: "ебат" is gone because it
# sits inside "дебаты", "хуе" because of "страхуем", "ебан" because of the
# surname Rebane.
_STEMS = (
    "fuck",
    "fvck",
    "motherfuck",
    "cocksuck",
    "nigger",
    "faggot",
    "пизд",
    "еблан",
    "уебок",
    "уебищ",
    "бляд",
    "мудак",
    "гандон",
    "шлюх",
    "пидор",
    "пидар",
    "хуйн",
    "хуесос",
)

# Matched only as a whole word, because each also sits inside an innocent one.
_WORDS = (
    "cunt",
    "shit",
    "bitch",
    "slut",
    "whore",
    "rape",
    "rapist",
    "retard",
    "nazi",
    "porn",
    "nigga",
    "хуй",
    "сука",
    "суки",
    "сучка",
    "шалава",
    "порно",
    "ебать",
    "ебал",
    "ебаный",
    "ебанный",
)

_LEET = str.maketrans({"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "ё": "е"})
_SEPARATORS = re.compile(r"[\s_.\-*+|]+")
_WORD_SPLIT = re.compile(r"[^0-9a-zа-яё@$]+")

# What a person can report a profile for. Kept to a handful so the sheet in the
# app reads as a choice rather than a form; "other" takes the free text.
REPORT_REASONS = ("spam", "harassment", "impersonation", "inappropriate", "other")
REPORT_DETAILS_MAX = 1000


def _normalize(text: str) -> str:
    return text.lower().translate(_LEET)


def contains_objectionable(text: str | None) -> bool:
    """True when the text carries a word that may not be shown to others."""
    if not text:
        return False
    normalized = _normalize(text)
    collapsed = _SEPARATORS.sub("", normalized)
    if any(stem in collapsed for stem in _STEMS):
        return True
    words = set(_WORD_SPLIT.split(normalized))
    return any(word in words for word in _WORDS)


def check_profile_text(profile_name: str, username: str) -> None:
    """Raise ValueError when a name or handle may not be posted.

    A ValueError is what the profile routes already turn into a 400 with its
    message as the detail, so the app shows this sentence as it stands.
    """
    if contains_objectionable(profile_name) or contains_objectionable(username):
        raise ValueError("This name can't be used on big3.me. Please choose another one.")


def check_message_text(body: str) -> None:
    """Raise ValueError when a chat message may not be sent.

    Nothing is stored and nobody is told: the sender sees why it did not go
    and can say it another way."""
    if contains_objectionable(body):
        raise ValueError("This message can't be sent: it has words that aren't allowed on big3.me.")
