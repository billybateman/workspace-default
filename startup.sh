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
FRONTEND_PORT="${FRONTEND_PORT:-5173}"
BACKEND_PORT="${BACKEND_PORT:-4000}"

echo "[startup] ensuring PostgreSQL is running"

if ! pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" >/dev/null 2>&1; then
  if command -v pg_ctlcluster >/dev/null 2>&1 && [ -d /etc/postgresql ]; then
    PG_VERSION="$(
      find /etc/postgresql -mindepth 1 -maxdepth 1 -type d \
        -printf '%f\n' 2>/dev/null | sort -V | tail -n 1
    )"
    [ -z "$PG_VERSION" ] ||
      sudo -n pg_ctlcluster "$PG_VERSION" main start >/dev/null 2>&1 ||
      true
  fi

  if ! pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" >/dev/null 2>&1; then
    PG_BINDIR="$(pg_config --bindir)"
    POSTGRES_DATA_DIR="${POSTGRES_DATA_DIR:-/var/lib/postgresql/tenderheart}"
    if [ -s "$POSTGRES_DATA_DIR/PG_VERSION" ]; then
      sudo -n -u postgres "$PG_BINDIR/pg_ctl" \
        --pgdata="$POSTGRES_DATA_DIR" \
        --log="${POSTGRES_LOG_FILE:-/var/log/postgresql/tenderheart.log}" \
        --options="-h $POSTGRES_HOST -p $POSTGRES_PORT -k /tmp" \
        --wait \
        --timeout=60 \
        start >/dev/null
    fi
  fi
fi

for _ in $(seq 1 120); do
  PGPASSWORD="$POSTGRES_PASSWORD" pg_isready \
    -h "$POSTGRES_HOST" \
    -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" >/dev/null 2>&1 && break
  sleep .25
done

PGPASSWORD="$POSTGRES_PASSWORD" pg_isready \
  -h "$POSTGRES_HOST" \
  -p "$POSTGRES_PORT" \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" >/dev/null

echo "[startup] starting backend on $BACKEND_PORT"
start_process backend "$BACKEND_PORT" \
  "cd '$WORKSPACE_ROOT/backend' && BACKEND_PORT='$BACKEND_PORT' PORT='$BACKEND_PORT' npm start"

echo "[startup] starting frontend on $FRONTEND_PORT"
start_process frontend "$FRONTEND_PORT" \
  "cd '$WORKSPACE_ROOT/frontend' && FRONTEND_PORT='$FRONTEND_PORT' npm run dev -- --host 0.0.0.0 --port '$FRONTEND_PORT' --strictPort"

echo workspace_started
