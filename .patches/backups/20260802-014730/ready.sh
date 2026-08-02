#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/user}"
source "$WORKSPACE_ROOT/scripts/runtime-common.sh"
load_env

POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-tenderheart_workspace}"
POSTGRES_USER="${POSTGRES_USER:-tenderheart}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-tenderheart_local}"
FRONTEND_PORT="${FRONTEND_PORT:-8080}"
BACKEND_PORT="${BACKEND_PORT:-4000}"

fail() {
  echo "[ready] $*" >&2
  exit 1
}

PGPASSWORD="$POSTGRES_PASSWORD" pg_isready \
  -h "$POSTGRES_HOST" \
  -p "$POSTGRES_PORT" \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" >/dev/null 2>&1 ||
  fail "PostgreSQL is not ready at ${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"

curl -fsS --connect-timeout 1 --max-time 3 \
  "http://127.0.0.1:${BACKEND_PORT}/api/health" >/dev/null ||
  fail "Backend is not ready at 127.0.0.1:${BACKEND_PORT}/api/health"

curl -fsS --connect-timeout 1 --max-time 3 \
  "http://127.0.0.1:${FRONTEND_PORT}/" >/dev/null ||
  fail "Frontend is not ready at 127.0.0.1:${FRONTEND_PORT}"

echo workspace_ready
