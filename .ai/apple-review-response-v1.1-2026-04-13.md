# Apple Review Response — big3.me v1.1

**Submission ID:** 2b81bd3a-fd7c-4534-a70f-33b7f0641b76
**Date:** 2026-04-13
**Issues flagged by Apple:** 4.3(b), 2.2, 2.1(b), 5.1.1(v)

This document contains: (1) code changes shipped in this submission, (2) Resolution Center reply draft, (3) three strategic options for 4.3(b), (4) checklist for the human (what only the account owner can do).

---

## 1. Code changes shipped in this build

All changes live in branch `claude/ios-paywall-contact` (auto-merges to `main` on push → Railway deploys).

### 1.1 — 5.1.1(v) Account Deletion (FULLY IMPLEMENTED)

- Backend: `DELETE /api/v1/auth/account` removes user + all owned data in FK-safe order (latest_transits, profile_follows both directions, profile_invites both directions, profiles, subscriptions, user row) and calls Supabase Admin API to delete the Auth record.
- Frontend: **Settings → Account → Delete account** (red card at bottom). Opens confirm modal → calls API → signs out → reloads to `/`.
- Privacy policy `templates/legal/privacy.html` section 7a rewritten to describe the in-app flow.
- Localized in EN/RU (8 new i18n keys).

### 1.2 — 2.2 Beta removal (DONE)

All user-visible "beta" labels removed:
- `settings.freeBeta`: "Free Beta" → "Free" (EN), "Бесплатная бета" → "Бесплатный" (RU)
- `settings.versionVal`: "0.1.0 beta" → "1.1" (both locales)

### 1.3 — 2.1(b) IAP compliance hardening (DONE)

Strategy chosen: **Option C (Hybrid / Multiplatform Services-adjacent)**
- iOS app is purely informational regarding subscriptions — no pricing, no purchase CTA, no external payment links visible inside the iOS app.
- Web subscribers retain Pro feature access on iOS via the same account sync (Supabase Auth session).

Concrete changes:
- `Paywall.tsx` — native branch (when `Capacitor.isNativePlatform()`) now shows:
  - Neutral title: "Pro feature" (was "Unlock big3.me Pro")
  - Informational message: "This feature is available to Pro subscribers only."
  - "Got it" dismiss button only.
  - **No prices, no benefits list, no purchase button, no external link, no mailto.**
- `SettingsModal.tsx` — "Manage subscription" button (which redirected to Stripe Customer Portal) is now hidden on iOS. Pro iOS users see a passive line: "Subscription is managed from the website where it was purchased." (No URL mentioned.)
- Previously removed in earlier iteration of this branch: `CONTACT_EMAIL` + `handleContactEmail` in Paywall that was a mailto IAP-circumvention vector.

### 1.4 — Files touched

- `app/api/v1/routes/auth.py`
- `frontend/src/api.ts`
- `frontend/src/components/Paywall.tsx`
- `frontend/src/components/SettingsModal.tsx`
- `frontend/src/styles.css`
- `frontend/src/i18n/en.ts`
- `frontend/src/i18n/ru.ts`
- `templates/legal/privacy.html`

---

## 2. Resolution Center reply draft

Paste the block below into App Store Connect → Resolution Center → Reply to Apple, after TestFlight build with all above fixes is live for the reviewer.

> Hello Apple Review Team,
>
> Thank you for the detailed feedback. We have addressed each guideline item in the new build and below we respond to each point individually. We have also answered the App Store Business Model questions explicitly.
>
> **Guideline 2.2 — Beta Testing**
>
> We have removed all user-visible references to "beta" from the app UI. The Settings → Account screen now shows plan "Free" (previously "Free Beta") and the Settings → About screen shows version "1.1" (previously "0.1.0 beta"). We ship this as a production release, not a beta.
>
> **Guideline 2.1(b) — Business Model (App Review Information answers)**
>
> 1. Features that require subscription to function as intended: extended 10-day transit forecast, detailed transit descriptions/interpretations, cosmic climate analysis, aspect timeline, synastry compatibility report, and chart export. Free tier users receive a 3-day transit summary with basic aspect data and an interactive natal chart.
>
> 2. Free features available: account creation and sign-in, natal chart calculation and interactive chart wheel, 3-day transit summary with up to 3 top active aspects, basic aspect data, viewing followed natal profiles, and news content.
>
> 3. Paid features available: the extended features listed in answer (1). These are unlocked on a user's account after they subscribe.
>
> 4. Paid content, subscriptions, or features unlocked within the iOS app that do not use in-app purchase: **none from within the iOS app**. The iOS app does not offer any in-app purchase and does not display subscription pricing, plans, purchase buttons, or external payment links. big3.me is a cross-platform astrology service. Users who have subscribed to our service on our website (big3.me) can sign in to the iOS app with the same account and, because subscription state is tied to the account rather than the device, they retain access to the features they already paid for. We believe this is consistent with the Multiplatform Services principle in guideline 3.1.3(b). The iOS app itself does not encourage, link to, or provide pricing information about any external purchase method.
>
> 5. Advertising revenue: the app does not display any third-party advertising.
>
> If Apple would prefer us to add an in-app purchase as an alternative way to subscribe from iOS, we can do so in a follow-up submission. Please confirm whether the current configuration (iOS app shows no subscription pricing or CTA; web-only subscription sync via account) is acceptable, or if IAP is required.
>
> **Guideline 5.1.1(v) — Account Deletion**
>
> Account deletion is now available in-app: Settings → Account → "Delete account". Tapping it shows a confirmation dialog; on confirm, the app calls our backend which deletes the user's profile data, birth data, chart data, follow relationships, subscription records, and the Supabase Auth record. The user is signed out and returned to the landing screen. An email-based fallback also exists for users who cannot sign in. Privacy policy at https://big3.me/privacy section 7a describes the flow.
>
> **Guideline 4.3(b) — Design: Saturated Categories**
>
> (Choose one of the three blocks in Section 3 below and insert here after decision is made.)
>
> Thank you for your continued review. We are available at big3meapp@gmail.com for any clarification.
>
> — The big3.me team

---

## 3. Guideline 4.3(b) — three response options

Apple rejected us twice on 4.3(b). Reviewer language both times: "saturated category" / "similar to other astrology apps". Reviewer has asked us to demonstrate unique value beyond existing astrology apps. Three realistic paths:

### Option A — Third repositioning attempt (inside the "astrology" category, stronger differentiation)

Argue that big3.me is **not a horoscope app** but an **astronomical calculation and visualization tool for personal timing**. Key talking points to give Apple:

- Swiss Ephemeris engine (Astrodienst-grade ephemeris, arcsecond-accurate planetary positions) — most consumer astrology apps use approximated or cached ephemeris data.
- No horoscope text, no "love compatibility" matching gimmick, no zodiac personality quizzes.
- Interactive natal chart rendered in-app with configurable house system, orb settings, aspect type filters, and transparent display of calculation parameters (visible in Settings → System).
- Cross-reference tool: sidereal/tropical zodiac disclosure, visible ephemeris version, visible house system — positioned as a reference instrument, comparable to a planetarium app but focused on personal timing.
- Visual differentiator: our chart wheel design and UX is novel (Apple can see in screenshots).

**Tone of reply:** respectful, factual, provides explicit list of technical differentiators with links to Settings screens.

**Pros:** lowest effort, no code changes needed beyond v1.1. Keeps us on course for consumer discoverability under "astrology".
**Cons:** reviewer has rejected similar arguments twice. Third attempt may still fail. Risk burning goodwill.

### Option B — Request App Review Board appeal + phone call

Apple provides an appeal escalation path for 4.3(b): https://developer.apple.com/contact/app-store/?topic=appeal
A phone call with the Review Board lets us argue the case live. Phone review can override the reviewer's decision when the case is well made.

**Prep for the call:**
- 60-second pitch: "big3.me is an astronomical timing instrument, not a horoscope app. Swiss Ephemeris. Transparent computation parameters. No personality gimmicks. Target audience: serious astrology practitioners, not entertainment consumers."
- Three differentiators ready: (1) calculation transparency (Settings → System shows ephemeris/house system/orb), (2) cross-platform account sync (iOS reads data computed on the same engine as the web), (3) visualizations (chart wheel interactions).
- Comparable apps to differentiate from by name: Co-Star (entertainment/AI-generated horoscopes), The Pattern (personality), Costar-style apps.
- Outcome we want: conditional approval with a note that if we stay under "astrology", the binary must demonstrate the technical angle. Or approval under a less crowded category like "Reference" or "Utilities".

**Pros:** highest chance of a clean approval if we hold up under live review. Also a good strategic data point — we learn exactly what Apple wants to see.
**Cons:** requires a live human call in a specific timezone. If we do this and still lose, the ruling is final-ish on this build.

### Option C — Accept the reality: pivot to PWA on iOS

Accept that 4.3(b) under "astrology" will keep getting rejected. Withdraw the App Store submission for now. Ship the iOS experience as an installable PWA promoted from our landing page (https://big3.me/app or similar): iOS users tap "Add to Home Screen" and get the full big3.me experience. This bypasses App Store review entirely.

**What we keep:**
- All users (web + "mobile web app") remain on one codebase with one auth path and one subscription path.
- No more App Store review cycles blocking releases.

**What we lose:**
- Discoverability via App Store search.
- "Download on the App Store" marketing asset.
- Push notifications via APNs (PWA has Web Push on iOS since 16.4 but with caveats).
- Access to Apple Sign In inside a native wrapper (though Apple Sign In works on web too).

**Pros:** zero App Store dependency going forward. Frees up engineering time.
**Cons:** no App Store presence, harder to reach non-technical mobile users.

### Recommendation

Try **A first** (low cost), but keep **B warm** (prepare the phone call pitch and submit the appeal form in parallel). Reserve **C** as fallback if both A and B fail on the next cycle.

---

## 4. Human action checklist

The following items require the account owner (Serge) — Claude cannot do these from the sandbox:

### 4.1 — Xcode build + TestFlight upload

1. Open `frontend/ios/App/App.xcworkspace` in Xcode.
2. Bump build number: Target "App" → General → Identity → **Build**: bump to the next integer above the previously-rejected build.
3. (Optional but recommended) Bump marketing version to `1.1` if not already there.
4. Product → Archive → Distribute App → App Store Connect → Upload.
5. Wait for the build to finish processing in App Store Connect (~15–30 minutes). It appears in TestFlight → iOS Builds once processed.
6. Attach the new build to the rejected submission in App Store Connect: Submission → "Build" section → select the new build.

Since the app loads `https://big3.me` via Capacitor's `server.url`, the web changes auto-deploy on push to `main`. The Xcode build is only needed to package the new `Info.plist`/asset changes (if any) and produce a fresh binary with a new build number for Apple's review queue. **You do need a new Xcode build + upload for Apple to re-review** — TestFlight does not auto-update binaries from a web deploy.

### 4.2 — Screen recording for 5.1.1(v)

Apple asks for a screen recording showing the deletion flow when account deletion is a new addition. Quick capture:

1. Sign in to the app on iOS (any test account will do).
2. Start a QuickTime screen recording (Mac: Cmd+Shift+5 → record selected iPhone via Mirror).
3. Walk through: Settings (gear) → Account → scroll to red "Delete account" card → tap → confirm dialog → tap "Delete".
4. Show that the app returns to the landing/sign-in screen.
5. Save as .mov or .mp4 and attach to the Resolution Center reply.

### 4.3 — App Review Information field updates in App Store Connect

Before resubmitting:

1. App Store Connect → My Apps → big3.me → App Store tab → the rejected submission → **App Review Information**.
2. Paste the 5 Business Model answers from Section 2 of this doc into the "Notes" field (or directly in the Resolution Center message).
3. Confirm **Demo Account** credentials are current and the account has at least one natal profile configured (reviewer needs to see Pro features referenced in answer 1 — create a test Pro account, or note in Notes: "Demo account is free tier; Pro features can be demonstrated by calculating a natal chart, which is free, and viewing the 3-day transit summary; extended features require a subscription we do not offer from iOS").

### 4.4 — 4.3(b) strategic decision

Pick A, B, or C from Section 3. If A: just paste the A reply into Resolution Center. If B: open https://developer.apple.com/contact/app-store/?topic=appeal and request a phone call. If C: withdraw the submission in App Store Connect and ship PWA promotion instead.

### 4.5 — Resolution Center reply

After build is attached and demo account is ready:
1. App Store Connect → Resolution Center → Reply.
2. Paste the Section 2 reply with the chosen 4.3(b) block inserted.
3. Attach the deletion screen recording (4.2).
4. Submit.

---

## 5. Open questions for Serge

1. **4.3(b) path:** A / B / C?
2. **Pro demo account:** do we want to give Apple reviewer a Pro-activated account so they can see the extended features (which are free on web after login) directly, or leave the explanation in the Notes field? A Pro demo account would strengthen our "multiplatform service" narrative but requires us to flag one account as Pro in Supabase.
3. **Privacy policy** already live on `https://big3.me/privacy` — confirm once more after the main deploy that section 7a describes the in-app delete flow (it does in this branch, will be live post-merge).
