"""What may not be posted, and what a report may say.

The text one person puts in front of another on big3.me is a profile's
display name and its handle, and the messages of the chats. There are no
posts or comments. So this is where objectionable material is stopped on the
way in, which is the first of App Review's four requirements for a social
network (guideline 1.2). The other three (report, block and published
contact details) live in the social routes, the app, and the legal pages.

The list is deliberately short and unambiguous. A filter that rejects "Dick"
or "Scunthorpe" turns real people away from their own names, which is worse
than the rare slur that gets past it and is then reported. So:

* stems that are never innocent inside another word are matched anywhere;
* words that are innocent inside other words ("rape" in "grape") are matched
  only as whole words;
* spacing, underscores, dots and the usual digit-for-letter swaps are undone
  first, so "f_u_c_k" and "sh1t" do not walk around it.

A message is checked against a narrower list, slurs and sexual violence
only, a word at a time (see `message_is_objectionable`): collapsing the
spaces of a whole sentence would glue innocent neighbours into a stem ("поп
издал" reads "попиздал").
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
    "нахуй",
    "похуй",
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

# A private message is held to a narrower list than a name. Two people who
# chose to talk may swear at each other; a name is shown to everyone. What no
# message may carry is hate aimed at a group and sexual violence: the slurs
# and the words below, matched the same way as the names' lists.
_MESSAGE_STEMS = (
    "nigger",
    "faggot",
    "пидор",
    "пидар",
)
_MESSAGE_WORDS = (
    "nigga",
    "retard",
    "rape",
    "rapist",
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


def _word_is_objectionable(word: str, stems: tuple[str, ...] = _STEMS, whole: tuple[str, ...] = _WORDS) -> bool:
    """One word of a message, normalized: a stem anywhere in it once its
    inner separators are gone, or a whole word of the list, with or without
    the punctuation around it ("s.h.i.t!")."""
    collapsed = _SEPARATORS.sub("", word)
    if any(stem in collapsed for stem in stems):
        return True
    parts = set(_WORD_SPLIT.split(word)) | set(_WORD_SPLIT.split(collapsed))
    return any(part in parts for part in whole)


def message_is_objectionable(text: str | None) -> bool:
    """True when a message carries a word that may not be sent to anyone:
    a slur or sexual violence (`_MESSAGE_STEMS`, `_MESSAGE_WORDS`). Everyday
    swearing between two people is theirs to have, and is not refused.

    A message is read a word at a time, plus any run of single letters
    spelled out with spaces ("f a g g o t"), which is the one way around a
    word-by-word check that people actually use."""
    if not text:
        return False
    words = _normalize(text).split()
    if any(_word_is_objectionable(word, _MESSAGE_STEMS, _MESSAGE_WORDS) for word in words):
        return True
    run: list[str] = []
    for word in [*words, ""]:
        if len(word) == 1:
            run.append(word)
            continue
        if len(run) > 1 and _word_is_objectionable("".join(run), _MESSAGE_STEMS, _MESSAGE_WORDS):
            return True
        run = []
    return False


def check_profile_text(profile_name: str, username: str) -> None:
    """Raise ValueError when a name or handle may not be posted.

    A ValueError is what the profile routes already turn into a 400 with its
    message as the detail, so the app shows this sentence as it stands.
    """
    if contains_objectionable(profile_name) or contains_objectionable(username):
        raise ValueError("This name can't be used on big3.me. Please choose another one.")
