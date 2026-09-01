# AI Changelog

Changes relevant for AI assistants working on this codebase.

## 2026-09-01

### Production outage: Railway trial expired
`big3.me` and the generated `bb4q5xov.up.railway.app` both returned Railway's 404
("The train has not arrived at the station"). Root cause confirmed in the Railway
dashboard: **the trial ended and Railway stopped every service on the account**
(`Trial expired` badge, "Trial Ended / Upgrade now" banner, all four projects at
`0/1 service online`). Not a code, DNS, or custom-domain fault: DNS verified
healthy (apex flattens to the same Railway edge IP as the generated domain, `www`
proxied via Cloudflare) and CI is clean (last deploy 2026-06-13, all auto-merge
runs green).

Fix is account-level: upgrade the Railway plan, then redeploy. User data was
never at risk since persistence is Supabase PostgreSQL and images are in Supabase
Storage, so the Railway container is stateless; what only exists in Railway is
the service configuration.

Recovery order, data-safety note, and the env-var restore list (including two
variables that fail silently: `ASTRO_CONSUL_PERSISTENCE_BACKEND=database`, which
the Dockerfile bakes as `file`, and `ASTRO_CONSUL_AUTH_ENABLED=true`, which
defaults to `false`) are in `.ai/railway-outage-2026-09-01.md`.

Also noted: the scheduled `Rotate Apple SIWA Secret` workflow has been failing
since 2026-06-01.

## 2026-06-12

### Android Google/Apple OAuth login fix
Symptom: tapping "Continue with Google" on Android opened the website in the system browser and never logged the user into the app. Root causes:
1. `AuthContext.tsx` detected Capacitor via `navigator.userAgent.includes("big3me")` — the WebView UA contains no such token (no `appendUserAgent` configured), so it always evaluated false and `redirectTo` fell back to `https://big3.me`.
2. Even with a deep-link `redirectTo`, nothing caught the return: no `appUrlOpen` listener and `@capacitor/app` was not installed.
3. Android had no intent-filter for the `big3me://` scheme, so the OS could not route the OAuth return back into the app.

Fixes (JS — deploys via Railway, picked up by the WebView since it loads `https://big3.me` live):
- `AuthContext.tsx`: detect native with `Capacitor.isNativePlatform()`; on native, open OAuth in the system browser via `@capacitor/browser` (`skipBrowserRedirect: true`) and complete the session in an `App.addListener("appUrlOpen")` handler that calls `supabase.auth.exchangeCodeForSession(code)`, then closes the in-app browser.
- `package.json`: added `@capacitor/app`.

Native (local-only — `frontend/android/` and `frontend/ios/` are gitignored; require a manual rebuild + store release):
- `android/app/src/main/AndroidManifest.xml`: added VIEW/BROWSABLE intent-filter for `android:scheme="big3me"` on MainActivity (already `launchMode="singleTask"`).
- iOS already registers the `big3me` scheme in `Info.plist`; run `npx cap sync ios` so the iOS project also picks up `@capacitor/app`.

Dashboard config: in Supabase → Authentication → URL Configuration → Redirect URLs, `big3me://auth-callback` must be present (verified already present on 2026-06-12). Without it Supabase rejects the redirect and falls back to the Site URL (the website). No Google Cloud Console change needed — Google still redirects to the Supabase callback.

Follow-up fix (implicit-flow tokens): on-device test showed the app returned from the system browser but never logged in. Cause: the Supabase client uses the default `flowType: 'implicit'`, so the OAuth return carries tokens in the URL **hash** (`#access_token=...&refresh_token=...`), not a PKCE `?code=`. The `appUrlOpen` handler only read `?code=`. Fixed the handler in `AuthContext.tsx` to handle both: `?code=` → `exchangeCodeForSession`, otherwise parse the hash and call `setSession({access_token, refresh_token})`. JS-only fix — the installed app picks it up on reload (no new APK). Future hardening: switch the client to `flowType: 'pkce'`.

Play Store release: signed AAB built (`versionCode 2`, `versionName 1.1`) and published to the **Internal testing** track on 2026-06-12 (developer `SRG PLUS`, app `me.big3.app`, internal opt-in `https://play.google.com/apps/internaltest/4701718781571690534`). Verified working on a physical device on 2026-06-13, then **promoted to Production and sent for Google review** the same day (managed publishing is OFF → auto-publishes to 100% on approval). Next build must use `versionCode >= 3`.

iOS / App Store: **deferred** — the iOS app is currently in a rejected state with Apple (see [[project_apple_review]], 4.3b history), so we are shipping the login fix on Android only for now. The JS fix is already live for iOS too (WebView loads it from big3.me) and the `big3me` scheme is in Info.plist, but iOS still needs `@capacitor/app` added to the build for `appUrlOpen` to fire. `npx cap sync ios` cannot add it via CLI because the Xcode project was renamed from `App.xcodeproj` to `big3.me.xcodeproj` (the SPM `CapApp-SPM/Package.swift` write fails) — it must be added by hand in Xcode (File → Add Package Dependencies) when the iOS release is revisited. No iOS build was archived or submitted.

## 2026-04-14

### StoreKit2 IAP implementation (3.1.1 compliance)
Apple rejected Option C (no IAP) on Apr 14. Guideline 3.1.1 requires IAP if Pro content is accessible on iOS.

- **Backend**: `POST /api/v1/payments/verify-apple` — verifies StoreKit2 transaction and activates subscription (`payment_provider: "apple"`)
- **Backend**: `POST /api/v1/payments/webhooks/apple` — App Store Server Notifications v2 for renewals, cancellations, refunds
- **Swift**: `StoreKit2Manager.swift` — manages products, purchases, transaction listener; communicates with JS via `WKScriptMessageHandler` on `storekit` channel
- **Swift**: `CustomViewController.swift` — registers StoreKit2Manager as message handler
- **Frontend**: `Paywall.tsx` — native branch now shows real StoreKit product cards with localized prices, purchase button, restore purchases
- **Frontend**: `SettingsModal.tsx` — Apple subscribers see "Manage Subscription" linking to iOS subscription settings
- **Frontend**: `api.ts` — added `verifyAppleTransaction()` function
- **CSS**: `.paywall-restore-btn` style for restore purchases button
- Product IDs: `me.big3.pro.monthly` ($7.99), `me.big3.pro.annual` ($59.99) — must be created in App Store Connect
- Strategy: IAP on iOS + Stripe on web coexist per guideline 3.1.3(b)

### Apple review status (Apr 14 rejection)
- 2.2 Beta Testing: RESOLVED (no longer flagged)
- 5.1.1(v) Account Deletion: RESOLVED (no longer flagged)
- 4.3(b) Design Spam: still rejected (3rd time) — recommend booking "Meet with Apple" appointment
- 3.1.1 IAP: NEW — addressed by StoreKit2 implementation above

## 2026-04-13

### Apple review compliance (v1.1, submission 2b81bd3a)
- iOS Paywall: removed "Unlock Pro" marketing title on native, removed benefits list on native; native branch is now strictly informational ("Pro feature" + "available to Pro subscribers only" + "Got it" dismiss)
- SettingsModal: hide Stripe "Manage subscription" button on iOS (`Capacitor.isNativePlatform()`); Pro users on iOS see a passive line "Subscription is managed from the website where it was purchased"
- Strategy chosen for 2.1(b): Option C (Hybrid / Multiplatform Services) — iOS app has zero purchase UI; web subscribers retain Pro access via account sync
- Full response doc at `.ai/apple-review-response-v1.1-2026-04-13.md`

### Earlier this day (commit 3b1aaf5)
- Backend `DELETE /api/v1/auth/account` for 5.1.1(v) account deletion
- In-app delete flow in Settings → Account (confirm dialog, cascading FK-safe delete, Supabase Auth admin delete)
- Removed "beta"/"бета" from UI: settings plan "Free Beta" → "Free", version "0.1.0 beta" → "1.1"
- Removed mailto IAP circumvention from Paywall native branch (2.1(b) hardening pre-Apple re-rejection fix)
- Privacy policy section 7a updated to describe in-app deletion flow

## 2026-03-17

### Features
- Natal aspects sorted by planet priority (Sun→Moon→Mercury→...→Vertex) instead of by orb
- Retrograde exact pass notches on transit progress bar (`find_all_exact_passes()`)
- Retrograde badge (Ⓡ) shown on collapsed transit row
- OG/Twitter meta tags with Big3 branding
- Google Search Console verified for big3.me

### Fixes
- iOS tap in popups: native `<button>` + `onTouchEnd` (5 iterations to solve)
- Profile detail endpoint: 7 DB sessions → 2 (`load_profile_with_social()`)
- Transit loading spinner: separate `transitRefreshing` state, grey iOS-style
- Desktop column swap: natal LEFT, transits RIGHT
- Removed "following" count from followers widget
- `canonical_host` added to Settings with default empty string
- Favicon switched to PNG/ICO format

### Infrastructure
- Domain: big3.me live via Cloudflare DNS → Railway
- GoDaddy nameservers delegated to Cloudflare
- CNAME `@` → `bb4q5xov.up.railway.app` (Cloudflare CNAME flattening)
- CNAME `www` → `bb4q5xov.up.railway.app`

## 2026-03-16

### Fixes
- Docker: `python:3.11-slim` → `python:3.11-slim-bookworm`
- Follow: auto-create Supabase Auth users in `users` table (`ensure_user()`)
- Skeletons: opaque CSS vars per theme
- Stale data cleared on profile switch
- Sidebar TII persistence via `cachedTiiMap`
- Settings modal scroll fix

## 2026-03-15

### Features
- Social features: follow/unfollow profiles
- Public search and featured profiles endpoints
- Skeleton loaders for all views
- Background TII fetch for sidebar
