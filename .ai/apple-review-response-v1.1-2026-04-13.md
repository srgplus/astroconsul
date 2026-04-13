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
> 1. Users who will use paid subscriptions: existing big3.me web users who want the full content depth that the free tier does not expose. Pro unlocks, on a signed-in account: the full set of daily transit aspects (free tier shows only the top 3 active aspects), the detailed transit interpretation text (the textual description and contextual insight for each aspect), the full cosmic climate analysis text, and the full set of natal chart interpretations (free tier shows interpretations for the top 3 natal positions and top 3 natal aspects only). Pro users are also the audience for new content additions we plan in the same areas.
>
> 2. Where users can purchase subscriptions: only on our website, big3.me, via Stripe checkout. The iOS app does not offer any purchase path and does not display pricing or external payment links.
>
> 3. Previously purchased subscriptions accessible in the app: a Pro subscription activated on the big3.me website is tied to the user's account (not to the device). When the same user signs in to the iOS app with that account, Pro content unlocks in the iOS UI — the full transit aspect list, the interpretation text, the full cosmic climate text, and the full natal interpretation set.
>
> 4. Paid content, subscriptions, or features unlocked within the iOS app that do not use in-app purchase: Pro-gated content described in (1) becomes visible on iOS when the signed-in user is already a Pro subscriber. The iOS app itself does not offer any in-app purchase and does not display subscription pricing, plans, purchase buttons, or external payment links. big3.me is a cross-platform service; subscription state is tied to the account rather than the device. We believe this is consistent with the Multiplatform Services principle in guideline 3.1.3(b). The iOS app does not encourage, link to, or provide pricing information about any external purchase method.
>
> 5. Advertising revenue: the app does not display any third-party advertising.
>
> Free-tier features available without any subscription: account creation and sign-in, interactive natal chart wheel with precise planet positions, the top 3 active transit aspects with their core data (object, aspect, orb, strength), the TII (0–100 daily score) and Feels Like indicator, synastry compatibility analysis between the user and any other profile, follow/unfollow other users, view public profiles, invite friends via email, browse featured profiles, and news content.
>
> If Apple would prefer us to add an in-app purchase as an alternative way to subscribe from iOS, we can do so in a follow-up submission. Please confirm whether the current configuration (iOS app shows no subscription pricing or CTA; web-only subscription sync via account) is acceptable, or if IAP is required.
>
> **Guideline 5.1.1(v) — Account Deletion**
>
> Account deletion is now available in-app: Settings → Account → "Delete account". Tapping it shows a confirmation dialog; on confirm, the app calls our backend which deletes the user's profile data, birth data, chart data, follow relationships, subscription records, and the Supabase Auth record. The user is signed out and returned to the landing screen. An email-based fallback also exists for users who cannot sign in. Privacy policy at https://big3.me/privacy section 7a describes the flow.
>
> **Guideline 4.3(b) — Design: Saturated Categories**
>
> We have repositioned the app and its App Store listing to reflect what big3.me actually is: a social networking application where users connect through their natal birth charts.
>
> The app is now categorized under **Social Networking** (not Lifestyle). The subtitle is "Birth Chart Social Network". The primary screenshot and landing page lead with the social feed: "Your friends. One feed." Core features exposed in the listing are: following friends, viewing public profiles, comparing birth charts side-by-side, running synastry compatibility analysis, and a personal daily tracker.
>
> We believe this positioning is materially distinct from other astrology or lifestyle apps Apple may have compared us to previously. In particular:
>
> 1. **Category fit.** The app's core loop is social: follow → view chart → compare charts → run synastry. The astrological data is the *medium* through which users connect, not the product itself. This is why Social Networking is the accurate category.
>
> 2. **Computational differentiation.** Unlike most apps in the astrology/lifestyle space that serve pre-written horoscope text, every data point in big3.me is computed in real-time via Swiss Ephemeris — the same professional-grade astronomical ephemeris used by academic and professional astrology software. We expose the engine's configuration (house system, orb limits, ephemeris version) transparently in Settings → System, which is unusual for consumer apps in this space.
>
> 3. **Social graph.** The app includes follow relationships, public profile discovery, profile invites via email, and shared synastry views — standard social networking primitives built specifically around birth charts.
>
> 4. **Multiplatform, no purchase flow in iOS.** The iOS app has no in-app purchase, no subscription pricing shown, no purchase CTAs, and no external payment links. Web subscribers retain their Pro tier via account sync (multiplatform service, consistent with 3.1.3(b)).
>
> We are confident the app provides a meaningfully different experience from the apps in the saturated category Apple flagged previously, and we are happy to demonstrate any of the above directly if helpful. If Apple sees a specific concern within this Social Networking positioning, we would welcome the detail so we can address it.
>
> Thank you for your continued review. We are available at big3meapp@gmail.com for any clarification.
>
> — The big3.me team

---

## 3. Guideline 4.3(b) — CURRENT STRATEGY: Social Networking category + Scientific framing

**The App Store listing has already been repositioned for this cycle:**
- **Category:** Social Networking (not Lifestyle)
- **Subtitle:** "Birth Chart Social Network"
- **Promotional Text:** "Follow friends, compare birth charts, and explore compatibility — all powered by real-time Swiss Ephemeris calculations. A social network for chart enthusiasts."
- **Screenshots:** lead with "Your friends. One feed." — social feed, then Compatibility (synastry), Daily Score, Live planetary data, Professional chart engine, Create your profile
- **Keywords:** birth chart, social, compatibility, synastry, natal chart, friends, transit, ephemeris, forecast, connect

**Reply argument to 4.3(b):** "big3.me is categorized under Social Networking, not Lifestyle. The app is fundamentally a social network for people connecting through their birth charts — following friends, comparing charts, and exploring compatibility. This differs materially from general horoscope/astrology apps in the Lifestyle category that Apple may be comparing us to. Our computation engine is also differentiated: every result is computed in real-time via Swiss Ephemeris (a professional astronomical ephemeris), not served from pre-written content. We would welcome further dialogue if Apple identifies a more specific concern within this positioning."

### 3.1 — Landing page + metadata alignment (fixed in this commit)

Apple reviewers typically cross-check the App Store listing against the app's web presence. The iOS app loads `big3.me` directly (WKWebView), so the landing page must match the Social Networking positioning. Previously the landing page said:
- Hero: "Explore Cosmic Weather"
- Subtitle: "See what the stars reveal about your favorite celebrities"
- Pills: Transit Alerts · Moon Phases · Natal Chart · Synastry
- Meta title: "big3.me — Cosmic Weather for Your Big 3"
- Meta description: "AI-powered cosmic weather tracks how planetary transits interact with your Big 3..."

**Updated to:**
- Hero: "Your friends. One feed." (mirrors App Store screenshot #1)
- Subtitle: "A social network built around birth charts. Follow friends, compare charts, and discover compatibility — all powered by real-time Swiss Ephemeris calculations."
- Pills: Follow Friends · Compatibility · Daily Score · Natal Chart · Swiss Ephemeris
- Meta title: "big3.me — Birth Chart Social Network"
- Meta description: "Follow friends, compare birth charts, and discover compatibility. Real-time calculations powered by Swiss Ephemeris."
- Section label: "Featured Profiles" (was "Featured Charts")
- Sign-up hint: "Sign up to connect and compare"

RU translations updated in parallel.

### 3.2 — App Review Information "Notes" field (REPLACE IN APP STORE CONNECT)

**Current Notes text contains "astrology app" in the first sentence — this contradicts the Social Networking category and will trigger 4.3(b) again.**

**Current (replace this):**
> "This is an astrology app that provides personalized daily transit reports based on the user's birth chart. The app uses Swiss Ephemeris for astronomical calculations. Pro subscription is handled via Stripe (web-based payment), not In-App Purchase."

**New text to paste into App Store Connect → App Review Information → Notes:**

```
big3.me is a social networking application where users connect through their natal birth charts. Core functionality: follow friends, view public profiles, compare birth charts (synastry compatibility), and a personal daily tracker showing how current planetary positions interact with each user's chart.

Category: Social Networking.

Differentiators vs other social/lifestyle apps in the store:
- Cross-profile social graph: users follow each other, compare charts side-by-side, run synastry analysis between any two profiles
- Real-time astronomical computation: every data point is computed via Swiss Ephemeris (a professional-grade ephemeris used in academic astronomy software), not served from pre-written content
- Transparent calculation parameters: users can see the house system, orb limits, and ephemeris version the app uses (Settings → System)

Subscription model: big3.me offers a Pro tier that unlocks the full set of daily transit aspects (free tier shows the top 3), detailed transit and natal interpretation text, and full cosmic climate analysis. Subscription is offered ONLY on our website (big3.me). The iOS app does NOT display subscription pricing, purchase buttons, or external payment links. Users who subscribe on the web retain their Pro access when signing in on iOS via the same account (multiplatform service, consistent with guideline 3.1.3(b)). The iOS app is free to download and use.

Demo account: (provided in the Demo Account section).
```

---

## 4. Alternative 4.3(b) paths if Social Networking positioning still fails

If Apple rejects v1.1 again even under the Social Networking category, these are fallback options:

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

### Fallback order (only if Social Networking positioning fails)

1. **Option A** (third repositioning under Lifestyle/Reference, scientific framing) — cheap first attempt after Social fails
2. **Option B** (App Review Board appeal + phone call) — if A fails, escalate to live review
3. **Option C** (withdraw and ship PWA) — final fallback if both above fail

---

## 5. Human action checklist

The following items require the account owner (Serge) — Claude cannot do these from the sandbox:

### 5.1 — Xcode build + TestFlight upload

1. Open `frontend/ios/App/App.xcworkspace` in Xcode.
2. Bump build number: Target "App" → General → Identity → **Build**: bump to the next integer above the previously-rejected build.
3. (Optional but recommended) Bump marketing version to `1.1` if not already there.
4. Product → Archive → Distribute App → App Store Connect → Upload.
5. Wait for the build to finish processing in App Store Connect (~15–30 minutes). It appears in TestFlight → iOS Builds once processed.
6. Attach the new build to the rejected submission in App Store Connect: Submission → "Build" section → select the new build.

Since the app loads `https://big3.me` via Capacitor's `server.url`, the web changes auto-deploy on push to `main`. The Xcode build is only needed to package the new `Info.plist`/asset changes (if any) and produce a fresh binary with a new build number for Apple's review queue. **You do need a new Xcode build + upload for Apple to re-review** — TestFlight does not auto-update binaries from a web deploy.

### 5.2 — Screen recording for 5.1.1(v)

Apple asks for a screen recording showing the deletion flow when account deletion is a new addition. Quick capture:

1. Sign in to the app on iOS (any test account will do).
2. Start a QuickTime screen recording (Mac: Cmd+Shift+5 → record selected iPhone via Mirror).
3. Walk through: Settings (gear) → Account → scroll to red "Delete account" card → tap → confirm dialog → tap "Delete".
4. Show that the app returns to the landing/sign-in screen.
5. Save as .mov or .mp4 and attach to the Resolution Center reply.

### 5.3 — App Review Information field updates in App Store Connect

Before resubmitting:

1. App Store Connect → My Apps → big3.me → App Store tab → the rejected submission → **App Review Information** → **Notes**.
2. **Replace the current "astrology app" text with the new Notes text in Section 3.2 above.** This is the single most important change after the build upload — the old text directly contradicts the Social Networking category.
3. Confirm **Demo Account** credentials are current. If we're going to answer question (1) about Pro features honestly, we either (a) flag the demo account as Pro in Supabase so reviewer can see extended features directly, or (b) note in Notes: "Demo account is free tier; Pro features (extended forecast, detailed descriptions) are shown to users who subscribe on our website; for this review, extended features are documented in the Description and screenshots."
4. Verify the App Store listing fields match the Social Networking pivot (they already do in the listing Serge pasted):
   - Category: Social Networking ✓
   - Subtitle: "Birth Chart Social Network" ✓
   - Promotional Text, Description, Keywords all social-first ✓

### 5.4 — 4.3(b) strategic decision (already made: Social Networking + Scientific)

Decision already taken: repositioned to Social Networking category, with Scientific (Swiss Ephemeris) differentiation. No further choice needed unless this cycle fails. Fallbacks in Section 4 (A, B, C) stay reserved for later cycles.

### 5.5 — Resolution Center reply

After build is attached and demo account is ready:
1. App Store Connect → Resolution Center → Reply.
2. Paste the Section 2 reply (now self-contained — 4.3(b) block pre-filled with Social Networking argument).
3. Attach the deletion screen recording (5.2).
4. Submit.

---

## 6. Open questions for Serge

1. **Pro demo account:** flag the demo account as Pro in Supabase so reviewer sees extended features directly? Strengthens our "multiplatform service" narrative considerably. If yes: pick a demo account email and update their row in `subscriptions` table (or give me the email + I'll provide the SQL).
2. **Privacy policy** already live on `https://big3.me/privacy` — confirm once more after the main deploy that section 7a describes the in-app delete flow (it does in this branch, will be live post-merge).
3. **If 4.3(b) rejected AGAIN under Social Networking:** proceed to Fallback A (Lifestyle/Reference + scientific), then B (Review Board phone call), then C (PWA). See Section 4.
