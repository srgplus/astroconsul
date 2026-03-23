"""Example celebrity definition.

Usage:
  python scripts/add_celebrity.py scripts/celebrities/example.py

Birth data must be from Astro-Databank with Rodden Rating AA or A.
"""

CELEBRITY = {
    # Basic info
    "name": "Zendaya",
    "birth_date": "1996-09-01",       # YYYY-MM-DD
    "birth_time": "18:55",            # HH:MM local time
    "timezone": "America/Los_Angeles",
    "location_name": "Oakland, CA",
    "latitude": 37.8044,
    "longitude": -122.2712,

    # Data verification (REQUIRED)
    "rodden_rating": "AA",            # Only AA or A accepted
    "astro_databank_url": "https://www.astro.com/astro-databank/Zendaya",
}
