# App Store submission v1.2 — draft texts for review

**Status:** DRAFT, nothing sent to Apple. Prepared 2026-09-06.
**Build:** 6 (marketing 1.2), uploaded 2026-09-06, VALID in ASC.
**Version record 1.2 does not exist in ASC yet.** 1.1 is REJECTED, and the
review submission from Apr 13 is still open in state UNRESOLVED_ISSUES.

Code fixes that must ship before the texts below are true:
1. The in-app web view must serve the free tier to everyone and never open the
   paywall (section 5).
2. Account deletion must be native, not a trip through the web view (section 5).

---

## 1. App Review Information → Notes

> big3.me is a social networking app built around birth charts. People follow
> each other, look at each other's profiles, and compare charts.
>
> **What changed since the previous submission (April 2026)**
>
> The app has been rebuilt. The previous binary was a web view wrapper. This
> build is a native SwiftUI application: the root view controller hosts native
> SwiftUI, and the main experience (home, profile list, profile search, profile
> editing, the chart wheel, settings and notifications) is native code. A few
> secondary screens still load our web app inside the app while we finish
> migrating them.
>
> What is new, specifically:
>
> 1. Rebuilt natively in SwiftUI. New navigation, new layout, new interaction
>    model. None of the previous submission's screens survive unchanged.
> 2. All descriptive interpretation text has been removed from iOS. The app
>    presents computed values only: positions, aspects, orbs, the window an
>    aspect runs over, a 0 to 100 daily score and a "feels like" category.
>    There is no pre-written interpretive text of any kind in this build.
> 3. A new presentation modelled on a weather app: one page per profile, swipe
>    between the people you follow, each page showing that person's reading for
>    the day.
> 4. Native notifications. The device is notified when a profile's daily
>    category changes. One reading per local noon, on by default, time
>    configurable in Settings.
> 5. A new native chart wheel drawn in SwiftUI, with a picker between the birth
>    aspect grid and the transit-to-natal grid, and tappable aspects.
> 6. New profile search and discovery, and profile transfer to another person
>    by email.
>
> **How it works**
>
> Every value is computed server side in real time with Swiss Ephemeris, the
> same ephemeris used in professional and academic software. Nothing is served
> from stored or pre-written content. The house system, orb limits and
> ephemeris version the app uses are visible inside the app.
>
> **Purchases**
>
> There are none in this build. The app is free. There is no in-app purchase,
> no subscription offer, no pricing, no purchase button and no link to any
> external purchase method. Every feature the app exposes is available to every
> signed-in account at no cost, including accounts that hold a paid tier on our
> website: the app does not grant, display, advertise or reference that tier.
> The in-app purchase products in App Store Connect are intentionally not
> submitted with this version.
>
> **Sign in (please read before testing)**
>
> The first sign-in step sends a one time code by email, which you will not be
> able to receive. Please use the password path instead:
>
> 1. On the sign-in screen tap "Sign in with password", below the provider
>    buttons.
> 2. Email: <DEMO EMAIL>
> 3. Password: <DEMO PASSWORD>
>
> Apple and Google sign in also work if you prefer your own account.
>
> **Account deletion (Guideline 5.1.1(v))**
>
> Settings (gear icon at the top of the profile list) > Account > "Delete
> account". Tapping it asks for confirmation. On confirm the app deletes the
> account, all profiles and birth data, follow relationships and the
> authentication record, then signs out and returns to the sign-in screen. The
> whole flow is native. A screen recording is attached to our Resolution Center
> reply.
>
> **Location and notifications**
>
> Location is requested so a reading can be labelled with the place it was
> calculated for. It is optional: a place can be typed instead and the app
> works without granting it. Notification permission is requested from the home
> screen because the notification is about that screen.

---

## 2. What's New in This Version

Note: 1.1 was never released, so 1.2 is a first release and App Store Connect
normally does not show this field at all. Text kept for the release notes and
for the next update if the field is present.

> Rebuilt from the ground up as a native app.
>
> A page for every person you follow, swipe to move between them.
> A daily score and a "feels like" category for each profile.
> Notifications when someone's day changes category.
> A new chart wheel you can tap.
> Search for and discover new profiles.
> Hand a profile over to someone else by email.

---

## 3. Resolution Center reply (request a call, send today)

Sent as a reply on submission 2b81bd3a. Deliberately short: it asks for a
conversation and does not re-argue the April decision.

> Hello App Review Team,
>
> We would like to request a phone call, or an App Review consultation, before
> we submit our next version.
>
> Our app was rejected under Guideline 4.3(b) three times, and our appeal to
> the App Review Board was declined in April 2026 with the recommendation to
> reconsider the app concept. We have spent the time since rebuilding the app
> rather than re-arguing the previous decision. The app is now a native SwiftUI
> application instead of a web view wrapper, all descriptive interpretation
> text has been removed, the presentation has been rebuilt around following
> other people's profiles, and the app has no purchases of any kind.
>
> Before we submit we would like 30 minutes with someone from App Review, to
> confirm that this direction addresses the 4.3(b) concern and to hear what
> else you would want to see. We would rather get this right than send you
> another submission to reject.
>
> Please let us know how to arrange this. We are also requesting an App Review
> appointment through Meet with Apple. Our contact address is
> big3meapp@gmail.com.
>
> Thank you,
> The big3.me team

---

## 4. App Store Connect checklist

Version record and metadata:

- [ ] Do NOT create a new version record. 1.1 was never released, so its page is
      editable: change the Version field from 1.1 to 1.2 and save.
- [ ] Attach build 6 (the Build section currently holds the April build 1.7).
- [ ] Answer the new social media age rating questions in App Information.
      App Store Connect flags them as required from September 7, 2026 for any
      app being submitted, so this blocks the submission.
- [ ] Paste the Notes from section 1 into App Review Information > Notes,
      replacing the April text.
- [ ] Fill in the demo account email and password, and confirm that account can
      sign in with a password (not only a code).
- [ ] Replace all screenshots. The six on file show the old web interface and no
      longer represent the app (Guideline 2.3.3).
- [ ] Add the iPhone 6.9" screenshot set. Only 6.5" is uploaded, and 6.9" is the
      size App Store Connect asks for now.
- [ ] Remove the em-dash from Promotional Text ("compatibility — all powered").
      House rule: ASCII punctuation only in customer-facing copy.
- [ ] Leave both subscriptions unsubmitted. They stay in MISSING_METADATA and
      must not be attached to this version.
- [ ] Confirm the listing does not advertise In-App Purchases.

Keep as they are (already correct):

- Category: Social Networking
- Subtitle: "Birth Chart Social Network"
- Privacy policy: https://big3.me/privacy
- Support URL: https://big3.me/support
- Age rating: 4+

Attachments to prepare:

- [ ] Screen recording of the account deletion flow, end to end, from the
      native Settings to the confirmation.

---

## 5. Code fixes this submission depends on

**Payments, in the web app's native branch only.** The native app gates
nothing: there is no `isPro`, no paywall and no lock anywhere in the Swift
code, so everything it shows is already free to everyone. The risk is confined
to the web view, which loads big3.me in full.

- `useSubscription()` returns `is_pro: false` when running inside the app, so
  no paid content is served there even to an account that pays on the web.
- Backup on the backend: force the free tier when the request carries the
  iOS app's user agent (`big3me/ios`), so walking around the web view by hand
  cannot leak it.
- The paywall never renders inside the app. About ten call sites in `App.tsx`
  pass `onPaywall`, so one guard at the entry point covers them.
- Gated blocks show the free content plainly instead of a lock with an
  "unlock" affordance. A lock reads as a paywall to a reviewer.
- Hide the plan row (Pro / Free) in the web Settings modal inside the app.

**Account deletion.** "Manage account" currently opens the web app's home page,
leaving the delete action several taps deep. Point it at the account route.

**Native copy.** `SettingsView` footer reads "Account deletion and subscription
management open in the app's web view". Drop the subscription half.

---

## 6. Meet with Apple: App Review appointment

Checked 2026-09-06 at
https://developer.apple.com/events/view/upcoming-events?search=%22App%20Review%22

Format: 30 minute video appointment with App Review over Webex. The request
form asks for the app's Apple ID and specific details of what you want to
discuss. Language preference can be set, and Russian is on the list.

Availability:

| Dates | State | Request by |
|---|---|---|
| Sept 8-9 | Registration full | Sept 7 |
| Sept 10-11 | Registration full | Sept 9 |
| **Sept 15-16** | **open** | Sept 14, 12:00 a.m. PDT |
| Sept 17-18 | open, slots almost every hour | Sept 16, 12:00 a.m. PDT |

Sept 15 slots (PT): 12, 1, 2, 3, 4, 5, 9, 10 PM, plus Sept 16 at 12 AM.

### Text for the request form

> App Apple ID: 6761735807 (big3.me, bundle me.big3.app)
>
> We have been rejected three times under Guideline 4.3(b), and the App Review
> Board affirmed the rejection twice, most recently on April 22, 2026 (appeal
> ticket APL408627). The last review also cited Guideline 3.1.1.
>
> We have not resubmitted since. We rebuilt the app instead. It is now a native
> SwiftUI application rather than a web view wrapper, all descriptive
> interpretation text has been removed so the app presents computed values
> only, and the presentation has been rebuilt around following other people's
> profiles. We intend to submit with no purchases of any kind in the app, which
> we believe resolves the 3.1.1 finding.
>
> What we would like to discuss:
>
> 1. Whether a rebuild of this kind can be reviewed on our existing app record,
>    or whether the guidance to "reconsider the app concept and submit a new
>    app" means we are expected to create a new record and bundle identifier.
> 2. What in the current build would still read as duplicating a saturated
>    category, so that we can address it before submitting rather than after.
> 3. Whether removing all paid content from the iOS app is an acceptable way to
>    resolve 3.1.1, given that this version offers no in-app purchase.
>
> We can provide a TestFlight build to look at ahead of the call if that helps.
>
> Language preference: English or Russian.
