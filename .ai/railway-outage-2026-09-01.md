# Railway outage — 2026-09-01

## Symptom

`https://big3.me` and `https://bb4q5xov.up.railway.app` both return Railway's own
404 page ("Not Found / The train has not arrived at the station"). The native
iOS and Android apps load `https://big3.me` in a WebView, so they show the same
page — the outage takes down the store apps together with the website.

## Root cause (confirmed)

**The Railway trial expired and Railway stopped every service on the account.**
Confirmed in the dashboard on 2026-09-01: a `Trial expired` badge, the banner
"Trial Ended / Upgrade now to continue using the platform", the `SRG PLUS`
account marked `TRIAL`, and all four projects reporting `0/1 service online`.

Resolution is account-level, not code-level: upgrade the plan in Railway
(Hobby or higher), then redeploy. Nothing in this repository can fix it.

## How it presented

Railway's edge serves its 404 when a request arrives for a host it has no
active deployment to route to. Since the **generated** Railway domain
(`bb4q5xov.up.railway.app`) returned it too, the custom domain was never the
problem: there was no running service behind either hostname.

Ruled out:

- **Code / CI.** Last commit on `main` is `7e11766` (2026-06-13); all recent
  `auto-merge-claude.yml` runs succeeded. Nothing has deployed since June, so no
  release caused this.
- **DNS and Cloudflare.** Resolution is correct and unchanged:
  | host | resolves to | note |
  |---|---|---|
  | `bb4q5xov.up.railway.app` | `69.46.46.81` | Railway edge |
  | `big3.me` | `69.46.46.81` | CNAME flattening, DNS-only (grey cloud) |
  | `www.big3.me` | `104.21.96.16`, `172.67.150.64` | proxied through Cloudflare |

  Do not "fix" DNS. The apex correctly flattens to the same Railway edge IP as
  the generated domain, matching the setup recorded in `CHANGELOG.ai.md`
  (2026-03-27, Infrastructure).

## Recovery order

1. **Upgrade the Railway plan** (dashboard banner → Upgrade now). Until this is
   done nothing else has any effect: the services cannot start.
2. **Identify the project.** Four projects exist (`meticulous-perfection`,
   `tender-love`, `strong-benevolence`, `luminous-perfection`); astroconsul is
   whichever holds the `big3.me` custom domain. Idle projects still draw against
   the plan, so delete the ones that are not in use (`meticulous-perfection` has
   no services at all).
3. **Redeploy** the service and watch the build log. `start.sh` runs
   `alembic upgrade head` before uvicorn but tolerates migration failure, so a
   crash points at the app, not at migrations.
4. **Verify the variables below survived the trial expiry**, in particular the
   two that fail silently.
5. **Settings → Networking:** confirm `big3.me` and `www.big3.me` are still
   listed as custom domains and still provisioned.
6. **Trigger a clean deploy** by pushing any commit to a `claude/*` branch; the
   auto-merge action lands it on `main` and Railway builds from there.

### Data safety

User data is not on Railway. Persistence runs against Supabase PostgreSQL via
`ASTRO_CONSUL_DATABASE_URL`, and post images live in Supabase Storage, so the
Railway container is stateless. What is genuinely at risk if a project is
garbage-collected is the **service configuration**: the environment variable
values below exist only in Railway. Recovering them means pulling fresh keys
from Stripe and Supabase, so upgrade before letting the projects lapse.

## Variables to restore if the service is recreated

Two of these fail **silently** — the app boots and serves pages, but wrong:

- `ASTRO_CONSUL_PERSISTENCE_BACKEND=database` — the Dockerfile bakes `file`. If
  this is not set at runtime, the app comes up reading JSON files instead of
  Postgres and looks like an empty install with all user data gone.
- `ASTRO_CONSUL_AUTH_ENABLED=true` — defaults to `false` in
  `app/core/config.py`, i.e. auth silently disabled.

Runtime variables:

| variable | why |
|---|---|
| `ASTRO_CONSUL_PERSISTENCE_BACKEND=database` | see above |
| `ASTRO_CONSUL_DATABASE_URL` | Supabase Postgres URL; also gates the Alembic run in `start.sh`. Unset ⇒ no migrations **and** a fallback to local SQLite |
| `ASTRO_CONSUL_AUTH_ENABLED=true` | see above |
| `ASTRO_CONSUL_CANONICAL_HOST=big3.me` | `www` → apex redirect in `app/main.py` |
| `ASTRO_CONSUL_CORS_ORIGINS` | CORS middleware is only added when non-empty |
| `ASTRO_CONSUL_SUPABASE_URL` | backend Supabase calls |
| `ASTRO_CONSUL_SUPABASE_ANON_KEY` | backend Supabase calls |
| `ASTRO_CONSUL_SUPABASE_JWT_SECRET` | JWT verification for authenticated routes |
| `SUPABASE_URL` | account deletion (`auth.py`) and image upload (`images.py`) |
| `SUPABASE_SERVICE_ROLE_KEY` (or `SUPABASE_KEY`) | same two routes; admin-level key |
| `STRIPE_SECRET_KEY` | checkout |
| `STRIPE_PRICE_PRO_MONTHLY` | checkout |
| `STRIPE_PRICE_PRO_ANNUAL` | checkout |
| `STRIPE_WEBHOOK_SECRET` | webhook signature verification |
| `ASTRO_CONSUL_SENTRY_DSN` | optional |
| `ASTRO_CONSUL_RESEND_API_KEY` | optional |

Build-time variables (Docker `ARG`s in the frontend stage, baked into the bundle
by Vite — set them as Railway variables so the build picks them up):

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

If these two are missing at build time the frontend ships without Supabase
config and login breaks with no server-side error.

Apple IAP needs no variables: `APPLE_PRODUCT_MAP` and `APPLE_BUNDLE_ID` are
constants in `app/api/v1/routes/payments.py`.

## Maintenance page

`cloudflare-worker/` holds a `big3-maintenance` worker with routes `big3.me/*`
and `www.big3.me/*`. Caveat: Cloudflare Worker routes only fire on **proxied**
(orange-cloud) records. `www` is proxied, the apex is DNS-only, so as configured
the worker would not intercept `big3.me` — flipping the apex to proxied would
also mean re-checking how Railway issues its certificate.

## Unrelated finding

The scheduled `Rotate Apple SIWA Secret` workflow failed on 2026-06-01 and has
not run since (run `26771874166`). Its logs are past GitHub's retention window
(410 Gone), and the next scheduled run is 2027-01-01 (`cron: 0 12 1 1,6 *`), so
diagnosing it means a manual `workflow_dispatch`. Note that a manual run
actually rotates the live Apple client secret in Supabase Auth, so it needs a
deliberate go-ahead rather than being fired off during an outage. The secret
expires after at most 6 months, so this needs its own task.
