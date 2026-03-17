#!/bin/bash
set -e

# Run Alembic migrations if DATABASE_URL is configured (PostgreSQL mode)
if [ -n "$ASTRO_CONSUL_DATABASE_URL" ]; then
  echo "Running Alembic migrations..."
  alembic upgrade head || echo "WARNING: Alembic migrations failed (may need manual fix)"
fi

# Start the application
exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}
