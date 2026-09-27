"""The social layer: likes, who follows and likes whom, Activity, blocks, reports.

Kept apart from the profile repositories because none of it is about a chart.
It is about accounts and what they do to each other's profiles — the half of
"social network" that following alone never supplied: following went one way
and nothing came back, so a profile's owner never learned who was there.

Two identities meet here, and every method keeps them straight:

* an **account** acts — it follows, likes, blocks and reports;
* a **profile** is what gets followed and liked, and its owner is the account
  that hears about it.

When an account has to be shown to someone — as the one who liked your chart,
or as a follower — it is shown as its own chart: the profile it marked as its
own, or failing that the one it touched last. That is its "card".
"""

from __future__ import annotations

import json
from datetime import UTC, date, datetime
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import and_, delete, func, or_, select, union, union_all
from sqlalchemy.orm import Session, sessionmaker

from app.domain.chat_rules import may_write
from app.infrastructure.persistence.models import (
    DeviceTokenModel,
    LatestTransitModel,
    NatalChartModel,
    ProfileFollowModel,
    ProfileLikeModel,
    ProfileModel,
    ProfileReportModel,
    UserBlockModel,
    UserModel,
)
from app.infrastructure.repositories.sqlalchemy_repositories import _isoformat_z, _now_utc, ensure_user

# How far back Activity reaches. It is a list of what happened lately, not an
# archive; the counts on a profile carry the totals.
ACTIVITY_LIMIT = 50

# What a card says when the account behind it has no chart at all: it can still
# like and follow, it just has nothing of its own to show.
EMPTY_CARD: dict[str, Any] = {
    "profile_id": None,
    "profile_name": None,
    "username": None,
    "natal_summary": None,
    "latest_transit": None,
}


_EPOCH = datetime.min.replace(tzinfo=UTC)


def today_in(zone_name: str | None) -> date:
    """Today in a profile's own zone: the day half of the state a like is for.

    One zone per profile rather than the liker's, so everyone who likes a
    chart on the same day is counted on the same day, wherever they are."""
    try:
        zone = ZoneInfo(zone_name) if zone_name else UTC
    except (ZoneInfoNotFoundError, ValueError):
        zone = UTC
    return datetime.now(zone).date()


def _aware(value: datetime | None) -> datetime | None:
    """SQLite hands timestamps back without a zone; everything here is UTC."""
    if value is None:
        return None
    return value if value.tzinfo is not None else value.replace(tzinfo=UTC)


def _stamp(value: datetime | None) -> str | None:
    """A stored timestamp as the API spells one, or None for a missing one."""
    aware = _aware(value)
    return _isoformat_z(aware) if aware is not None else None


def account_cards(session: Session, user_ids: set[str]) -> dict[str, dict[str, Any]]:
    """Each account's card, keyed by account id. An account with no profile
    gets the empty card rather than being dropped, so a like from it still
    shows up as something.

    A function rather than a method so the chats can draw the person on the
    other side the same way, in the session they already hold."""
    if not user_ids:
        return {}

    # The primary profile wins outright; without one, the profile touched
    # last stands in for the account. The owner's primary rides along on
    # each profile row, so this is one query rather than two.
    chosen: dict[str, tuple[str, str, str, datetime]] = {}
    rows = session.execute(
        select(
            ProfileModel.id,
            ProfileModel.user_id,
            ProfileModel.display_name,
            ProfileModel.handle,
            ProfileModel.updated_at,
            UserModel.primary_profile_id,
        )
        .outerjoin(UserModel, UserModel.id == ProfileModel.user_id)
        .where(ProfileModel.user_id.in_(user_ids))
    ).all()
    for profile_id, user_id, name, handle, updated_at, primary_id in rows:
        stamp = _aware(updated_at) or _EPOCH
        current = chosen.get(user_id)
        if primary_id == profile_id:
            chosen[user_id] = (profile_id, name, handle, stamp)
        elif current is None or (primary_id != current[0] and stamp > current[3]):
            chosen[user_id] = (profile_id, name, handle, stamp)

    summaries: dict[str, Any] = {}
    readings: dict[str, dict[str, Any]] = {}
    picked_ids = [value[0] for value in chosen.values()]
    if picked_ids:
        # The Big 3 alone, read out of the chart in the database: the
        # whole payload is some 9 KB a card, and a card shows 100 bytes of
        # it. With it, the last numbers each chart was read at, so a card
        # opened from Activity shows the person's day rather than an empty
        # sky.
        for chart_profile_id, summary, tii, tension, feels in session.execute(
            select(
                ProfileModel.id,
                NatalChartModel.chart_payload_json["natal_summary"],
                LatestTransitModel.tii,
                LatestTransitModel.tension_ratio,
                LatestTransitModel.feels_like,
            )
            .join(NatalChartModel, NatalChartModel.id == ProfileModel.chart_id)
            .outerjoin(LatestTransitModel, LatestTransitModel.profile_id == ProfileModel.id)
            .where(ProfileModel.id.in_(picked_ids))
        ).all():
            summaries[str(chart_profile_id)] = summary if isinstance(summary, dict) else None
            if tii is not None:
                readings[str(chart_profile_id)] = {"tii": tii, "tension_ratio": tension, "feels_like": feels}

    cards: dict[str, dict[str, Any]] = {}
    for user_id in user_ids:
        picked = chosen.get(user_id)
        if picked is None:
            cards[user_id] = dict(EMPTY_CARD)
            continue
        profile_id, name, handle, _ = picked
        cards[user_id] = {
            "profile_id": profile_id,
            "profile_name": name,
            "username": handle,
            "natal_summary": summaries.get(profile_id),
            "latest_transit": readings.get(profile_id),
        }
    return cards


def blocked_account_ids(session: Session, user_id: str) -> set[str]:
    """Every account on the other side of a block with this one, whichever of
    the two did the blocking."""
    rows = session.execute(
        select(UserBlockModel.blocker_id, UserBlockModel.blocked_id).where(
            or_(UserBlockModel.blocker_id == user_id, UserBlockModel.blocked_id == user_id)
        )
    ).all()
    return {blocked if blocker == user_id else blocker for blocker, blocked in rows}


def follow_ties(session: Session, user_id: str, others: set[str] | None = None) -> tuple[set[str], set[str]]:
    """The follows between one account and others, account to account: the
    accounts it follows (at least one chart they own) and the accounts that
    follow it (at least one chart it owns). With `others`, only among those;
    without, everyone on either side. What the chats' rule (`may_write`)
    reads, two queries for a whole listing."""
    candidates = None if others is None else {other for other in others if other and other != user_id}
    if candidates is not None and not candidates:
        return set(), set()

    follows = (
        select(ProfileModel.user_id)
        .join(ProfileFollowModel, ProfileFollowModel.profile_id == ProfileModel.id)
        .where(ProfileFollowModel.user_id == user_id, ProfileModel.user_id != user_id)
    )
    followed_by = (
        select(ProfileFollowModel.user_id)
        .join(ProfileModel, ProfileModel.id == ProfileFollowModel.profile_id)
        .where(ProfileModel.user_id == user_id, ProfileFollowModel.user_id != user_id)
    )
    if candidates is not None:
        follows = follows.where(ProfileModel.user_id.in_(candidates))
        followed_by = followed_by.where(ProfileFollowModel.user_id.in_(candidates))
    return (
        {owner for owner in session.execute(follows.distinct()).scalars() if owner},
        set(session.execute(followed_by.distinct()).scalars()),
    )


class SqlAlchemySocialRepository:
    def __init__(self, session_factory: sessionmaker[Session]):
        self.session_factory = session_factory

    # MARK: - Cards

    def _cards_for_users(self, session: Session, user_ids: set[str]) -> dict[str, dict[str, Any]]:
        return account_cards(session, user_ids)

    def _followed_profile_ids(self, session: Session, user_id: str, profile_ids: set[str]) -> set[str]:
        """Which of these profiles the account already follows — what decides
        whether a row offers "Follow back"."""
        if not profile_ids:
            return set()
        return set(
            session.execute(
                select(ProfileFollowModel.profile_id).where(
                    ProfileFollowModel.user_id == user_id,
                    ProfileFollowModel.profile_id.in_(profile_ids),
                )
            ).scalars()
        )

    def _blocked_ids(self, session: Session, user_id: str) -> set[str]:
        return blocked_account_ids(session, user_id)

    # MARK: - Likes

    def _profile_days(self, session: Session, profile_ids: list[str]) -> dict[str, date]:
        """Today for each profile, in the zone its readings are cast in: the
        place its last reading was for, else the zone it was born in."""
        if not profile_ids:
            return {}
        rows = session.execute(
            select(ProfileModel.id, ProfileModel.timezone, LatestTransitModel.timezone)
            .outerjoin(LatestTransitModel, LatestTransitModel.profile_id == ProfileModel.id)
            .where(ProfileModel.id.in_(profile_ids))
        ).all()
        return {profile_id: today_in(current or born) for profile_id, born, current in rows}

    def like_profile(
        self,
        user_id: str,
        profile_id: str,
        *,
        feels_like: str | None = None,
        tii: float | None = None,
    ) -> bool:
        """Likes the state on screen: this word, today. The same state twice
        changes nothing; a new word or a new day is a new state and a new like.

        True when this is the account's first like on the chart today: the
        one worth a push. A second state liked the same day is stored and
        shown in Activity, but the owner's phone has already heard."""
        state = feels_like or ""
        with self.session_factory() as session:
            ensure_user(session, user_id)
            day = self._profile_days(session, [profile_id]).get(profile_id, today_in(None))
            today = (
                session.execute(
                    select(ProfileLikeModel.feels_like).where(
                        ProfileLikeModel.user_id == user_id,
                        ProfileLikeModel.profile_id == profile_id,
                        ProfileLikeModel.day == day,
                    )
                )
                .scalars()
                .all()
            )
            if state in today:
                return False
            session.add(
                ProfileLikeModel(
                    user_id=user_id,
                    profile_id=profile_id,
                    day=day,
                    feels_like=state,
                    tii=tii,
                    created_at=_now_utc(),
                )
            )
            session.commit()
            return not today

    def unlike_profile(self, user_id: str, profile_id: str, *, feels_like: str | None = None) -> None:
        """Takes back the like on today's state. Without a word, every like
        this account gave the chart today. Earlier states keep theirs: they
        were liked while they were on screen."""
        with self.session_factory() as session:
            day = self._profile_days(session, [profile_id]).get(profile_id, today_in(None))
            conditions = [
                ProfileLikeModel.user_id == user_id,
                ProfileLikeModel.profile_id == profile_id,
                ProfileLikeModel.day == day,
            ]
            if feels_like is not None:
                conditions.append(ProfileLikeModel.feels_like == feels_like)
            session.execute(delete(ProfileLikeModel).where(and_(*conditions)))
            session.commit()

    def social_counts(self, profile_ids: list[str], viewer_user_id: str) -> dict[str, dict[str, Any]]:
        """The likes on every state each profile has had today, the states
        the viewer liked, all likes ever, followers, and how many charts the
        owner follows — for a whole listing in a handful of queries rather
        than a handful per card.

        `likes_total` is the number under the heart: every like the chart
        has had, from anyone but its owner, never reset by a new word or a
        new day. The owner cannot like their own charts; likes they gave one
        before that rule, or before it became theirs, are left out here
        rather than deleted.

        `my_state_likes` is what a client reads against the word it has on
        screen, to fill the heart. `state_likes`, `likes_count` and
        `is_liked` are today's, for builds that counted per state.

        `followers_count`, `following_count` and `likes_total` are None for
        everyone but the owner when the owner keeps them hidden
        (Settings > Community).

        `can_message` is whether the viewer can write to the chart: only a
        chart its owner marked as their own is a way to a person, only
        somebody else's, and only while the chats' rule lets the two of them
        write (`may_write`: they follow each other)."""
        ids = list(dict.fromkeys(profile_ids))
        counts: dict[str, dict[str, Any]] = {
            profile_id: {
                "likes_count": 0,
                "likes_total": 0,
                "likes_day": None,
                "state_likes": {},
                "my_state_likes": [],
                "followers_count": 0,
                "following_count": 0,
                "is_liked": False,
                "can_message": False,
            }
            for profile_id in ids
        }
        if not ids:
            return counts

        with self.session_factory() as session:
            days = self._profile_days(session, ids)
            for profile_id, day in days.items():
                counts[profile_id]["likes_day"] = day.isoformat()

            for profile_id, day, state, total in session.execute(
                select(
                    ProfileLikeModel.profile_id,
                    ProfileLikeModel.day,
                    ProfileLikeModel.feels_like,
                    func.count(),
                )
                .join(ProfileModel, ProfileModel.id == ProfileLikeModel.profile_id)
                .where(
                    ProfileLikeModel.profile_id.in_(ids),
                    ProfileLikeModel.user_id != ProfileModel.user_id,
                )
                .group_by(ProfileLikeModel.profile_id, ProfileLikeModel.day, ProfileLikeModel.feels_like)
            ).all():
                counts[profile_id]["likes_total"] += int(total)
                if days.get(profile_id) == day:
                    counts[profile_id]["likes_count"] += int(total)
                    counts[profile_id]["state_likes"][state or ""] = int(total)

            for profile_id, total in session.execute(
                select(ProfileFollowModel.profile_id, func.count())
                .where(ProfileFollowModel.profile_id.in_(ids))
                .group_by(ProfileFollowModel.profile_id)
            ).all():
                counts[profile_id]["followers_count"] = int(total)

            for profile_id, day, state in session.execute(
                select(ProfileLikeModel.profile_id, ProfileLikeModel.day, ProfileLikeModel.feels_like).where(
                    ProfileLikeModel.user_id == viewer_user_id,
                    ProfileLikeModel.profile_id.in_(ids),
                )
            ).all():
                if days.get(profile_id) == day:
                    counts[profile_id]["is_liked"] = True
                    counts[profile_id]["my_state_likes"].append(state or "")

            # Whose each chart is, whether that account keeps its numbers to
            # itself, and which of its charts it marked as its own.
            owners: dict[str, tuple[str, bool]] = {}
            own_charts: set[str] = set()
            for profile_id, owner_id, hidden, primary_id in session.execute(
                select(
                    ProfileModel.id,
                    ProfileModel.user_id,
                    UserModel.hide_social_counts,
                    UserModel.primary_profile_id,
                )
                .outerjoin(UserModel, UserModel.id == ProfileModel.user_id)
                .where(ProfileModel.id.in_(ids))
            ).all():
                owners[profile_id] = (owner_id, bool(hidden))
                if primary_id == profile_id and owner_id != viewer_user_id:
                    own_charts.add(profile_id)
            owner_ids = {owner_id for owner_id, _ in owners.values()}
            if own_charts:
                follows, followed_by = follow_ties(
                    session, viewer_user_id, {owners[profile_id][0] for profile_id in own_charts}
                )
                for profile_id in own_charts:
                    owner_id = owners[profile_id][0]
                    counts[profile_id]["can_message"] = may_write(owner_id in follows, owner_id in followed_by)
            # Following belongs to the account, not the chart: every chart the
            # owner follows, not counting any of its own.
            following: dict[str, int] = {}
            if owner_ids:
                for owner_id, total in session.execute(
                    select(ProfileFollowModel.user_id, func.count())
                    .join(ProfileModel, ProfileModel.id == ProfileFollowModel.profile_id)
                    .where(
                        ProfileFollowModel.user_id.in_(owner_ids),
                        ProfileModel.user_id != ProfileFollowModel.user_id,
                    )
                    .group_by(ProfileFollowModel.user_id)
                ).all():
                    following[owner_id] = int(total)

            for profile_id, (owner_id, hidden) in owners.items():
                counts[profile_id]["following_count"] = following.get(owner_id, 0)
                if hidden and owner_id != viewer_user_id:
                    counts[profile_id]["followers_count"] = None
                    counts[profile_id]["following_count"] = None
                    counts[profile_id]["likes_total"] = None

        return counts

    def followers_among(self, viewer_user_id: str, user_ids: set[str]) -> set[str]:
        """Which of these accounts follow at least one profile the viewer
        owns — "Follows you" for a whole listing in one query."""
        candidates = {user_id for user_id in user_ids if user_id and user_id != viewer_user_id}
        if not candidates:
            return set()
        with self.session_factory() as session:
            return set(
                session.execute(
                    select(ProfileFollowModel.user_id)
                    .join(ProfileModel, ProfileModel.id == ProfileFollowModel.profile_id)
                    .where(ProfileModel.user_id == viewer_user_id, ProfileFollowModel.user_id.in_(candidates))
                    .distinct()
                ).scalars()
            )

    def follows_viewer(self, owner_user_id: str, viewer_user_id: str) -> bool:
        """True when the owner of a profile follows any profile the viewer
        owns: what the app shows as "Follows you"."""
        if not owner_user_id or owner_user_id == viewer_user_id:
            return False
        with self.session_factory() as session:
            found = session.execute(
                select(ProfileFollowModel.id)
                .join(ProfileModel, ProfileModel.id == ProfileFollowModel.profile_id)
                .where(ProfileFollowModel.user_id == owner_user_id, ProfileModel.user_id == viewer_user_id)
                .limit(1)
            ).first()
            return found is not None

    # MARK: - Who is there

    def _people(
        self,
        model: type[ProfileLikeModel] | type[ProfileFollowModel],
        profile_id: str,
        viewer_user_id: str,
    ) -> list[dict[str, Any]]:
        with self.session_factory() as session:
            rows = session.execute(
                select(model.user_id, model.created_at)
                .where(model.profile_id == profile_id, model.user_id != viewer_user_id)
                .order_by(model.created_at.desc())
            ).all()
            blocked = self._blocked_ids(session, viewer_user_id)
            visible = [(user_id, created_at) for user_id, created_at in rows if user_id not in blocked]
            cards = self._cards_for_users(session, {user_id for user_id, _ in visible})
            followed = self._followed_profile_ids(
                session,
                viewer_user_id,
                {card["profile_id"] for card in cards.values() if card["profile_id"]},
            )
            return [
                {
                    "actor": cards[user_id],
                    "created_at": _stamp(created_at),
                    "actor_followed": cards[user_id]["profile_id"] in followed,
                }
                for user_id, created_at in visible
            ]

    def list_likers(self, profile_id: str, viewer_user_id: str) -> list[dict[str, Any]]:
        """Every like the chart has had, newest first, each with the day it
        was for and the word that day had — the same person once per day."""
        with self.session_factory() as session:
            rows = session.execute(
                select(
                    ProfileLikeModel.user_id,
                    ProfileLikeModel.created_at,
                    ProfileLikeModel.day,
                    ProfileLikeModel.feels_like,
                )
                .where(ProfileLikeModel.profile_id == profile_id, ProfileLikeModel.user_id != viewer_user_id)
                .order_by(ProfileLikeModel.created_at.desc())
                .limit(ACTIVITY_LIMIT * 2)
            ).all()
            blocked = self._blocked_ids(session, viewer_user_id)
            rows = [row for row in rows if row[0] not in blocked]
            cards = self._cards_for_users(session, {row[0] for row in rows})
            followed = self._followed_profile_ids(
                session,
                viewer_user_id,
                {card["profile_id"] for card in cards.values() if card["profile_id"]},
            )
            return [
                {
                    "actor": cards[user_id],
                    "created_at": _stamp(created_at),
                    "actor_followed": cards[user_id]["profile_id"] in followed,
                    "day": day.isoformat() if day else None,
                    "feels_like": feels_like or None,
                }
                for user_id, created_at, day, feels_like in rows
            ]

    def list_followers(self, profile_id: str, viewer_user_id: str) -> list[dict[str, Any]]:
        return self._people(ProfileFollowModel, profile_id, viewer_user_id)

    # MARK: - Activity

    def list_activity(self, user_id: str, *, limit: int = ACTIVITY_LIMIT) -> dict[str, Any]:
        """Likes and follows on the profiles this account owns, newest first,
        each marked read or unread against when Activity was last opened."""
        with self.session_factory() as session:
            user = session.get(UserModel, user_id)
            seen_at = _aware(user.activity_seen_at) if user is not None else None
            blocked = self._blocked_ids(session, user_id)

            # (kind, row id, actor, profile, when, day liked, word that day).
            # The chart each one was on is already joined in to find the
            # owner's, so its name and handle come along with the row.
            events: list[tuple[str, int, str, str, datetime, date | None, str | None]] = []
            targets: dict[str, tuple[str | None, str | None]] = {}
            for (
                row_id,
                actor_id,
                profile_id,
                created_at,
                day,
                feels_like,
                target_name,
                target_handle,
            ) in session.execute(
                select(
                    ProfileLikeModel.id,
                    ProfileLikeModel.user_id,
                    ProfileLikeModel.profile_id,
                    ProfileLikeModel.created_at,
                    ProfileLikeModel.day,
                    ProfileLikeModel.feels_like,
                    ProfileModel.display_name,
                    ProfileModel.handle,
                )
                .join(ProfileModel, ProfileModel.id == ProfileLikeModel.profile_id)
                .where(ProfileModel.user_id == user_id, ProfileLikeModel.user_id != user_id)
                .order_by(ProfileLikeModel.created_at.desc())
                .limit(limit)
            ).all():
                if actor_id not in blocked:
                    targets[profile_id] = (target_name, target_handle)
                    events.append(
                        ("like", row_id, actor_id, profile_id, _aware(created_at) or _now_utc(), day, feels_like)
                    )
            for row_id, actor_id, profile_id, created_at, target_name, target_handle in session.execute(
                select(
                    ProfileFollowModel.id,
                    ProfileFollowModel.user_id,
                    ProfileFollowModel.profile_id,
                    ProfileFollowModel.created_at,
                    ProfileModel.display_name,
                    ProfileModel.handle,
                )
                .join(ProfileModel, ProfileModel.id == ProfileFollowModel.profile_id)
                .where(ProfileModel.user_id == user_id, ProfileFollowModel.user_id != user_id)
                .order_by(ProfileFollowModel.created_at.desc())
                .limit(limit)
            ).all():
                if actor_id not in blocked:
                    targets[profile_id] = (target_name, target_handle)
                    events.append(
                        ("follow", row_id, actor_id, profile_id, _aware(created_at) or _now_utc(), None, None)
                    )

            events.sort(key=lambda event: event[4], reverse=True)
            events = events[:limit]

            cards = self._cards_for_users(session, {event[2] for event in events})
            followed = self._followed_profile_ids(
                session,
                user_id,
                {card["profile_id"] for card in cards.values() if card["profile_id"]},
            )

            items = []
            for kind, row_id, actor_id, profile_id, created_at, liked_day, liked_word in events:
                name, handle = targets.get(profile_id, (None, None))
                items.append(
                    {
                        "id": f"{kind}:{row_id}",
                        "kind": kind,
                        "created_at": _isoformat_z(created_at),
                        "is_unread": seen_at is None or created_at > seen_at,
                        "actor": cards[actor_id],
                        "actor_followed": cards[actor_id]["profile_id"] in followed,
                        "target": {"profile_id": profile_id, "profile_name": name, "username": handle},
                        "day": liked_day.isoformat() if liked_day else None,
                        "feels_like": liked_word or None,
                    }
                )

            return {
                "items": items,
                "unread_count": self._unread_count(session, user_id),
                "seen_at": _isoformat_z(seen_at) if seen_at else None,
            }

    def _unread_count(self, session: Session, user_id: str) -> int:
        """Likes and follows on the account's charts since Activity was last
        opened, less anyone across a block. One query, the read marker and
        the blocks asked inside it: the badge asks on every return to the
        app, and each query is a round trip to the database."""
        seen_at = select(UserModel.activity_seen_at).where(UserModel.id == user_id).scalar_subquery()
        blocked = union(
            select(UserBlockModel.blocked_id).where(UserBlockModel.blocker_id == user_id),
            select(UserBlockModel.blocker_id).where(UserBlockModel.blocked_id == user_id),
        )
        events = union_all(
            *(
                select(model.id)
                .join(ProfileModel, ProfileModel.id == model.profile_id)
                .where(
                    ProfileModel.user_id == user_id,
                    model.user_id != user_id,
                    model.user_id.not_in(blocked),
                    or_(seen_at.is_(None), model.created_at > seen_at),
                )
                for model in (ProfileLikeModel, ProfileFollowModel)
            )
        ).subquery()
        return int(session.execute(select(func.count()).select_from(events)).scalar_one())

    def unread_activity_count(self, user_id: str) -> int:
        with self.session_factory() as session:
            return self._unread_count(session, user_id)

    def mark_activity_seen(self, user_id: str) -> None:
        with self.session_factory() as session:
            user = ensure_user(session, user_id)
            user.activity_seen_at = _now_utc()
            session.commit()

    # MARK: - Settings

    def social_settings(self, user_id: str) -> dict[str, bool]:
        """What this account shows other people about itself — whether its
        charts carry their followers and following counts — and which of
        their likes and follows are pushed to its phones."""
        with self.session_factory() as session:
            return self._settings_of(session.get(UserModel, user_id))

    @staticmethod
    def _settings_of(user: UserModel | None) -> dict[str, bool]:
        if user is None:
            return {"show_counts": True, "push_likes": True, "push_follows": True, "push_messages": True}
        return {
            "show_counts": not user.hide_social_counts,
            "push_likes": bool(user.push_likes),
            "push_follows": bool(user.push_follows),
            "push_messages": bool(user.push_messages),
        }

    def update_social_settings(
        self,
        user_id: str,
        *,
        show_counts: bool | None = None,
        push_likes: bool | None = None,
        push_follows: bool | None = None,
        push_messages: bool | None = None,
    ) -> dict[str, bool]:
        """Changes what is given and leaves the rest as it was."""
        with self.session_factory() as session:
            user = ensure_user(session, user_id)
            if show_counts is not None:
                user.hide_social_counts = not show_counts
            if push_likes is not None:
                user.push_likes = push_likes
            if push_follows is not None:
                user.push_follows = push_follows
            if push_messages is not None:
                user.push_messages = push_messages
            session.commit()
            return self._settings_of(user)

    # MARK: - Devices

    def card_for(self, user_id: str) -> dict[str, Any]:
        """One account's card: how a push names the person who acted."""
        with self.session_factory() as session:
            return self._cards_for_users(session, {user_id})[user_id]

    def register_device(self, user_id: str, token: str, *, environment: str, lang: str) -> None:
        """Records the phone a push for this account goes to. A token that
        belonged to another account moves over: whoever is signed in on the
        phone now is whose news it shows."""
        now = _now_utc()
        with self.session_factory() as session:
            ensure_user(session, user_id)
            device = session.get(DeviceTokenModel, token)
            if device is None:
                session.add(
                    DeviceTokenModel(
                        token=token,
                        user_id=user_id,
                        environment=environment,
                        lang=lang,
                        created_at=now,
                        updated_at=now,
                    )
                )
            else:
                device.user_id = user_id
                device.environment = environment
                device.lang = lang
                device.updated_at = now
            session.commit()

    def unregister_device(self, user_id: str, token: str) -> None:
        """Forgets a phone on sign-out. Only the account's own: a token
        another account has since taken over stays with it."""
        with self.session_factory() as session:
            session.execute(
                delete(DeviceTokenModel).where(DeviceTokenModel.token == token, DeviceTokenModel.user_id == user_id)
            )
            session.commit()

    def devices_for(self, user_id: str) -> list[dict[str, str]]:
        with self.session_factory() as session:
            return [
                {"token": token, "environment": environment, "lang": lang}
                for token, environment, lang in session.execute(
                    select(DeviceTokenModel.token, DeviceTokenModel.environment, DeviceTokenModel.lang).where(
                        DeviceTokenModel.user_id == user_id
                    )
                ).all()
            ]

    def drop_device(self, token: str) -> None:
        """Forgets a token APNs no longer takes: the app was deleted, or the
        phone gave the install a new one."""
        with self.session_factory() as session:
            session.execute(delete(DeviceTokenModel).where(DeviceTokenModel.token == token))
            session.commit()

    # MARK: - Blocks

    def block_user(self, blocker_id: str, blocked_id: str) -> None:
        """Blocks an account, and severs what already ran between the two:
        every follow and like either way, on every profile either owns."""
        with self.session_factory() as session:
            ensure_user(session, blocker_id)
            ensure_user(session, blocked_id)
            existing = session.execute(
                select(UserBlockModel).where(
                    UserBlockModel.blocker_id == blocker_id,
                    UserBlockModel.blocked_id == blocked_id,
                )
            ).scalar_one_or_none()
            if existing is None:
                session.add(UserBlockModel(blocker_id=blocker_id, blocked_id=blocked_id, created_at=_now_utc()))

            for actor, owner in ((blocker_id, blocked_id), (blocked_id, blocker_id)):
                owned = select(ProfileModel.id).where(ProfileModel.user_id == owner)
                for model in (ProfileFollowModel, ProfileLikeModel):
                    session.execute(delete(model).where(model.user_id == actor, model.profile_id.in_(owned)))
            session.commit()

    def unblock(self, blocker_id: str, block_id: int) -> bool:
        """Lifts one of this account's own blocks. False when there is no such
        block, or it is somebody else's."""
        with self.session_factory() as session:
            block = session.get(UserBlockModel, block_id)
            if block is None or block.blocker_id != blocker_id:
                return False
            session.delete(block)
            session.commit()
            return True

    def list_blocks(self, blocker_id: str) -> list[dict[str, Any]]:
        with self.session_factory() as session:
            rows = session.execute(
                select(UserBlockModel.id, UserBlockModel.blocked_id, UserBlockModel.created_at)
                .where(UserBlockModel.blocker_id == blocker_id)
                .order_by(UserBlockModel.created_at.desc())
            ).all()
            cards = self._cards_for_users(session, {blocked for _, blocked, _ in rows})
            return [
                {"block_id": block_id, "created_at": _stamp(created_at), "actor": cards[blocked]}
                for block_id, blocked, created_at in rows
            ]

    def blocked_user_ids(self, user_id: str) -> set[str]:
        with self.session_factory() as session:
            return self._blocked_ids(session, user_id)

    def blocker_of(self, viewer_id: str, other_id: str) -> str | None:
        """Who blocked whom between two accounts: the viewer's id when the
        viewer did, the other's when the viewer is the one blocked, None when
        neither."""
        with self.session_factory() as session:
            rows = (
                session.execute(
                    select(UserBlockModel.blocker_id).where(
                        or_(
                            and_(UserBlockModel.blocker_id == viewer_id, UserBlockModel.blocked_id == other_id),
                            and_(UserBlockModel.blocker_id == other_id, UserBlockModel.blocked_id == viewer_id),
                        )
                    )
                )
                .scalars()
                .all()
            )
            if viewer_id in rows:
                return viewer_id
            return other_id if rows else None

    # MARK: - Reports

    def create_report(
        self,
        reporter_id: str,
        profile: dict[str, Any],
        *,
        reason: str,
        details: str | None,
    ) -> dict[str, Any]:
        now = _now_utc()
        with self.session_factory() as session:
            ensure_user(session, reporter_id)
            report = ProfileReportModel(
                reporter_id=reporter_id,
                profile_id=str(profile["profile_id"]),
                reported_user_id=profile.get("user_id"),
                profile_name=profile.get("profile_name"),
                profile_handle=profile.get("username"),
                reason=reason,
                details=details,
                status="open",
                created_at=now,
            )
            session.add(report)
            session.commit()
            return {
                "report_id": report.id,
                "profile_id": report.profile_id,
                "reason": reason,
                "created_at": _isoformat_z(now),
            }


class FileSocialRepository:
    """The same layer for file persistence, which is local development only.

    One JSON file holds likes, blocks, reports, read markers and settings.
    Follows keep their own file and carry no timestamps there, so Activity in
    this mode shows likes alone — enough to work on the screens without a
    database.
    """

    def __init__(self, profiles: Any, path: Path | None = None):
        # The file profile repository: it owns the follows file and the
        # profiles, and this reads both through it rather than twice over.
        self.profiles = profiles
        self.path = path or Path("profiles/_social.json")

    def _load(self) -> dict[str, Any]:
        if self.path.exists():
            try:
                data: dict[str, Any] = json.loads(self.path.read_text(encoding="utf-8"))
                return data
            except (json.JSONDecodeError, OSError):
                pass
        return {"likes": [], "blocks": [], "reports": [], "seen": {}, "settings": {}, "next_id": 1}

    def _save(self, data: dict[str, Any]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(data, indent=2), encoding="utf-8")

    def _next_id(self, data: dict[str, Any]) -> int:
        value = int(data.get("next_id", 1))
        data["next_id"] = value + 1
        return value

    def _owner(self, profile_id: str) -> str | None:
        owner: str | None = self.profiles.get_owner_user_id(profile_id)
        return owner

    def _card(self, user_id: str) -> dict[str, Any]:
        owned = self.profiles.list_summaries(user_id=user_id)
        if not owned:
            return dict(EMPTY_CARD)
        first = owned[0]
        return {
            "profile_id": first.get("profile_id"),
            "profile_name": first.get("profile_name"),
            "username": first.get("username"),
            "natal_summary": first.get("natal_summary"),
            "latest_transit": first.get("latest_transit"),
        }

    # Local development counts a day in UTC: the file store keeps no zone for
    # the place a profile was last read for.

    def like_profile(
        self,
        user_id: str,
        profile_id: str,
        *,
        feels_like: str | None = None,
        tii: float | None = None,
    ) -> bool:
        data = self._load()
        day = today_in(None).isoformat()
        state = feels_like or ""
        today = [
            like.get("feels_like") or ""
            for like in data["likes"]
            if like["user_id"] == user_id and like["profile_id"] == profile_id and like.get("day") == day
        ]
        if state in today:
            return False
        data["likes"].append(
            {
                "id": self._next_id(data),
                "user_id": user_id,
                "profile_id": profile_id,
                "day": day,
                "feels_like": state,
                "tii": tii,
                "created_at": _isoformat_z(_now_utc()),
            }
        )
        self._save(data)
        return not today

    def unlike_profile(self, user_id: str, profile_id: str, *, feels_like: str | None = None) -> None:
        data = self._load()
        day = today_in(None).isoformat()
        data["likes"] = [
            like
            for like in data["likes"]
            if not (
                like["user_id"] == user_id
                and like["profile_id"] == profile_id
                and like.get("day") == day
                and (feels_like is None or (like.get("feels_like") or "") == feels_like)
            )
        ]
        self._save(data)

    def social_counts(self, profile_ids: list[str], viewer_user_id: str) -> dict[str, dict[str, Any]]:
        data = self._load()
        likes = data["likes"]
        day = today_in(None).isoformat()
        counts: dict[str, dict[str, Any]] = {}
        for profile_id in dict.fromkeys(profile_ids):
            owner = self._owner(profile_id)
            # The owner's own likes, from before they could not give them,
            # count nowhere: the same rule as the database's.
            received = [like for like in likes if like["profile_id"] == profile_id and like["user_id"] != owner]
            todays = [like for like in received if like.get("day") == day]
            states: dict[str, int] = {}
            for like in todays:
                states[like.get("feels_like") or ""] = states.get(like.get("feels_like") or "", 0) + 1
            mine = [
                like.get("feels_like") or ""
                for like in likes
                if like["profile_id"] == profile_id and like.get("day") == day and like["user_id"] == viewer_user_id
            ]
            hidden = owner != viewer_user_id and self._hides_counts(data, owner)
            counts[profile_id] = {
                "likes_count": len(todays),
                "likes_total": None if hidden else len(received),
                "likes_day": day,
                "state_likes": states,
                "my_state_likes": mine,
                "followers_count": None if hidden else self.profiles.count_followers(profile_id),
                "following_count": None if hidden or owner is None else self.profiles.count_following(owner),
                "is_liked": bool(mine),
                # The first chart stands in for a primary here, as in `card`.
                "can_message": owner is not None
                and owner != viewer_user_id
                and self._card(owner)["profile_id"] == profile_id
                and may_write(self.follows_viewer(viewer_user_id, owner), self.follows_viewer(owner, viewer_user_id)),
            }
        return counts

    @staticmethod
    def _hides_counts(data: dict[str, Any], user_id: str | None) -> bool:
        if user_id is None:
            return False
        return bool(data.get("settings", {}).get(user_id, {}).get("hide_counts"))

    def followers_among(self, viewer_user_id: str, user_ids: set[str]) -> set[str]:
        return {user_id for user_id in user_ids if self.follows_viewer(user_id, viewer_user_id)}

    def follows_viewer(self, owner_user_id: str, viewer_user_id: str) -> bool:
        if not owner_user_id or owner_user_id == viewer_user_id:
            return False
        own_ids = {s.get("profile_id") for s in self.profiles.list_summaries(user_id=viewer_user_id)}
        return any(self.profiles.is_following(owner_user_id, profile_id) for profile_id in own_ids)

    def list_likers(self, profile_id: str, viewer_user_id: str) -> list[dict[str, Any]]:
        blocked = self.blocked_user_ids(viewer_user_id)
        likes = [
            like
            for like in reversed(self._load()["likes"])
            if like["profile_id"] == profile_id and like["user_id"] != viewer_user_id and like["user_id"] not in blocked
        ]
        return [
            {
                "actor": (card := self._card(like["user_id"])),
                "created_at": like["created_at"],
                "actor_followed": bool(card["profile_id"])
                and self.profiles.is_following(viewer_user_id, card["profile_id"]),
                "day": like.get("day"),
                "feels_like": like.get("feels_like") or None,
            }
            for like in likes
        ]

    def list_followers(self, profile_id: str, viewer_user_id: str) -> list[dict[str, Any]]:
        # The follows file carries no timestamps and no reverse index; local
        # development does not need the list badly enough to build one.
        del profile_id, viewer_user_id
        return []

    def list_activity(self, user_id: str, *, limit: int = ACTIVITY_LIMIT) -> dict[str, Any]:
        data = self._load()
        seen_at = data["seen"].get(user_id)
        blocked = self.blocked_user_ids(user_id)
        items = []
        for like in reversed(data["likes"]):
            if like["user_id"] == user_id or like["user_id"] in blocked:
                continue
            if self._owner(like["profile_id"]) != user_id:
                continue
            card = self._card(like["user_id"])
            try:
                target = self.profiles.load_profile(like["profile_id"])
            except FileNotFoundError:
                continue
            items.append(
                {
                    "id": f"like:{like['id']}",
                    "kind": "like",
                    "created_at": like["created_at"],
                    "is_unread": seen_at is None or like["created_at"] > seen_at,
                    "actor": card,
                    "actor_followed": bool(card["profile_id"])
                    and self.profiles.is_following(user_id, card["profile_id"]),
                    "target": {
                        "profile_id": like["profile_id"],
                        "profile_name": target.get("profile_name"),
                        "username": target.get("username"),
                    },
                    "day": like.get("day"),
                    "feels_like": like.get("feels_like") or None,
                }
            )
        items = items[:limit]
        return {
            "items": items,
            "unread_count": sum(1 for item in items if item["is_unread"]),
            "seen_at": seen_at,
        }

    def unread_activity_count(self, user_id: str) -> int:
        count: int = self.list_activity(user_id)["unread_count"]
        return count

    def mark_activity_seen(self, user_id: str) -> None:
        data = self._load()
        data["seen"][user_id] = _isoformat_z(_now_utc())
        self._save(data)

    def social_settings(self, user_id: str) -> dict[str, bool]:
        mine = self._load().get("settings", {}).get(user_id, {})
        return {
            "show_counts": not mine.get("hide_counts", False),
            "push_likes": mine.get("push_likes", True),
            "push_follows": mine.get("push_follows", True),
            "push_messages": mine.get("push_messages", True),
        }

    def update_social_settings(
        self,
        user_id: str,
        *,
        show_counts: bool | None = None,
        push_likes: bool | None = None,
        push_follows: bool | None = None,
        push_messages: bool | None = None,
    ) -> dict[str, bool]:
        data = self._load()
        mine = data.setdefault("settings", {}).setdefault(user_id, {})
        if show_counts is not None:
            mine["hide_counts"] = not show_counts
        if push_likes is not None:
            mine["push_likes"] = push_likes
        if push_follows is not None:
            mine["push_follows"] = push_follows
        if push_messages is not None:
            mine["push_messages"] = push_messages
        self._save(data)
        return self.social_settings(user_id)

    def card_for(self, user_id: str) -> dict[str, Any]:
        return self._card(user_id)

    def register_device(self, user_id: str, token: str, *, environment: str, lang: str) -> None:
        data = self._load()
        data.setdefault("devices", {})[token] = {"user_id": user_id, "environment": environment, "lang": lang}
        self._save(data)

    def unregister_device(self, user_id: str, token: str) -> None:
        data = self._load()
        devices = data.setdefault("devices", {})
        if devices.get(token, {}).get("user_id") == user_id:
            del devices[token]
            self._save(data)

    def devices_for(self, user_id: str) -> list[dict[str, str]]:
        return [
            {"token": token, "environment": device["environment"], "lang": device["lang"]}
            for token, device in self._load().get("devices", {}).items()
            if device.get("user_id") == user_id
        ]

    def drop_device(self, token: str) -> None:
        data = self._load()
        if data.setdefault("devices", {}).pop(token, None) is not None:
            self._save(data)

    def block_user(self, blocker_id: str, blocked_id: str) -> None:
        data = self._load()
        if not any(b["blocker_id"] == blocker_id and b["blocked_id"] == blocked_id for b in data["blocks"]):
            data["blocks"].append(
                {
                    "id": self._next_id(data),
                    "blocker_id": blocker_id,
                    "blocked_id": blocked_id,
                    "created_at": _isoformat_z(_now_utc()),
                }
            )
        pair = {blocker_id, blocked_id}
        data["likes"] = [
            like
            for like in data["likes"]
            if not (like["user_id"] in pair and self._owner(like["profile_id"]) in pair - {like["user_id"]})
        ]
        self._save(data)
        for actor, owner in ((blocker_id, blocked_id), (blocked_id, blocker_id)):
            for summary in self.profiles.list_summaries(user_id=owner):
                self.profiles.unfollow_profile(actor, summary["profile_id"])

    def unblock(self, blocker_id: str, block_id: int) -> bool:
        data = self._load()
        kept = [b for b in data["blocks"] if not (b["id"] == block_id and b["blocker_id"] == blocker_id)]
        if len(kept) == len(data["blocks"]):
            return False
        data["blocks"] = kept
        self._save(data)
        return True

    def list_blocks(self, blocker_id: str) -> list[dict[str, Any]]:
        return [
            {"block_id": b["id"], "created_at": b["created_at"], "actor": self._card(b["blocked_id"])}
            for b in reversed(self._load()["blocks"])
            if b["blocker_id"] == blocker_id
        ]

    def blocked_user_ids(self, user_id: str) -> set[str]:
        ids: set[str] = set()
        for b in self._load()["blocks"]:
            if b["blocker_id"] == user_id:
                ids.add(b["blocked_id"])
            elif b["blocked_id"] == user_id:
                ids.add(b["blocker_id"])
        return ids

    def blocker_of(self, viewer_id: str, other_id: str) -> str | None:
        blocks = self._load()["blocks"]
        if any(b["blocker_id"] == viewer_id and b["blocked_id"] == other_id for b in blocks):
            return viewer_id
        if any(b["blocker_id"] == other_id and b["blocked_id"] == viewer_id for b in blocks):
            return other_id
        return None

    def create_report(
        self,
        reporter_id: str,
        profile: dict[str, Any],
        *,
        reason: str,
        details: str | None,
    ) -> dict[str, Any]:
        data = self._load()
        report = {
            "report_id": self._next_id(data),
            "reporter_id": reporter_id,
            "profile_id": str(profile["profile_id"]),
            "reported_user_id": profile.get("user_id"),
            "profile_name": profile.get("profile_name"),
            "profile_handle": profile.get("username"),
            "reason": reason,
            "details": details,
            "status": "open",
            "created_at": _isoformat_z(_now_utc()),
        }
        data["reports"].append(report)
        self._save(data)
        return {key: report[key] for key in ("report_id", "profile_id", "reason", "created_at")}
