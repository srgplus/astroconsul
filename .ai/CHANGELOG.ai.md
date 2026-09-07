# AI Changelog

Changes relevant for AI assistants working on this codebase.

## 2026-09-06

### iOS: the hero icon says where the place came from, the dots say which page is yours
The hero always drew `location.fill` beside the place name, whatever the name
was — a fix off the device and a city someone typed on the web looked
identical. `CosmicWeatherView.place` now returns the label *and* its source, and
the icon follows it: `location.fill` for the device's own fix, `location.slash`
for a place that was typed (the transit location on the profile, or one chosen
in the settings sheet), and nothing at all when the handle is standing in for a
place — `@someone` is not a location and should not be dressed as one. It
replaces `subtitle`, which returned only the string.

The primary profile's page dot was carrying the same arrow, which is now the
house it should have been: the arrow is the hero's word for "read off a fix",
and the dot means something else — the page that is *yours*, wherever it is
being read from.

### iOS: transfer a profile to someone else
The web has had this since the invite tables landed: an owner gives a profile
away by email, and it only changes hands once the recipient accepts. iOS had
the backend and none of the UI, so the same flow now lives in the edit sheet.

`ProfileEditSheet` gains a **Transfer Profile** row between the coordinates
card and Delete. It is drawn as an ordinary row, not a destructive one — the
invite offers the profile, it does not move it, and nothing is lost if the
recipient never opens the mail. Delete stays last, where a destructive action
belongs.

`ProfileTransferSheet` / `ProfileTransferViewModel`
(`Features/Profiles/`) take the address and `POST
/api/v1/profiles/{id}/invite` — the same route `InviteModal.tsx` posts to,
owner-only, 403 for anyone else. The response carries `email_sent`, and the
confirmation reads off it: when the mailer went through it names the
recipient, and when it did not it says so and leans on Copy Link / Share Link
instead. Both are offered either way, because a link handed over on WhatsApp
beats an email nobody checks.

Accepting still happens on the web, at `big3.me/invite/{token}` — the app
claims no associated domain, so the link opens Safari. Nothing to do on the
iOS side until it does.

### iOS: the transit wheel drops the natal aspect grid
Transit mode drew both grids at once — natal-to-natal lines dimmed to half ink
underneath the transit-to-natal ones. On a phone that is roughly fifty lines
through one circle and neither grid reads.

`ChartWheelData.init(positions:aspects:showsTransits:hidesSpecialPoints:)`
(`Features/Chart/ChartWheelLayout.swift`) now fills `natalAspects` only when
`showsTransits` is false, so the mode picker swaps grids rather than stacking
them: Birth draws the natal aspects, Transit draws the transit-to-natal ones
(the left segment was labelled Chart until the picker was renamed).
The `natalInk` dimming in `WheelLayout.lines` went with it — natal lines are
never drawn beside transit lines any more, so they are always at full strength.

Nothing else changed: both rings, the glyph rows, hit testing and the
`.natalAspect` caption branch all stay as they were, and the web chart is
untouched.

### iOS: search across profiles, and a preview before you subscribe
The bottom bar had one button and a slot held empty for a second. The search
button fills that slot, on the left, which is also what keeps the dots on the
centre line of the screen: the empty slot was only ever there to balance the
list button. Both buttons on the right was tried first and costs the dot
capsule about three of its ten dots, because the empty slot has to grow to
match them.

**The search screen** (`Features/Profiles/ProfileSearchScreen.swift`) answers
in two halves, which is the whole point of it:

- *Mine* and *Following* come out of `ProfileListViewModel`, which already
  holds them, so they filter on the keystroke with no request at all.
- *Discover* / *New profiles* is `GET /api/v1/profiles/search`, debounced
  300 ms through `.task(id: query)` so a fast typist makes one request rather
  than one per letter. Before the first keystroke it shows
  `GET /api/v1/public/featured` instead.

That route drops the caller's own profiles but happily returns ones they
already follow, so the screen subtracts `list.savedProfileIds` — a plus button
next to a profile you already follow is a lie. `ProfileSummary.matches(_:)`
now holds the one match test both this screen and `ProfileListScreen` apply,
so a term that finds a profile in one finds it in the other.

**Subscribing** is either the plus on the row or the plus on the preview.
`ProfilePreviewSheet` is Weather's "city you searched for": the profile's own
sky, TII, feels-like, Big 3 and birth moment, with a cross top-left and a plus
top-right. It asks the network for nothing — everything is in the search
payload — because `GET /profiles/{id}/transits/forecast` answers 403 for a
profile you neither own nor follow. A full forecast in the preview needs that
route to admit a public read; it does not today.

Two things worth not rediscovering:

- A follow failure is returned from `ProfileListViewModel.follow`, not pushed
  into its `state`. It is called from a sheet, and turning the whole pager
  behind it into an error screen over one refused subscription is out of
  proportion.
- Both the search screen and the preview watch the same `followError`, and an
  alert raised by the *presenting* screen makes SwiftUI close the sheet to show
  it. The search screen's alert is therefore gated on `preview == nil`, and the
  preview carries its own.

`ProfileSummary` gained `natalSummary` (the Big 3 the preview shows) and
`birthMoment`, the birth date/time split that `NatalChartCard` had been keeping
to itself.
### iOS: the ••• joins the header, and Edit Profile stops floating
`ProfileEditSheet` had the two habits the other sheets have now lost. It is
filled rather than frosted — a form of text fields, date pickers and a
destructive row, all drawn for a background of a known colour — its cards are a
step in tone with no hairline round them, and the grabber is gone.

Saving moved from a full-width bar under the form to a tick in the corner where
a confirm belongs. That bar was the only thing on the screen that needed a bar
of its own, and it covered the bottom of the fields it was saving. Close moved
to the leading side to face it.

The ••• sits at the top of the header now, and inside the scrolling content
rather than pinned over it, so it leaves with the header it belongs to. As an
overlay it costs the hero no height: it rides in the band beside the status bar
that is empty anyway.

### iOS: the Google button carries Google's own mark
The native sign-in screen drew the provider as a serif letter "G", which read
as a typo next to Apple's real glyph. It now uses the official four-colour
mark, shipped as a vector asset (`Assets.xcassets/GoogleLogo.imageset`, the
same 18x18 SVG the web `AuthScreen` inlines) so both platforms show one logo.

Surface, border and label colours come from Google's sign-in branding
guidelines, not from `Theme`: white on `#747775` in light, `#131314` on
`#8E918F` in dark. They live in a `GoogleBrand` enum at the bottom of
`SignInView.swift` precisely because they are not ours to retheme. Height,
corner radius and the rounded label font stay the app's, which the guidelines
allow, so the button still lines up with Continue with Apple.

### iOS: the weather page grew a ••• menu, and Edit Profile went native
The ••• sits in the hero's top-right corner, Weather's own placement, and
offers exactly one thing depending on the page: **Edit Profile** on a profile
the account owns, **Unfollow** on a followed one.

**Ownership is decided by the presenter, not by the page.** `CosmicWeatherView`
takes `onEdit` and `onUnfollow` as optionals and shows whichever it was handed.
`WeatherHomeView` picks by membership in `model.ownProfiles`, not by
`profile.ownedByViewer` — the API has reported an owner's own primary profile
with `is_own: false` (`ProfileListViewModel` already works around this), and
trusting the flag would offer that profile's owner "Unfollow".

**The sheet is presented from `WeatherHomeView`, not from the page.** A sheet
owned by a `TabView` page goes with the page when the pager tears it down, the
same reason Settings is presented from `ProfileListScreen` rather than the
pager.

**New: `ProfileEditSheet` + `ProfileEditViewModel`.** Name, username, birth
date, birth time, birthplace, plus a collapsed Coordinates & Timezone group
that is read-only — those come from picking a place, never from typing. Delete
Profile lives at the bottom behind a confirmation alert naming the profile.
New API calls: `GET /profiles/{id}` (the only payload carrying `birth_input`,
which is where the raw birth data lives), `PATCH /profiles/{id}`,
`DELETE /profiles/{id}`, `GET /locations/search`, `POST /locations/resolve`.

**A birthplace typed over without picking a suggestion is geocoded on save**
via `/locations/resolve`, and the save is abandoned if that fails. Saving the
new name against the old city's coordinates would recast the chart for a place
the profile no longer claims — which is what the web form does today.

**Seconds of the birth time survive a save.** The picker only offers hours and
minutes, so `ProfileEditViewModel` carries the stored seconds through instead
of rounding a birth minute recorded to the second down to `:00`.

**After a save the page is rebuilt, not refreshed.** `WeatherHomeView` bumps a
per-profile counter that rides in the page's `.id`, so the forecast is recast
against the new chart. Comparing the profile summary would not do: an edit that
only moved the birthplace comes back byte-identical.

**`MinimalSpinner` has an explicit `init` now.** Its `@State private var
turning` made the synthesized memberwise initializer private, so the arc could
not be used outside `CosmicWeatherView.swift`.

**Known, unrelated:** `DELETE /api/v1/profiles/{profile_id}` verifies no
ownership — `PATCH` calls `_verify_ownership`, `DELETE` does not. Any signed-in
user can delete any profile by id.

## 2026-09-07

### iOS: the device is told when the feels-like category changes
The twelve categories in `app/domain/astrology/tii.py` (`_FEELS_LIKE_MATRIX`,
`Calm` … `Explosive`) now reach the phone as notifications on the days they
change.

**They are local notifications, not APNs pushes, and that is the design.** The
engine casts one reading per local *noon*, so a category change always lands on
a day boundary and `GET /transits/forecast` already knows every one of them up
to 30 days out. That makes the whole schedule computable in advance and
handable to iOS in one go, firing whether or not the app is running. A push
would need an APNs key, a device-token table and a server cron to produce the
same banner, and would go quiet the moment any of the three broke. If real
pushes are ever wanted — a same-day revision, say — the change list is the
seam to move server-side, not the scheduling.

- **`Native/Core/CategoryChange.swift`** is the rule, deliberately free of
  UserNotifications and UIKit so it can be compiled and exercised on its own:
  `list(in:)` turns a forecast into the days whose label differs from the day
  before, and `fireComponents(hour:minute:in:)` dates the alert in the zone the
  forecast was cast for. **Day zero is skipped on purpose** — it has no
  predecessor in the window, and the run that scheduled the window today fell
  in has already queued it.
- **`Native/Core/CategoryAlerts.swift`** owns permission, the queue and the
  `BGAppRefreshTask`. It rebuilds wholesale rather than diffing, so a revised
  forecast can never leave yesterday's alert behind; every request it queues
  carries the `category-change.` prefix so a rebuild only clears its own work.
  Horizon 14 days, throttled to one forecast every 6h (each day is a separate
  ephemeris pass server-side), and the queue is dropped on sign-out.
- Scheduled for the **primary profile only**. Someone following a dozen charts
  does not want a dozen banners a day.
- Settings gains a Notifications section: toggle, time of day, and a live count
  of what iOS is actually holding — `syncState()` reads the pending list back
  rather than trusting a counter no rebuild has touched this launch.
- `Info.plist` gains `UIBackgroundModes: fetch` and the
  `BGTaskSchedulerPermittedIdentifiers` entry. **`BGTaskScheduler` traps unless
  every permitted identifier has a handler registered before
  `didFinishLaunchingWithOptions` returns** — hence the call at the top of
  `AppDelegate`, above the window.
- **`-uiPreviewAlerts`** joins `-uiPreviewWeather`: it schedules from the sample
  forecast, prints the pending queue with its fire dates, and delivers one
  banner 15s out, so the whole path can be checked on a simulator without an
  account.

**The temperature is a picture as well as a line.** `Native/Design/CategoryArtwork.swift`
renders a 512pt square per alert — a pastel gradient picked for the category
with the reading drawn on it — and attaches it, so the banner reads
"⚡ Dynamic / 44° / Easing from Flowing" with the card beside it. **The badge at
the leading edge of a banner cannot be changed**: it is the app icon, drawn
small by SpringBoard, and no ordinary notification can replace it. An
attachment is the only slot an app owns, and iOS shows it as the thumbnail next
to the text and full width once the banner is expanded.

**The reading is in the subtitle as well, and that is not redundancy.** An
attachment is a thumbnail *the system* renders, through QuickLook, and a system
that declines has to not take the temperature down with it. It does decline in
the Simulator: SpringBoard logs `QLThumbnailErrorDomain 102` for every card,
while `QLThumbnailGenerator` run against the very same file inside the very
same simulator returns an 80×80 thumbnail happily — so the file is sound, the
attachment is stored, and it is SpringBoard's own thumbnail path that fails
there. **The card has therefore never been seen rendered; it is verified only
as far as "iOS accepted it and QuickLook can read it".** Check it on a device
before believing the picture half.

- Twelve palettes, one per category, not four per TII zone: sharing a zone would
  put `Calm` and `Grinding` on the same blue, which defeats a notification whose
  whole content is that the category changed. Kept in separate hue families so
  no two are confused at 38pt.
- System rounded numerals at `.medium`, not the hero's Space Grotesk
  ultraLight — the card is drawn at 512 and shown at 38, and a display face at
  a hairline weight disappears at that reduction.
- `UNNotificationAttachment` **moves** the file into its own store, so every
  card is written under a fresh UUID; handing the same URL over twice fails,
  and the schedule is rebuilt on every foreground.

### iOS: the reading is a moment somewhere, and now you can say which
A chart is fixed; a transit is not. The weather screens always read the present
at the profile's own place, which is the right default and was the only option.

- **`TransitMoment`** is what the reader picked instead — an instant, a zone,
  and optionally a place. `CosmicWeatherViewModel.chosen` holds it, and both
  halves of the screen follow: the report is cast for that instant, and the
  forecast window starts on its date rather than today, so the sky over the
  cards and the cards are the same day. It never falls back to the device zone
  the way a saved setting does — retrying a chosen moment somewhere else would
  answer a question nobody asked.
- **`start_date`** is a new optional query parameter on
  `GET /profiles/{id}/transits/forecast`, defaulting to today as before.
- **`TransitSettingsSheet`** is the form, opened from the stamp under the
  profile's name: date, time, a city search on `/locations/search`, and the
  zone the picked city carries — moving the clock with it, since the hour on
  the picker is a wall clock reading. It is a plain grouped `Form` in a half
  sheet with Cancel and a tick, so the row metrics and inset hairlines come
  from the system instead of from constants that only nearly match.

### iOS: sheets stop being frosted, and the list stops pretending it is not on a sky
Two opposite mistakes, one cause: a surface has to know what it is standing on.

- **The sheets are opaque.** The transit detail sheet and Settings both drew a
  blurred sky behind system controls built for a background of a known colour,
  and every one of them was being propped up by hand — translucent row fills,
  a hairline round each card. They use the system's grouped pair now
  (`Theme.sheetBg` / `Theme.sheetCard`), no borders, with Weather's own close
  button and no grabber beside it.
- **The profile list is told it is dark.** It stands on a frosted night sky, so
  left to the device's appearance its search field, group name and Settings
  button all resolved for a white page and landed as dark ink and light pills
  on the dark wash. The screen forces `.colorScheme(.dark)`; Settings is
  presented from outside that override so it still opens in the app's own
  appearance.
- **The wordmark is centred**, the group name moved onto its line, and it
  appears only once cards start going under the bar. Tracking which group is
  on screen is done from the rows' own appear and disappear: a `List` hosts its
  rows separately and their preferences never reach the screen, which is the
  obvious way to do it and does not work. The bar's own material is hidden for
  a wash that fades out, so cards pass under it rather than being cut off.

### iOS: two marks removed, because the line already said it
`TransitProgressBar` drew a tick standing above the track for each moment the
aspect is exact, and a 10pt dot for now. The ticks are gone; each exact moment
is a dot the width of the track, sitting in the line — a tick has to be read
against the line to be placed at all, a dot is the point itself. Now needs no
mark either: the filled length is where now is.

The stamp in the hero lost its capsule for the same reason. The chevron says it
is a control, and the plate was saying it a second time.

### iOS: the wheel answers a tap
Stage three. A glyph or an aspect line is tapped and named in a caption under
the wheel, and a transit aspect's caption opens the detail sheet the transits
card already uses. This is the phone's replacement for the web ring's hover
tooltip, which has no equivalent here.

**`WheelLayout` is the change that matters.** The geometry used to live inside
the `Canvas` closure, where a gesture cannot see it. It is now built once per
size in `ChartWheelLayout.swift` and read by both the drawing and the hit test,
so a touch target cannot drift from the thing it is meant to hit. Working it
out twice is how you get a wheel whose glyphs sit half a degree from where they
can be tapped, with neither copy looking wrong on its own. `Metrics`, `Ring`
and `Placement` moved there with it, and the wheel's inputs are now one
`ChartWheelData` rather than eight properties.

- **Glyphs beat lines**, and within each kind the nearest wins, so a tap
  between two crowded glyphs takes the closer one. The reach is 16 points
  against a 13-point glyph: a fingertip is 44, and since the nearest wins,
  reaching past the neighbours costs nothing.
- The glyph's tap target follows the **glyph**, not the tick — a crowded row
  nudges glyphs off their true angle, and you aim at what you can see.
- Tapping the same thing again clears it, so the caption can be let go of
  without hunting for empty space between the rings.
- A selection does not survive Chart/Transit or Special points: the rings are
  rebuilt, and the body may not be drawn any more or may have moved.
- The caption sits **under** the wheel, not in the middle of it. The middle is
  about seventy points across once five rings are drawn, and a readout that
  fits there in one combination is clipped in another.
- Haptics are `@State`, not a stored `let`. A stored property on a `View` is
  rebuilt every time SwiftUI rebuilds the struct, and a generator that new has
  not warmed the Taptic Engine, so the first tap after any redraw was silent.

**No rotation, deliberately.** The card lives inside a vertical `ScrollView`
inside a horizontal pager, so a one-finger drag on the wheel fights both, and
the wheel is a big target people scroll through. A two-finger `RotationGesture`
would not conflict but nobody would find it. Neither earns its keep next to
tapping, and rotating also breaks the convention the house numbers and axes are
drawn to, that the ascendant is on the left horizon.

### iOS: Cosmic Climate, one line per season
The web widget gives each long transit a card: emoji, name, a paragraph of
meaning, a line of advice, a bar. On the native weather screen it is a
dashboard row instead — glyphs, the arc of the window, the months it spans,
nothing else — in the same shape the Active transits rows have, sitting
directly under them (`CosmicClimateCard`).

`cosmic_climate` has been in the report payload all along and was going
undecoded on iOS. `TransitReport` now carries it and `CosmicWeatherViewModel`
publishes it in the order the engine already ranked it — window over orb,
longest and tightest first — so the card ranks nothing itself.

Rows the report sends without timing are dropped rather than drawn empty: the
bar and the months are the whole row here, and the report's fast phase sends
aspects with no window at all.

The harness had nothing to show in the new card, so two more rows joined the
sample aspects: Neptune sextile AC (orb 1.53) and Neptune square Moon (orb
1.92). Both are true to the arcminute against the sample positions — the rule
that any preview row has to survive being drawn on the wheel still holds — and
both run the months an outer-planet transit actually runs. `climate` is then
filtered out of that same list the way the backend filters it, so an aspect
cannot carry one window on the transits card and a different one below it.

A row answers "when", so tapping one opens `TransitDetailSheet` for "what" —
the same sheet the Active transits rows open, retrograde marker and all. The
card takes `retrograde` and `positions` for it, the way the transits card
already does.

### CI: the red run on every merge was not a failure
Every merge left a red `CI` run behind, triggered by `pull_request`, with a
"workflow file issue" and **zero jobs**. Three in one evening, each one costing
a manual check of whether the merge was actually broken. It was not.

The push run and the pull_request run fire on the same commit, and the push run
is the one branch protection reads: required checks match by name against the
head SHA, and the push run is on that SHA. The PR run was a duplicate that
raced the auto-merge and lost — the merge deletes the branch and
`refs/pull/N/merge` with it, GitHub can no longer resolve the workflow, and the
run dies before it creates a single job.

The three jobs already carried an `if` meant to skip that run. A job-level `if`
is evaluated only once the jobs exist, which is the thing that never happened,
so it worked exactly when the race was won and not otherwise (hence some runs
"skipped" and some "failure"). There is no head-branch filter for the
`pull_request` trigger, so the only way to not lose the race is to not enter
it: the trigger is gone and `push` now covers `'**'` instead of
`[main, 'claude/**']`, which is what a hand-raised PR from another branch name
needed the PR trigger for. A PR from a fork now gets no checks; this repository
has none.

### iOS: the wheel draws aspects to the angles, and the preview data stopped lying
Two findings from checking, endpoint by endpoint, where the wheel's aspect
lines actually attach.

**Aspects to AC and MC were being dropped.** `drawable()` filters ASC and MC
out of the glyph rows, because they are drawn as arrows through the rim
instead — so every aspect naming one had no placement and was silently
skipped. The web ring does the same, but on the web there is no transits card
directly above the wheel listing the aspect you cannot find on it.
`axisPlacements(_:)` gives them a place: their own angle, at
`zodiacInner - notch`, which is where the arrow's inner end already is. Every
other body sits further in, so a line to an angle always leaves the zodiac
band inward and lands along the arrow it names. Verified: both ends land at
r=124.0 with zodiacInner=126.0 and notch=2.0.

**The preview transit aspects were geometrically false.** Of ten rows, two
matched the positions they were supposedly measured from. "Mars trine Pluto"
sat 29.53° apart; "Pluto conjunction ASC" sat 239.93° apart. They were written
for a card that only ever printed two glyphs and an orb, so nothing checked
them. The wheel checks them: a trine drawn between two bodies 30° apart looks
like a bug in the renderer. All ten are now real for the positions below them,
to the arcminute, and three of them name an angle so the new lines are
exercised. **Any row added to `WeatherPreviewData.aspects` has to survive
being drawn.**

The natal-to-natal and transit-to-natal attachments were checked the same way
and were correct: each end lands on the inner edge of its own row, so a
planet-and-point pair gets two different radii (99.0 and 79.0), and the natal
end of a transit line is always inward — not by luck, but because the transit
ring is strictly inside the natal one, which makes the projection negative
every time.

### iOS: the Moon leaves the summary card and gets its own panel
It used to be a chip in `TodaySummaryCard`'s conditions row — "🌔 Waxing
Gibbous · 78%" next to the retrograde count. `MoonCard` now stands on its own
under the forecast, laid out the way Weather lays out its moon module: the
phase named in the header, a short column of readings, the sphere on the right.

- **The disc is drawn, not photographed.** `MoonDisc` paints the near side in a
  `Canvas` — the maria as one union of overlapping ellipses so the coastline
  comes out ragged rather than as a row of circles, a scatter of craters from a
  fixed seed, a radial highlight and limb darkening for volume. `MoonLitShape`
  closes the lit limb with the terminator, whose projected half-width is
  `cos(elongation)`, signed; `MoonShadowShape` fills disc-plus-lit even-odd, so
  what is left is exactly what is in shadow. No asset, every phase from one
  number.
- **That number is `moon_phase.phase_angle`,** which the engine already sent
  and iOS was throwing away. `MoonPhase` decodes it and derives the age and
  both countdowns from it; a response without one falls back to illumination
  plus the phase name, which say the same thing between them.
- **Where Weather prints moonrise and moonset, this prints the sign.** Rise and
  set need a horizon and the forecast is cast for a chart, not a viewing spot.
  `AstroGlyph.sign` gained the zodiac, each pinned to text presentation with
  U+FE0E — bare, those code points render as purple emoji tiles.
### iOS: the natal card sets the big three apart and opens the rest
Two things the card was missing. Sun, Moon and Ascendant — the three the app
is named for — sat in the same run as Midheaven and the personal planets, and
tapping the card did nothing, so the rest of the chart had nowhere to live.

- The big three are now their own block, set off by a gap rather than a
  heading: over three rows a label costs more room than it earns. Their names
  carry slightly more weight than the rows below them.
- Tapping the card unfolds the outer planets and the special points, banded
  and labelled the way `ActiveTransitsCard` bands its aspects, with a chevron
  in the header saying which way it goes. `onTapGesture` on the card body does
  not cost the pager its horizontal swipe — checked on the simulator.
- No new request: `natal_positions` already carries all 19 objects, so the
  drawer is reading what the card had all along.
- `WeatherPreviewData` gained the six natal points it was missing (Jupiter,
  Uranus, Selena, South Node, Part of Fortune, Vertex), so `-uiPreviewWeather`
  draws both bands in full rather than half of one.

### iOS: the wheel's aspect lines lost their colour, on purpose
The web ring gives each aspect a hue. That works on white; it does not work
here, and the reasons are worth writing down before someone puts the colours
back.

- The card floats over a sky that is **blue, green, orange or red** depending
  on the day's TII. A green sextile line vanishes over a green sky.
- Those are the same four hues the app already spends on the TII zones, so one
  orange would have meant two unrelated things on one screen.
- Colour was carrying a *category* (which aspect), which is the one job an
  instrument face does with shape instead.

`AspectStyle` now holds no colour. The ink is `transitPalette.primary`, so the
lines are white over the sky and dark on a surface without asking. The aspect
is carried three ways:

- **Solid is hard, broken is soft.** Conjunction, opposition and square are
  unbroken; trine is a long dash, sextile a dot.
- **Weight ranks within the family.** Conjunction is the heaviest line on the
  wheel at 1.5, sextile the lightest at 0.9.
- **Orb sets the ink** (`AspectStyle.ink(orb:)`), falling to a little over half
  by 6°. The coloured version could not say this at all, and it is the thing
  you want to see first: which transits are actually close.

### iOS: skeletons instead of an empty weather page
Removing the mid-screen spinner left the page as a hero over bare sky while
the reading was computed, which is worse than the spinner was: nothing says
anything is coming, and each card shoves the page down as it lands.

`WeatherSkeleton` stands in for all three cards — the summary's three lines
and its transit rows, the ten forecast rows, a band of active transits — so
the layout is already the layout and the data fills it in. One pulse animates
the whole card; bars fading out of step read as a glitch rather than as
waiting. Widths are fixed rather than fractions of the card: a fraction needs
the card's width measured back into the layout, and the extra pass buys
nothing for bars nobody reads.

Old cached data would be better still on a repeat visit, but nothing caches a
report yet — only `latest_transit`, which the hero already falls back to.

### iOS: one loader on the weather page, and it is a ring
`ProgressView`'s spokes are a system alert's indicator. At 13pt on the sky
they read as a stuck widget rather than as work in progress, and the grey
they are tinted with disappears on a dark sky where every other mark in the
hero is white. `MinimalSpinner` is a thin arc that turns, trailing the date in
the stamp capsule.

The page has no other loader now. The large one mid-screen and the one inside
the Active Transits card are gone: the stamp already says the reading is being
computed, and a second spinner in the middle of an empty page read as a screen
that had failed to draw. The cards simply arrive.

### iOS: the harness can play the loading states
Swiping the weather harness never showed a spinner, which reads as "it does
not load" but is the harness working as built: every page is handed a model
seeded with `.loaded`, and `CosmicWeatherView.task` returns early for anything
but `.idle`, so no request is ever made and no loading state is ever drawn.

`-uiPreviewLoading` alongside `-uiPreviewWeather` now holds the seeded data
behind the real states for three seconds each — forecast first, report a beat
later, the order an account sees — so the spinners can be checked without
signing in:

    ./scripts/ios-simulator.sh --run -uiPreviewWeather -uiPreviewLoading

### iOS: the dot capsule is the app's glass, and the stamp carries the spinner
The bar held two surfaces that did not match. `UIPageControl.backgroundStyle =
.prominent` draws Weather's capsule, but it is UIKit's own light material and
takes none of `weatherGlass`'s dark tint, so beside the list button it read as
a different material sitting on a different sky.

The control now runs `.minimal`, which draws no background at all, and
`WeatherBottomBar` wraps it in the same glass the button uses.

Sizing the capsule to the dots took measuring rather than guessing. The
control reports no padding of its own — one dot is 12pt, each further dot one
17.67pt pitch — so 33 profiles ask for 577pt, it is handed the bar's width
instead, and it windows the dots and centres them, leaving its bounds mostly
empty for a capsule to wrap. `sizeThatFits` now caps the width at that window,
derived from the control's own metrics rather than constants of ours. The cap
is ten dots, not the eleven a windowed control draws, because it shrinks the
outer ones as it windows.

Separately, the hero's date capsule now carries the spinner while the transit
report for that moment is still in flight, so the stamp and its progress are
one thing rather than two.

### iOS: the hero says when, in what words, and how tense
Three things the web hero has and the native one did not.

- **When.** A transit reading is a moment, not a day, so a capsule under the
  name prints it — "Sun, Sep 6 at 4:14 PM" — in the profile's own zone, not
  the device's. `CosmicWeatherViewModel` publishes the instant and zone it
  built the request from, rather than the hero reading the clock a second time
  and drifting from what is on screen.
- **In what words.** Under the feels-like label sits the short line the web
  calls a time modifier: "In the flow" at four in the afternoon, "Drift into
  peace" at one in the morning. The API does not send it — the web app reads
  `data/feels_like_time_modifiers.json` directly — so `FeelsLike.headline`
  inlines the English half of that file. 48 short strings did not warrant a
  bundled resource and a decode path, but the JSON stays the source of truth.
- **How tense.** `TensionBar` puts the engine's tension ratio under the
  headline as a short track and a percentage. It is a footnote to the reading
  above it, so it is 132pt wide and 4pt tall and says nothing else.

### iOS: the list's glass frosts the sky that is actually behind it
Opening the profile list over a blue sky gave a green sheet.

Two causes, both fixed. `WeatherHomeView` keyed the backdrop to
`profile.latest_transit.tii`, but a page's sky comes from its own loaded
forecast, and the two disagree by a whole zone often enough to notice. Pages
now report the zone they settled on through `SkyZoneKey`, keyed by profile
because a paging `TabView` keeps every page alive and they all contribute; the
stored TII is only the fallback until a forecast lands. And since the sky
gained footage, `WeatherGlassBackdrop` frosted a gradient the sky no longer
is — it now draws the same `SkyVideo` under the material.

## 2026-09-06

### iOS: transit rings and aspect lines on the wheel
Stage two. The wheel now carries up to five rings and both aspect grids, and
the card grew the web chart's Chart/Transit switch.

- **Five rings, not three.** A "pair" is planets outside, special points
  inside, and there is one pair for the natal bodies and one for the
  transiting ones. Both switches on: zodiac + 4 = 5. `Metrics` takes
  `showsTransits` and `showsSpecialPoints` and thins the bands to suit —
  five rings in one circle is a different budget from three, and with the
  inner rows off the transit pair moves up into the room they vacated.
- **The zodiac rim is inverted**, black with light ink, as on the web chart.
  It is the one part of the wheel that ignores `transitPalette`: it makes its
  own contrast rather than borrowing the sky's.
- **Aspect lines.** `AspectStyle` ports `ASPECT_LINE_STYLES` with the hues
  lifted, because the web draws on white and these draw over a sky. Natal
  lines leave from their band's inner edge; transit-to-natal lines leave from
  whichever edge faces the other end, by the radial dot product the web uses,
  so a line never crosses its own band.
- The natal grid drops to half ink once transits are on. Both grids at full
  strength is fifty lines through one circle, which on a phone is a ball of
  wool. The transits are the news; the natal grid is the background.
- The report payload gained `natal_aspects` (`transit_builder.py`) next to
  `houses`, decoded as `NatalAspect`.
- `WeatherPreviewData.natalAspects` is seven aspects that are all real for
  the positions above them, to the arcminute. A made-up grid would draw lines
  the wheel's own geometry contradicts, which is worse than no preview.

### iOS: the birth chart wheel, drawn natively
The chart was the last big thing only the WebView could show. It is now a
SwiftUI `Canvas` on the cosmic weather screen, under Active Transits. This is
stage one: the natal wheel, static. The transit ring and tap-to-detail follow.

- `Design/ChartWheelGeometry.swift` is the maths, ported from
  `frontend/src/components/NatalZodiacRing.tsx`: `WheelMath.angle` rotates the
  chart onto the ascendant, and `WheelMath.spread` is a line-for-line port of
  the web `spreadGlyphs`, which shoves colliding glyphs apart along the band
  and then lets each slide home if the room is there. `Zodiac` holds the sign
  names and glyphs.
- `Features/Chart/ChartWheelView.swift` draws it. Not a transcription of the
  web ring: no curved sign names, no tooltips. It follows the instrument faces
  in Weather instead - 5° ticks around the rim, a taller one per sign, upright
  glyphs, hairlines. One `Canvas`, not a stack of shape views.
- The centre is deliberately empty. That is where the transit rings go.
- **Sign glyphs need `\u{FE0E}` and a non-rounded font.** U+2648-2653 are emoji
  code points, and inside a `Canvas` SF Rounded renders a missing glyph as a
  tofu box rather than falling back. `ChartWheelView.glyph(_:)` asks for no
  design for exactly this reason; `label(_:_:)` keeps `.rounded` for text.
- The report payload gained `houses` (`transit_builder.py`), the twelve cusps.
  It is the only chart call the native app makes, and the house ring needs
  them. `TransitReportResponse` is `extra="allow"`, so nothing else changed.
- `ChartPosition.longitude` decodes the field the API already sent and nothing
  read; `wheelLongitude` falls back to sign + degree so hand-written previews
  still place correctly.
### Web: the Chart widget opens its own details drawer
Reading a chart meant leaving the widget: tapping it threw up the full-screen
Birth Chart popup, which is also where Edit and Transfer Ownership live. The
widget now carries a "Details" button that unfolds `NatalPositionsTable` in
place, so the positions are one tap away and the popup stays what it is.

- The drawer is a prop on `ProfileSummaryCard` (`drawer`), set by the widget
  only. In the popup the same table is already further down the page.
- The widget's own `onClick` still opens the popup, so the toggle and the
  drawer body both `stopPropagation` — otherwise reading a row would launch
  the popup on top of it.
- The drawer cancels the widget's 16px padding with a negative margin, so the
  table's dividers run edge to edge the way they do in the popup.
- Fixed alongside, because the drawer is where it shows: a body the ephemeris
  has no data for (`build_unavailable_position` sends nulls) printed
  "sign.null" and "°null′" — the Chiron row on a real profile. Sign, glyph and
  degrees now fall back to a dash.

### iOS: the natal chart under the weather
`NatalChartCard` closes the weather screen with the chart every reading above
it is cast against: Sun, Moon, Ascendant, Midheaven, Mercury, Venus and Mars,
each with its sign, degrees, house and ℞ when the body was retrograde at
birth, then the birthplace and birth moment, with the age in the header.

- No new request. The transit report that already feeds Active Transits
  carries `natal_positions` and `angle_positions`, and the view model indexes
  both into `TransitPositions.natal` — the card just reads that.
- Signs are written out, not drawn: U+2648-2653 resolve through the emoji
  font, which the simulator draws as tofu. Same call `TransitDetailSheet`
  already made. Houses use the `house` SF Symbol rather than the web's △,
  which is the glyph for a trine.
- ASC and MC show degrees only — they are the cusps of houses 1 and 10 by
  definition, so a house number there repeats the label.
- The birth moment is read out of `local_birth_datetime` as text, never
  parsed into a `Date`: it is already local, so a timezone conversion would
  move the clock off the birth certificate.
- `WeatherPreviewData` gained a natal Mercury, retrograde, so `-uiPreviewWeather`
  shows the ℞ column instead of leaving it to be assumed.

### iOS: the weather screens ask the device where you are
`ProfileSummary.currentLocationName` moved the label off the birthplace, but
it could only offer what was on file, and `latest_transit.location_name` is
only filled when someone types a city into the web Transits tab. Most accounts
never have, so the label still had nothing better to show than the timezone's
city — and in the preview harness every sample carried the *same* string as
its birthplace, which made the fix look like it had done nothing.

- `Core/DeviceLocation.swift` takes one CoreLocation fix per app run and
  reverse-geocodes it to "City, Country". Accuracy is deliberately
  `kCLLocationAccuracyKilometer`: the output is a city name, so street-level
  digits would be paid for and thrown away. `NSLocationWhenInUseUsageDescription`
  is in Info.plist; the prompt is raised from `WeatherHomeView.task`, over the
  screen whose label it fills in.
- It applies to the **primary profile only**, on the hero and on its card. The
  primary is the person holding the phone — Weather's "My Location" at page one
  — and a followed profile's owner is somewhere else entirely. Everyone else
  keeps `currentLocationName`.
- Denied or undecided is not an error: `placeName` stays nil and the old chain
  answers. Failures are logged, never swallowed.
- `WeatherPreviewData` now gives every sample a birthplace and a different
  current city, and leaves every fourth filler profile without a current
  location, so the harness shows the fallback too.

Still open: the device location is display-only. It is not sent to the backend,
so the web app, the saved `latest_transit` and the transit engine's houses all
still use whatever was typed by hand.

### iOS: the weather screens name where you are, not where you were born
The hero and the list cards labelled every reading with `profile.location_name`
— the birthplace — so a person who moved was told the sky over a city they left.

- `ProfileSummary.currentLocationName` is the one place that answers "where is
  this person now": `latest_transit.location_name` (the transit location typed
  by hand in the web Transits tab) first, then the city of
  `latest_transit.timezone` ("Europe/Minsk" → "Minsk") for readings saved
  without a place. Birth location is deliberately not in the chain; when
  nothing is known the hero shows the handle instead of a place we cannot
  vouch for.
- `CosmicWeatherView` and `ProfileWeatherCard` both read it, so the list and
  the detail screen still agree. Search matches either location.
- `WeatherPreviewData.profile` is now born in Brest and living in Warsaw, so
  the `-uiPreviewWeather` harness shows the difference rather than hiding it
  behind one city in both fields.
- Next step: detect the location automatically instead of relying on the
  transit form.

### iOS: Settings on glass too, and where the glass gets its colour
Both presented screens — the profile list and Settings — sit on
`WeatherGlassBackdrop` instead of a `Theme.bg` fill, and Settings' rows use a
translucent material rather than `Theme.surface`.

The colour comes from the page's own sky, drawn inside the backdrop, not from
the screen underneath. A sheet's presenting screen is not rendered behind it:
`presentationBackground(.clear)` over a sheet shows the window's white, not
the weather page, and a material over that frosts the same white into grey. So
`WeatherHomeView` passes the visible page's `TiiZone` down, the backdrop draws
that gradient and frosts it, and the result is what would have shown through.
`glassEffect(.clear)` and `.opacity()` on a material are both dead ends here —
they drop the vibrancy and leave a flat light fill.

### iOS: Active Transits, compact rows with the arc each one travels
A third card under the 10-day forecast lists every aspect currently inside
orb, laid out the way the forecast lays out its days: one line per transit,
glyphs where the weather icon goes, the transit's arc where the temperature
bar goes, then the orb and the strength. The name stays off the row — three
glyphs already say it, and the line stays scannable. Rows are banded by how
fast the transiting body moves, and the header's switch narrows the list to
what is actually close.

- `Features/Weather/ActiveTransitsCard.swift` is the card, with `TransitGlyphs`
  and `StrengthLabel` beside it because the sheet reuses both. `SmallSwitch` is
  there too: SwiftUI's `Toggle` never sees a tap inside the pager's scroll view
  — the same gesture conflict that keeps a plain-styled `Button` from firing —
  and at 51x31 it towers over a 13pt header line with no supported way to
  shrink it, so the switch is drawn from two shapes and a tap gesture.
- `Features/Weather/TransitProgressBar.swift` is the arc. The track is the
  whole window, the gradient under it is the influence bell curve peaking
  where the aspect perfects, and it is masked back to now so the filled part
  reads as elapsed. The palette and the per-planet weights are the web app's
  (`buildTransitGradient`), which is why the Moon's bar tops out yellow while
  Pluto's runs to red. `showsDates` adds the start, peak and end labels; the
  compact row has no space for them, the sheet does. The peak label rides its
  notch via `.position`, so it centres without measuring the text.
- `Features/Weather/TransitDetailSheet.swift` opens on a tap: title, strength,
  orb and status; the window with its dates and every exact pass; and where
  both bodies sit. It is *not* drawn on the sky — Weather's own detail sheets
  drop the weather for a plain surface, and a sky-coloured sheet both fought
  the page behind it and, when the colour was derived from the transit, read
  as a severity the engine never assigned. So it sits on `Theme.bg` and its
  ink follows the system appearance.
- `Design/TransitPalette.swift` is how the shared pieces manage that. The same
  rows are drawn over a saturated sky, where they must be white under both
  appearances, and on a plain surface, where they must flip; one palette in the
  environment beats threading a colour through every subview.
- The report's `meaning`, `action` and `keywords` are the sheet's obvious next
  section and are deliberately not wired up yet, so `ActiveAspect` leaves them
  undecoded rather than carrying dead fields.
- The data is a second request: `POST /transits/report` with
  `include_timing: true`, which is the slow half and the only source of
  start/peak/end. `CosmicWeatherViewModel` runs it alongside the forecast
  under its own state, so the forecast cards draw without waiting, and it
  retries on the device's plain timezone when the profile's saved transit
  settings are stale — the same fallback `App.tsx` makes.
- `Design/AstroGlyphs.swift` ports the planet and aspect glyph tables and the
  three bands. Nothing is bundled: every code point resolves through Apple
  Symbols, checked on a simulator down to Chiron and Lilith. The zodiac signs
  are the exception and are written out — U+2648-2653 resolve through the
  emoji font, which the simulator draws as tofu and a device draws in colour.
  The house on a positions row is an SF Symbol rather than the web's △, which
  on a screen about aspects reads as a trine.
- Three things this surfaced elsewhere. `WeatherCard`'s border overlay was
  hit-testing, so it swallowed taps meant for anything inside a card. The
  pages ran under the floating bottom bar: they now take a `bottomInset` the
  way they already took a `topInset`, and pad by
  `WeatherBottomBar.height(bottomInset:)`. And the hero's `H:34° L:4°` line is
  gone — one TII a day means there is no daily high and low, so the figure was
  the ten-day spread wearing a label that promised something else.

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
### Docs: the development workflow is written down
`.ai/SKILL.md` explained the product and the formulas but never how work
reaches main, so every session had to rediscover it. New section 1a covers the
branch → PR → main flow, the one-simulator-per-worktree rule with the exact
`big3 <worktree>` name, and a standing instruction to update the file in the
same PR that moves the architecture. `CLAUDE.md` gained the naming convention
and says to delete hand-made simulators that sit outside it — three had already
appeared under three different names.

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
