# ---- Stage 1: Build frontend ----
FROM node:20-slim AS frontend-build
WORKDIR /app/frontend

# Supabase env vars needed at build time (Vite bakes them in)
ARG VITE_SUPABASE_URL
ARG VITE_SUPABASE_ANON_KEY
ENV VITE_SUPABASE_URL=$VITE_SUPABASE_URL
ENV VITE_SUPABASE_ANON_KEY=$VITE_SUPABASE_ANON_KEY

COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# ---- Stage 2: Python runtime ----
FROM python:3.11-slim-bookworm AS runtime
WORKDIR /app

# System deps for pyswisseph (needs C compiler for build)
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc build-essential && \
    rm -rf /var/lib/apt/lists/*

# Python dependencies
COPY pyproject.toml requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Clean up build deps
RUN apt-get purge -y gcc build-essential && apt-get autoremove -y

# Copy app code
COPY app/ ./app/
COPY *.py ./
COPY ephe/ ./ephe/

# Copy Alembic migration files
COPY alembic.ini ./
COPY alembic/ ./alembic/
COPY start.sh ./
RUN chmod +x start.sh

# Copy built frontend
COPY --from=frontend-build /app/frontend/dist ./frontend/dist

# Data files (writable volume in production)
COPY profiles/ ./profiles/
RUN mkdir -p ./charts

# Runtime config
ENV ASTRO_CONSUL_ENV=production
ENV ASTRO_CONSUL_PERSISTENCE_BACKEND=file
ENV PORT=8000

EXPOSE 8000

CMD ["./start.sh"]
