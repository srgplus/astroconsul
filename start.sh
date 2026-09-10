#!/bin/bash
set -e

# Run Alembic migrations if DATABASE_URL is configured (PostgreSQL mode).
#
# A failure here stops the deploy on purpose. This line used to end in
# `|| echo "WARNING: ..."`, and on 2026-09-09 that swallowed a chain which had
# been blocked for months: the version pointer sat at 20260406_000001 while the
# schema was really at 20260406_000002, so every deploy re-ran "create table
# subscriptions", failed on a table that already existed, and applied nothing
# after it. The app then booted with a model declaring two columns the database
# did not have, and every read of a user row answered 500 — which reached
# readers as "Не удалось загрузить профили".
#
# `set -e` above turns a non-zero exit into an aborted start, Railway retries
# per its restart policy and then marks the deploy failed, and the previous
# deployment keeps serving. A release that cannot migrate must not serve.
if [ -n "$ASTRO_CONSUL_DATABASE_URL" ]; then
  echo "Running Alembic migrations..."
  alembic upgrade head
fi

# Start the application
exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}
