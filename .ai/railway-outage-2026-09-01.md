# Railway outage — 2026-09-01

## Symptom

`https://big3.me` and `https://bb4q5xov.up.railway.app` both return Railway's own
404 page ("Not Found / The train has not arrived at the station"). The native
iOS and Android apps load `https://big3.me` in a WebView, so they show the same
page — the outage takes down the store apps together with the website.

## Diagnosis

Railway's edge serves that 404 when a request arrives for a host it has no
active deployment to route to. Since the **generated** Railway domain
(`bb4q5xov.up.railway.app`) returns it too, this is not a custom-domain problem:
the service itself has no active deployment.

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

## Where to look in Railway

In order, stopping at the first that explains it:

1. **Account → Usage / Billing.** A hit resource limit or a failed payment
   suspends services and produces exactly this 404. Most likely cause given
   there was no deploy and no code change for ~2.5 months.
2. **Project → service → Deployments.** Is any deployment `Active`, or are they
   all `Crashed` / `Removed` / stopped? `railway.json` sets
   `restartPolicyType: ON_FAILURE` with 10 retries, so a boot loop ends as a
   crashed deployment with no active replacement.
3. **Deploy logs of the last deployment.** `start.sh` runs
   `alembic upgrade head` before uvicorn, but tolerates migration failure, so a
   crash there points at the app itself, not migrations.
4. **Project existence.** If the project or service was deleted, recreate it and
   restore the variables below.

Once the service is healthy, re-check **Settings → Networking** so `big3.me` and
`www.big3.me` are still listed as custom domains, then push any commit to a
`claude/*` branch to trigger a fresh deploy through the auto-merge action.

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
not run since (run `26771874166`). The Apple Sign In client secret expires after
at most 6 months, so this needs its own fix.
