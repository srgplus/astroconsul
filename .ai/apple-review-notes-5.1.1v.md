# Review notes: account deletion (5.1.1(v))

Apple asked for account deletion in April 2026 and it shipped then, but the
button that leads to it opened the app's home screen and left the reviewer to
find the rest. This is the path as it is now, plus the text to paste into App
Store Connect and the script for the screen recording Apple asks for.

Written 2026-09-06, for the build that carries the `/account` deep link.

---

## 1. The path in the app

| Step | Where | What to tap |
|---|---|---|
| 1 | Cosmic weather (home) | the profiles button in the bottom bar |
| 2 | Profiles list | **Settings** in the top bar |
| 3 | Settings, Account section | **Manage account** |
| 4 | Account screen (opens on big3.me/account) | **Delete Account** |
| 5 | Confirmation dialog | **Delete my account** |

Step 3 opens the account screen directly. It is not the app's home screen, and
nothing else has to be navigated to reach step 4: the delete card is on screen
and briefly highlighted when the screen opens.

After step 5 the account and all of its data are deleted server side, the
session is cleared, and the app returns to the signed out state.

## 2. What deletion removes

`DELETE /api/v1/auth/account` removes, in FK-safe order: latest transits,
profile follows in both directions, profile invites in both directions,
profiles and their birth data, subscription records, the user row, and the
Supabase Auth record itself. Nothing is retained and there is no grace period.

## 3. Text for App Store Connect review notes

Paste as is. Plain ASCII punctuation, no dashes, so nothing is mangled in the
Resolution Center text box.

> Account deletion, guideline 5.1.1(v)
>
> Sign in with the demo account provided in App Review Information, then:
>
> 1. On the main weather screen, tap the profiles button in the bottom bar.
> 2. Tap Settings in the top bar of the profiles list.
> 3. In the Account section, tap "Manage account". This opens the account
>    screen directly (big3.me/account).
> 4. Tap "Delete Account". The delete option is on the first screen shown, it
>    is not nested behind further navigation.
> 5. Confirm with "Delete my account".
>
> On confirmation the app calls DELETE /api/v1/auth/account, which permanently
> removes the account and all associated data: profiles and birth data, charts,
> compatibility data, follows, invites, subscription records, and the
> authentication record. The user is signed out and returned to the signed out
> screen. There is no grace period and no retained copy.
>
> A screen recording of this flow is attached.
>
> The account screen is served from our web view. It is the same account screen
> our web users see, and the button opens it at its own address rather than at
> the site's home page, so the deletion control is reachable in one tap from
> the app's Settings.

## 4. Screen recording script

Record on a real device or the simulator, portrait, no cuts. One take, roughly
30 seconds.

1. Start on the cosmic weather screen with a signed in demo account.
2. Bottom bar, profiles button.
3. Settings.
4. Pause a beat on the Account section so "Manage account" is legible.
5. Tap it. Let the account screen finish loading, so the highlighted delete
   card is visible on screen.
6. Tap "Delete Account".
7. Let the confirmation dialog sit for two seconds, then confirm.
8. Keep recording until the app is back on the signed out screen.

Do not trim the loading moment in step 5. It is what shows that the button
lands on the account screen rather than somewhere the reviewer has to navigate
out of.

Use a throwaway account: this really does delete it.

## 5. Where this lives in the code

| Piece | File |
|---|---|
| The button | `frontend/ios/App/App/Native/Features/Settings/SettingsView.swift` |
| Destinations for the still-web screens | `frontend/ios/App/App/Native/Features/Web/WebScreen.swift` |
| Pointing the shared WebView at one | `frontend/ios/App/App/CustomViewController.swift` (`navigate(to:)`) |
| `/account` served as the SPA | `app/main.py`, test in `tests/test_api_v1_routes.py` |
| Opening settings on that route | `frontend/src/App.tsx` (`ACCOUNT_ROUTE`) |
| The delete card itself | `frontend/src/components/SettingsModal.tsx` |
| The deletion endpoint | `app/api/v1/routes/auth.py` |

See also `.ai/apple-review-response-v1.1-2026-04-13.md` for the April round,
which is where 5.1.1(v) was first answered.
