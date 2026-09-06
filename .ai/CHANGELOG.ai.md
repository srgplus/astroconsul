# AI Changelog

Changes relevant for AI assistants working on this codebase.

## 2026-09-06

### iOS: Settings button replaces the menu, primary pinned in the list too
- The profile list's ellipsis menu is gone: the toolbar button opens Settings
  directly. The web screens are still reachable — Settings links to them — and
  `ProfileListScreen` presents Settings itself rather than asking the pager to
  swap one presentation for another, which can drop the second sheet.
- The list is a `.sheet` now, not a `.fullScreenCover`: with Done gone, a swipe
  down is how it is left.
- `ProfileListViewModel.ownProfiles` filtered on `ownedByViewer`, so a primary
  profile the API reports with `is_own: false` — which is what it does on the
  owner's own account — landed in "Following", below every followed profile.
  The primary is now lifted out by id regardless of the flag, and excluded from
  `followedProfiles`. `WeatherHomeView` dropped its own copy of that pin.
- `WeatherPreviewData.profile` carries `isOwn: false` so the harness reproduces
  that shape instead of the tidy one.

### iOS 26: glass bottom bar, wordmark title, search at the bottom
The bottom bar dropped its slab of background: the dot capsule and the list
button now float over the sky as Liquid Glass, matching Weather on iOS 26.

- `Design/GlassSurface.swift` is the one place that calls `glassEffect`. The
  deployment target is still iOS 17, so it falls back to a dark
  `.ultraThinMaterial` shape; `WeatherGlassGroup` wraps `GlassEffectContainer`
  the same way. The glass carries a slight dark tint, otherwise white dots and
  glyphs disappear over a bright sky.
- `WeatherPageDots` switched to `backgroundStyle = .prominent`: that is what
  draws Weather's capsule, sized to the dots by the system. A capsule of our
  own sat ~50pt wider than the dots on each side, because `UIPageControl`
  reserves margin inside its own bounds. It also reports `sizeThatFits` so the
  control asks for its dots' width and no more.
- The pager draws full bleed, so the bar could not read the bottom safe-area
  inset for itself; `WeatherHomeView` passes it down and the bar sits above the
  home indicator rather than on it. The left slot is deliberately empty — a
  second button goes there later.
- `ProfileListScreen`: Done is gone from the toolbar (the ellipsis menu closes
  the screen, and so does picking a profile), the title is the big3.me
  wordmark, and the menu sits on that same line.
  `sharedBackgroundVisibility(.hidden)` keeps iOS 26 from putting a glass pill
  behind the wordmark.
- `Design/B3Wordmark.swift` draws the site's three-part lockup; Space Grotesk
  ships in `Design/Fonts` and is declared in `UIAppFonts`. Google's subset
  names the faces `SpaceGroteskLight-{Light,Regular,Bold}`.
- The list itself sits on `presentationBackground(.ultraThinMaterial)` rather
  than `Theme.bg`, so the weather page stays visible through it and the screen
  picks up the sky's colour. A clear presentation background also keeps the
  page below on screen instead of the cover blacking it out.
- Search moved to the bottom on its own: iOS 26 floats `.searchable` there for
  a `NavigationStack`. On iOS 17 the same code still draws it under the title,
  which is what the older simulators show.
### One simulator per worktree
`scripts/ios-simulator.sh` creates and boots a device named `big3 <worktree>`,
so parallel sessions stop installing builds over each other and screenshotting
each other's screen — the simulator tools otherwise default to whatever happens
to be booted. `--udid` prints the id for `xcodebuild -destination` and `simctl`,
`--delete` removes the device when a worktree is done. `SIM_DEVICE_TYPE` and
`SIM_RUNTIME` override the hardware and iOS version; the default runtime is the
newest installed, which can be ahead of what ships.

### CI and merging: PRs with required checks, and CI that actually runs
The old `auto-merge-claude.yml` pushed straight to main with `merge --ff-only`.
Two consequences, both live for months:

- **CI never ran.** GitHub does not trigger workflows for pushes made with
  `GITHUB_TOKEN`, so once the bot owned every push to main, `ci.yml` stopped
  firing. Its last run was 2026-04-06, and it was already failing then.
- **It broke silently.** `--ff-only` fails the moment another session moves
  main ahead, and nothing reports that; the branch just never lands.

Now: push to `claude/**` opens a PR (`open-pr.yml`) and queues it for
auto-merge. main is protected — PR required (0 approvals), `backend`,
`frontend` and `ios` checks must pass, direct pushes refused. `enforce_admins`
is off, so the owner keeps an escape hatch.

**What CI was hiding.** Making it green needed real fixes, not only lint:

- `app/main.py` called `logging.getLogger` in the sitemap's `except` branch
  without importing `logging`, so the fallback raised `NameError`.
- `FileProfileRepository.delete_profile` called `profile_path` without
  importing it, and `get_owner_user_id` called `.get` on the
  `(path, payload)` tuple that `natal_profiles.load_profile` returns.
- The test suite errored on import because CI installs `pyproject.toml`
  dependencies, which omit six packages that `requirements.txt` (what Railway
  installs) carries, `python-dotenv` among them. CI now installs both.
- Lint and types: 145 ruff findings and 35 mypy errors. Fixed rather than
  suppressed, except E501 (the formatter owns line width) and
  `synastry_engine`, added to the existing legacy mypy override list.

The ephemeris builders and `ProfileService` now annotate their payloads as
`dict[str, Any]` instead of `dict[str, object]`: the values are heterogeneous,
and `object` forced a cast at every read site.

### iOS: bottom bar trimmed, Settings can be closed, primary pinned first
- The bottom bar's left button is gone; the web screens are reached from the
  profile list's ellipsis menu. A clear 42pt spacer keeps the dots centred.
- `SettingsView` is presented as a sheet and had no control of its own, so a
  user who opened it was stuck. It now carries a Done button.
- `ProfileListViewModel.ownProfiles` sorted with a comparator that returned
  `true` for `lhs == rhs` when both were the primary, which is not a strict
  weak ordering; the primary ended up mid-list. It now sorts by name and lifts
  the primary out afterwards.
- `WeatherHomeView` pins the primary profile to page one regardless of which
  section it falls in. On the owner's own account the API reports the primary
  profile with `is_own: false`, so it sorts into "Following" and, without the
  pin, the location arrow landed in the middle of the page dots.

### iOS: page dots use UIPageControl
A hand-rolled `HStack` of dots is as wide as the profile count, so an account
following thirty-odd profiles made the bottom bar wider than the screen and
pushed the whole pager sideways — the sky started ~40pt in from the left edge.
`Features/Weather/WeatherPageDots.swift` wraps `UIPageControl`, which windows
and shrinks its dots to the width it is given and takes a per-page image for
the primary profile's location arrow. `WeatherPreviewData` now carries 33
sample profiles so the harness reproduces that pressure.

### iOS: tab bar removed, home is the weather pager
The shell now follows Weather all the way: no tab bar, one profile per page,
swiped horizontally, with a floating bottom bar over the sky.

- `Features/Weather/WeatherHomeView.swift` is the signed-in root. It owns the
  profile list model, the visible page and the covers.
- `Features/Weather/WeatherPager.swift`: paged `TabView` plus `WeatherBottomBar`
  (chart button left, page dots centre, profile list right). The primary
  profile takes Weather's location arrow instead of a dot.
- `Features/Profiles/ProfileListScreen.swift` replaces `ProfileListView`: same
  cards, now a full-screen cover with search and an ellipsis menu (Settings,
  web app). Tapping a card switches the visible page instead of pushing.
- `Features/Web/WebScreen.swift`: the Capacitor WebView, previously the Chart
  tab, is now a cover opened from the bottom bar and from Settings. It still
  owns the birth chart, transits, compatibility, profile editing and account
  deletion, so it stays reachable while those screens go native one by one.

The pager draws full bleed (`.ignoresSafeArea()`) so each page's sky reaches
the status bar, which means the page can no longer read the top safe-area
inset for itself: `WeatherHomeView` measures it once with a `GeometryReader`
and passes it to `CosmicWeatherView` as `topInset`.

## 2026-09-06

### iOS: Weather-style cosmic weather screen and profile list
The app's pitch is "Apple Weather for astrology", so the native screens now
look the part.

- `Features/Weather/CosmicWeatherView.swift`: one screen per profile. TII is
  the temperature (`51°`), `feels_like` is the condition, and H/L is the high
  and low **across the forecast window**, not within today — the engine yields
  one TII per day, so a same-day range would be invented.
- `Design/WeatherSky.swift`: a sky gradient per TII zone (quiet / active / hot
  / extreme), deeper in dark mode. Weather screens use white text on top of it
  rather than `Theme.text`, since the sky is saturated in both themes.
- `Features/Profiles/ProfileWeatherCard.swift` replaces `ProfileRowView`: the
  list now reads like Weather's saved cities, with the same gradient per zone.
  Tapping a card opens that profile's weather.
- `Features/Weather/ForecastCard.swift`: the 10-day list. Each row places its
  TII on the window's shared low…high scale, and the condition icon is an SF
  Symbol (`FeelsLike.symbol(for:)`) rather than the web app's emoji.

**One request feeds the whole screen**: `GET /transits/forecast?days=10` already
returns TII, feels-like, top transits, moon phase and retrogrades per day, so
no backend work was needed and no hourly strip exists (the engine has no hourly
TII).

The list drives navigation with `navigationDestination(item:)` and a plain
Button — a `NavigationLink` inside a `List` draws a disclosure chevron over the
card.

**Debug harness**: launch with `-uiPreviewWeather`
(`xcrun simctl launch <device> me.big3.app -uiPreviewWeather`) to open the
screens with sample data from `WeatherPreviewData`, no account needed. It is
`#if DEBUG` only and never reachable in a release build.

## 2026-09-06

### iOS: native sign-in (email code, Apple, Google, password)
The WebView's "Continue with Google" and "Continue with Apple" buttons did
nothing on iOS. Root cause: `AuthContext.tsx` calls `Browser.open()` from
`@capacitor/browser` on native, but the built app links only
`Capacitor.framework` and `Cordova.framework`. Neither `@capacitor/browser`
nor `@capacitor/app` is in `CapApp-SPM/Package.swift`, so the plugin call
throws and the flow dies silently. `npx cap sync ios` cannot add them because
the project was renamed to `big3.me.xcodeproj` and its `Package.swift` write
fails.

Rather than patch the plugins in, sign-in went native and no longer depends on
Capacitor at all:
- `Core/SupabaseAuthAPI.swift`: direct calls to Supabase `/auth/v1` for the
  email code (`otp` + `verify`), password grant, Apple `id_token` grant, and
  the provider `authorize` redirect.
- `Core/AppleSignInController.swift`: `ASAuthorizationController` with a nonce
  (SHA256 to Apple, raw to Supabase). Not `SignInWithAppleButton`, which builds
  its own request and would break nonce verification.
- `Core/GoogleSignInController.swift`: `ASWebAuthenticationSession` returning
  through `big3me://auth-callback`. Handles both implicit (hash) and PKCE
  (`?code=`) returns, since the client currently defaults to implicit.
- `Features/Auth/SignInView.swift`: email code is the primary path, password
  sits behind "Sign in with password" for accounts that have one.

Email code was chosen over a magic link on purpose: a link has to re-enter the
app through the same `big3me://` deep link that is currently broken, while a
6-digit code is typed in place with no round trip.

**Requires a dashboard change**: the Supabase "Magic Link" email template must
include `{{ .Token }}`, otherwise the message carries only a link and the user
never sees a code.

**Two-way session bridge** in `CustomViewController`: `applyNativeSession`
pushes a native session into the WebView via supabase-js `setSession`, and
`clearWebSession` signs it out. `AuthStore` records an explicit sign-out in
UserDefaults, because the WebView's localStorage copy survives app restarts
and the import bridge would otherwise sign a signed-out user back in the next
time the Chart tab loads.

Verified on the simulator: native sign-in screen renders, and the Google
button reaches the real `ASWebAuthenticationSession` consent sheet. The email
code path is unverified: it needs the template change and a real inbox.

### iOS: native SwiftUI shell replaces the WebView root
Start of the migration from a Capacitor WebView wrapper to a native app. The
Apple 4.3(b) rejection was aimed at the app reading as a repackaged website, so
screens move to native Swift one at a time instead of a rewrite.

**Project changes**
- `frontend/ios/` is no longer gitignored: it now holds hand-written Swift and
  needs history. `frontend/android/` stays ignored. The nested
  `frontend/ios/.gitignore` already excludes build output and the generated
  `capacitor.config.json` / `config.xml`, so a fresh clone needs
  `npx cap sync ios` before its first build.
- `StoreKit2Manager.swift` existed on disk but was **missing from the Xcode
  target**, so `CustomViewController` failed to compile ("cannot find
  'StoreKit2Manager' in scope") and the project did not build at all. Added to
  the target; IAP code is now actually part of the binary.
- `Native/` is attached as a `PBXFileSystemSynchronizedRootGroup`
  (objectVersion raised 60 -> 77), so new Swift files compile without editing
  `project.pbxproj`.
- `IPHONEOS_DEPLOYMENT_TARGET` 15.0 -> 17.0, required for `NavigationStack`,
  `LabeledContent` and the modern SwiftUI animation APIs. Covers iPhone XS and
  newer.

**Native layer** (`frontend/ios/App/App/Native/`)
- `Core/`: `AppConfig` (Supabase URL and anon key read from Info.plist),
  `Models` (Codable mirror of `types.ts` plus the TII zone bands),
  `APIClient` (URLSession against the same `/api/v1` REST API the web app
  uses), `AuthStore` + `KeychainStore` (session in the Keychain, single-flight
  refresh against Supabase `/auth/v1/token`).
- `Design/Theme.swift`: tokens ported from `styles.css`, resolved per trait
  collection so light and dark come from one definition.
- `Features/Profiles/`: native profile list with TII badges, sections for own
  vs followed profiles, swipe to set primary or unfollow, pull to refresh.
- `Features/Settings/`: native settings (account, appearance, about).
- `Features/Web/WebContainerView.swift`: the Capacitor controller as one tab,
  held by a singleton so switching tabs never reloads big3.me.
- `RootView.swift`: TabView shell (Profiles / Chart / Settings).

**Entry point**: `AppDelegate` now builds a `UIHostingController(RootView())`
as the window root and `UIMainStoryboardFile` was removed from Info.plist.
Capacitor is no longer the root; it renders inside one tab.

**Session bridge**: sign-in still happens in the WebView, so
`CustomViewController.importSupabaseSession()` reads the supabase-js session
out of localStorage after each page load and hands it to `AuthStore`. Deleted
once sign-in is native.

Account deletion stays in the WebView on purpose: that flow is what Apple
reviewed under 5.1.1(v), and it is not reimplemented until the rest of the
account screen is native.

Verified on the iPhone 15 Pro Max simulator: native tab bar, profile list
rendering its signed-out state, native settings, and big3.me loading inside
the Chart tab.

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
