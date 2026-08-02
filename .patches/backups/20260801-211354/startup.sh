#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/user}"
source "$WORKSPACE_ROOT/scripts/runtime-common.sh"
load_env

sudo service postgresql start >/dev/null 2>&1 || true

pg_isready   -h "$POSTGRES_HOST"   -p "$POSTGRES_PORT"   -U "$POSTGRES_USER"   -d "$POSTGRES_DB" >/dev/null

install_if_needed "$WORKSPACE_ROOT/frontend"
install_if_needed "$WORKSPACE_ROOT/backend"

bash "$WORKSPACE_ROOT/migrate.sh"
bash "$WORKSPACE_ROOT/seed.sh"

start_process backend "$BACKEND_PORT"   "cd '$WORKSPACE_ROOT/backend' && npm start"

start_process frontend "$FRONTEND_PORT"   "cd '$WORKSPACE_ROOT/frontend' && npm run dev -- --host 0.0.0.0 --port '$FRONTEND_PORT'"

bash "$WORKSPACE_ROOT/ready.sh"
echo workspace_ready
