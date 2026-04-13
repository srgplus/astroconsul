# AI Changelog

Changes relevant for AI assistants working on this codebase.

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
