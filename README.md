# Astro Consul MVP

Minimal Swiss Ephemeris prototype for validating natal chart accuracy, saving natal charts,
and running deterministic transit reports from the browser UI.

## Architecture snapshot

The project now has a modular-monolith backend foundation:

- `app/main.py`: FastAPI application factory, CORS, optional Sentry, frontend serving
- `app/api/v1`: versioned production-facing API routes
- `app/application/services`: orchestration layer for charts, profiles, transits, health, and location lookup
- `app/domain/astrology`: domain wrappers around the Swiss Ephemeris calculation modules
- `app/infrastructure/persistence`: SQLAlchemy models and session management
- `app/infrastructure/repositories`: file-backed and database-backed repository implementations
- `frontend/`: Vite + React SPA scaffold for the next frontend migration step
- `server.py`: compatibility shim that preserves the legacy import surface and `uvicorn server:app`

The current browser UI still falls back to `templates/index.html` until a built SPA is present in
`frontend/dist/`. The backend will automatically serve the SPA once it has been built.

## Project structure

```text
.
├── chart_test.py
├── requirements.txt
├── README.md
├── ephe
│   ├── sepl_18.se1
│   ├── sepl_24.se1
│   ├── semo_18.se1
│   └── semo_24.se1
└── swiss-test
    └── chart_test.py
```

## Requirements

- Python 3.11 recommended
- `pyswisseph`

## Installation

```bash
pip install -r requirements.txt
```

## Run

From the project root:

```bash
uvicorn server:app --reload
```

You can also run the new application entrypoint directly:

```bash
uvicorn app.main:app --reload
```

Open [http://127.0.0.1:8000](http://127.0.0.1:8000).

The browser UI now has two modes:

- `Product Flow`: create a saved natal chart from local birth date, birth time, timezone, and
  location coordinates, then run a transit report from that saved chart.
- `Engineering Debug`: call `/natal` directly with decimal UT inputs and inspect the raw JSON.

The main product flow now keeps local datetime as the primary user-facing value. Technical
metadata such as UTC timestamps, chart identifiers, Julian day, and file paths stays tucked
behind `Technical details`, while debug mode remains available for engineering verification.

Location name now resolves coordinates and timezone automatically for the main product flow.
Advanced timezone and coordinate fields remain available as manual overrides, but normal users
should not need to enter latitude and longitude by hand.

The product flow is:

1. Create a natal chart
2. Reuse the saved chart ID
3. Generate a transit report

The engineering debug calculator is still available at the bottom of the page for low-level verification only.

If you want the standalone script output instead of the browser UI, you can still run:

```bash
python chart_test.py
```

or:

```bash
python swiss-test/chart_test.py
```

## Test birth data

- Date: 15 November 1990
- Time: 14:35
- Latitude: 40.7128
- Longitude: -74.0060
- Timezone offset: -5
- House system: Placidus

## Notes

- The script converts local birth time to UTC before calculating the Julian Day.
- Planet output includes longitude, latitude, longitudinal speed, and retrograde status.
- House output includes all 12 cusps plus ASC and MC.
- The script prints the installed Swiss Ephemeris wrapper version and the ephemeris source actually used.
- The prototype now reads ephemeris data from `./ephe` via `swe.set_ephe_path('./ephe')`.
- If the `.se1` files are missing from `./ephe`, `pyswisseph` can fall back to Moshier, which is less suitable for accuracy validation against Astro.com or AstroGold.


## Chart Persistence

Create and persist a natal chart JSON via the API:

```bash
curl -X POST http://127.0.0.1:8000/create-natal-chart \
  -H "Content-Type: application/json" \
  -d '{"name":"Serge","birth_date":"1991-07-29","birth_time":"01:06:00","timezone":"Europe/Minsk","location_name":"Brest, Belarus","latitude":52.13472,"longitude":23.65694,"time_basis":"local"}'
```

Saved charts are written to `charts/chart_YYYY_MM_DD_HHMM.json`, where the chart ID token is
still based on the UTC birth moment used by the calculator.

Natal chart responses now include both:

- raw `planets` longitude data for low-level use
- normalized `natal_positions` entries for UI and product surfaces

Prefer `natal_positions` when rendering signs, degrees, houses, and retrograde state in the UI.

Run aspect tests with:

```bash
python -m unittest discover -s tests
```

## Database and migrations

The project now includes SQLAlchemy models plus Alembic migrations for the production persistence path.

Default local behavior remains file-backed. To enable database persistence, set:

```bash
export ASTRO_CONSUL_PERSISTENCE_BACKEND=database
export ASTRO_CONSUL_DATABASE_URL=postgresql://...
```

Run migrations with:

```bash
python -m alembic upgrade head
```

Import the current JSON fixtures into the database with:

```bash
python scripts/import_legacy_json_to_db.py \
  --database-url postgresql://... \
  --charts-dir charts \
  --profiles-dir profiles
```

For a clean local reset during migration tests:

```bash
python scripts/import_legacy_json_to_db.py \
  --database-url sqlite:///./astro_consul.db \
  --charts-dir charts \
  --profiles-dir profiles \
  --reset
```


## Transit Report

Request a UI-ready transit report from a saved natal chart:

```bash
curl -X POST http://127.0.0.1:8000/transit-report \
  -H "Content-Type: application/json" \
  -d '{"chart_id":"chart_1991_07_28_2206","transit_date":"2026-03-09","transit_time":"06:06:01","timezone":"Europe/Warsaw"}'
```

The response includes formatted transit positions, natal house placement, and transit-to-natal aspects sorted by orb.


## Browser UI Flow

From the browser UI:

1. Use `Create Natal Chart` to submit local birth data.
2. Enter a location name and let the UI resolve timezone plus coordinates automatically before chart creation.
3. Open advanced location details only when you need to override timezone or coordinates manually.
4. Review the main natal summary with local birth datetime, Sun, Moon, Asc, MC, and natal aspect count.
5. Open `Technical details` only when you need UTC timestamps, `chart_id`, Julian day, or saved chart metadata.
6. Reuse the returned `chart_id` in `Transit Report`.
7. Generate a transit report and review the structured output, with active aspects emphasized above transit positions.
8. Use `Engineering Debug` only when you want the raw `/natal` calculator with decimal UT input.
