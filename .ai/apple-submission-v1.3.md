# App Store submission 1.3: the social network

**Status:** DRAFT. Nothing sent to Apple. Prepared 2026-09-27.

**Why this version exists.** The App Review appointment (Sept 21, 2026) said it
plainly: the app claimed Social Networking in its category, subtitle and review
notes, but nothing in it let one person do anything to another. "Social network
is not saturated. On the other hand, astrology is." This version makes the
social network real (likes, Activity, followers and following, report, block)
and the texts below describe only what the build does.

**How it is submitted.** As an update to the existing record, per the call:
the rejected 1.1 version record is edited (version string 1.1 -> 1.3, build
17 attached), not a new app and not an appeal.

Every text meant for Apple uses ASCII punctuation only.

---

## Order of operations (each needs the owner's go)

1. **Deploy the backend** (push the branch; it auto-merges and Railway runs
   migrations `20260927_000001`, three new tables and one nullable column, and
   `20260927_000002`, one boolean with a default, additive only). The app talks
   to production, so this goes first.
2. **Seed the demo account** (hi@srgplus.com) on production, from real
   accounts the owner controls: follow it and like its chart from two or three
   of them, and have it follow them back. The reviewer must open Activity and
   see real rows, see real follower and following counts under the charts, and
   find "Follows you" in the Following list. One of them also writes to it,
   so Chats has a conversation to open.
3. **A 1.3 build after 18** archived and uploaded to TestFlight. Build 18
   predates the chat word filter's "not sent" line: on it a refused message
   reads "Not sent. Tap to try again", and trying again fails the same way.
4. **App Store Connect**: version string, build, texts, age rating,
   screenshots, review notes, all below.
5. **Submit for review.**

Also, before submitting:
- The moderation inbox is **big3meapp@gmail.com** (`ASTRO_CONSUL_MODERATION_EMAIL`),
  the same address the Terms, the support page and Settings publish: all user
  mail lands there. It must be watched: the Terms and the review notes promise
  a 24-hour response to reports. Report mails come from noreply@big3.me with
  Reply-To set to the reporter.
- **App Privacy** in App Store Connect. Web UI only, no public API, so a
  session does it in the owner's logged-in Chrome (Claude in Chrome), with his
  go before pressing Publish: App Store Connect → big3.me → App Privacy →
  Edit. Add data type **Other User Content** (profile display names and
  @handles shown to other members): Linked to the user: Yes; Used for
  tracking: No; Purpose: App Functionality. Add **Emails or Text Messages**
  (the text of chat messages, stored so both people can read them) the same
  way: linked, not tracking, App Functionality. Check that **Email Address** and
  **User ID** are declared the same way (linked, not tracking, App
  Functionality), and that **Other Data Types / sensitive** is not needed:
  birth date, time and place are entered for charts, declare them under
  "Other Data" if the questionnaire asks, linked, App Functionality. Then
  Publish.

---

## Version

| Field | Value |
|---|---|
| Version string | 1.3 |
| Build | 17 |
| Category | Social Networking (already set) |
| Subtitle | Birth Chart Social Network (unchanged, now true) |

What's New is not shown for an app that has never been released, so there is
nothing to fill.

## Promotional text (146 of 170)

```
Follow friends, see how their sky changes and like it when it does. Find out who follows and likes your chart. Free, with nothing sold in the app.
```

## Keywords (90 of 100)

```
social,friends,follow,likes,birth chart,compatibility,compare,community,transits,ephemeris
```

## Description

```
big3.me is a social network built on birth charts. Follow your friends and family, see how their sky changes, like it when it does, and find out who follows and likes yours.

FOLLOW PEOPLE
• Find people by name or @handle and follow their charts
• Swipe between everyone you follow, each with their sky today
• See who follows you back

LIKES AND ACTIVITY
• Like a friend's sky. Every time their state changes it is new, and you can like it again
• Activity shows who liked your chart and who started following you
• Follow back right from Activity

COMPARE TWO CHARTS
• Compatibility between you and anyone you follow, or between two friends
• A score in four areas, with every aspect between the two charts listed by strength

YOUR DAY IN TWO NUMBERS
• Intensity from 0 to 100 and tension as the share of hard aspects, with the formula explained in the app
• A 10-day outlook of the same measurements
• Active transits with the exact moment each one peaks
• A glossary on every screen that explains what you are looking at

SAFE BY DESIGN
• Report any profile and block anyone. Blocked accounts are listed in Settings
• Choose whether others see how many follow you and how many you follow
• Names that break the community rules are refused
• Every report is reviewed within 24 hours

REAL COMPUTATION
Every position is computed with the Swiss Ephemeris, the astronomical engine behind professional software, for the exact time and place of birth.

big3.me is free. Nothing is sold in the app.
```

## Age rating

The questionnaire's social media questions became mandatory in September 2026.

| Question | Answer | Why |
|---|---|---|
| Social media (`socialMedia`) | Yes | People discover, follow and like each other's charts |
| Social media age restricted (`socialMediaAgeRestricted`) | No | No age gate in the app; the rating does the work |
| User-generated content (`userGeneratedContent`) | Yes | Profile names, handles and chat messages are shown to other members |
| Messaging and chat | Yes | Members write to each other in Chats (text only) |

Result: 13+, with the Social Media descriptor. Sign-in already says
"big3.me is for people 13 and older".

## Review notes (paste as is)

```
Thank you for the App Review appointment in September. The reviewer pointed out that we described big3.me as a social networking app while the build had no interaction between people. This version makes the social network real, and everything below can be checked in a few minutes with the demo account.

SIGN IN
On the first screen tap "Sign in with password" (the default path emails a one-time code), then use the demo account from App Review Information.

WHAT TO CHECK
1. Activity: the bell at the top left of every page. Who liked your chart and who started following you, with "Follow back" on each row. A switch filters it by chart when you keep more than one.
2. Likes: the heart on the right under every chart. A like is for the state of that person's sky right now (the word under the numbers, for example "Expansive"). When their state changes it is new content and can be liked again. The owner sees each like in Activity, with the state that was liked.
3. Following: one follow button under every chart that is not yours: "Follow", "Follow back" when that person already follows you, and "Following" once you do, which asks before unfollowing. Beside it, how many follow the chart and how many its owner follows. Under your own chart the two counts open Followers and Following, and Settings > Community can hide them from others.
4. Find people: the magnifying glass at the bottom left. Search by name or @handle, open a preview, tap Follow.
5. Compatibility: at the bottom of any page, compare two charts, yours and a friend's or two friends'.
6. Chats: the button beside the bell. Write to anyone who has marked a chart as their own, from "Message" under their chart or "New Message" in Chats. Delivered and Seen show under your last message, and a push arrives when someone writes.

SAFETY (guideline 1.2)
- Report: the "..." menu on any chart you do not own, and on search previews. Reports reach our moderation inbox and are reviewed within 24 hours.
- Block: the same menus. A block removes all follows and likes between the two accounts, hides each from the other's search, and is not announced. Settings > Community > Blocked accounts lists them, with Unblock.
- Objectionable words are refused in profile names and handles, and in chat messages: such a message is not sent, and only its sender sees why.
- In a chat, Report and Block sit in the menu under the other person's face. A block closes the chat for both sides.
- The Terms, including community rules with zero tolerance for objectionable content and abusive users, are accepted at sign-in: https://big3.me/legal#community
- Contact: Settings > Community > Contact support (big3meapp@gmail.com), and https://big3.me/support

WHAT IS DIFFERENT
- People, not content: you follow people and swipe between them, each a page with their sky today, and you react when a friend's state changes.
- Two measured numbers per day, intensity from 0 to 100 and tension as the share of hard aspects, from a formula explained in the app's glossary. The app describes the sky, not your future: it names no events, people or decisions.
- Orbs to a hundredth of a degree in four strength bands, applying and separating, and the exact peak time of each transit.
- A glossary at the end of every detail sheet that defines each term on it.
- Every position computed with the Swiss Ephemeris for the exact time and place of birth.

BUSINESS MODEL
The iOS app is entirely free. Nothing is sold in the app, no content is locked, and there are no links to outside purchases. A subscription on our website unlocks nothing in the iOS app: every account sees the same app.
```

## Screenshots (iPhone 6.9", 1320 x 2868)

Taken from the real app against a local backend seeded with invented people
(no real names: a real person's name in a screenshot is theirs to lend), with
the status bar set to 9:41, full battery.

1. A friend's page: the sky, the two numbers, followers and following, "Following", the heart. Caption: "Follow the people you care about"
2. Activity: who liked and who followed. Caption: "See who liked your sky"
3. Your own page with the bell's count: Caption: "Your chart, your day in two numbers"
4. Find people: search results. Caption: "Find friends by name or @handle"
5. Compatibility report between two charts. Caption: "Compare any two charts"
6. Followers and Following. Caption: "See who follows you"

The April screenshots (old web UI) are deleted from the version.

## Subscriptions

`me.big3.pro.monthly` and `.annual` stay in MISSING_METADATA and are **not**
attached to this version: the iOS app sells nothing, and the review notes say
so. Nothing to do.
