#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/user}"
source "$WORKSPACE_ROOT/scripts/runtime-common.sh"
load_env

PGPASSWORD="$POSTGRES_PASSWORD" pg_isready \
  -h "$POSTGRES_HOST" \
  -p "$POSTGRES_PORT" \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" >/dev/null

curl -fsS --max-time 2 \
  "http://127.0.0.1:${BACKEND_PORT}/api/health" >/dev/null

curl -fsS --max-time 2 \
  "http://127.0.0.1:${FRONTEND_PORT}" >/dev/null

echo workspace_ready
