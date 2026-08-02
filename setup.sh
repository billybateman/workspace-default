#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/user}"

POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-tenderheart_workspace}"
POSTGRES_USER="${POSTGRES_USER:-tenderheart}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-tenderheart_local}"
DATABASE_URL="${DATABASE_URL:-postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}}"

log()  { printf '\033[0;34m[setup]\033[0m %s\n' "$*"; }
ok()   { printf '\033[0;32m[ok]\033[0m    %s\n' "$*"; }
warn() { printf '\033[0;33m[warn]\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

sudo_cmd() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo -n "$@"; fi
}

postgres_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    runuser -u postgres -- "$@"
  else
    sudo -n -u postgres "$@"
  fi
}

install_postgresql() {
  if command -v psql >/dev/null 2>&1 &&
     command -v pg_isready >/dev/null 2>&1 &&
     command -v pg_config >/dev/null 2>&1; then
    ok "PostgreSQL tooling already installed"
    return
  fi

  command -v apt-get >/dev/null 2>&1 ||
    die "PostgreSQL is missing and apt-get is unavailable"

  log "Installing PostgreSQL"
  sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get update
  sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    postgresql postgresql-client postgresql-contrib
  ok "PostgreSQL installed"
}

discover_postgres() {
  PG_BINDIR="$(pg_config --bindir)"
  PSQL="$PG_BINDIR/psql"
  CREATEDB="$PG_BINDIR/createdb"
  PG_ISREADY="$PG_BINDIR/pg_isready"
  PG_CTL="$PG_BINDIR/pg_ctl"
  INITDB="$PG_BINDIR/initdb"

  for executable in "$PSQL" "$CREATEDB" "$PG_ISREADY" "$PG_CTL" "$INITDB"; do
    [ -x "$executable" ] || die "Missing PostgreSQL executable: $executable"
  done
}

start_system_postgres() {
  if command -v pg_ctlcluster >/dev/null 2>&1 && [ -d /etc/postgresql ]; then
    local version
    version="$(find /etc/postgresql -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -n 1)"
    if [ -n "$version" ]; then
      sudo_cmd pg_ctlcluster "$version" main start >/dev/null 2>&1 || true
      for _ in $(seq 1 40); do
        "$PG_ISREADY" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" >/dev/null 2>&1 && return 0
        sleep .25
      done
    fi
  fi
  return 1
}

start_dedicated_postgres() {
  local data_dir="${POSTGRES_DATA_DIR:-/var/lib/postgresql/tenderheart}"
  local log_file="${POSTGRES_LOG_FILE:-/var/log/postgresql/tenderheart.log}"

  sudo_cmd install -d -o postgres -g postgres -m 0700 "$data_dir"
  sudo_cmd install -d -o postgres -g postgres -m 0755 "$(dirname "$log_file")"
  sudo_cmd touch "$log_file"
  sudo_cmd chown postgres:postgres "$log_file"

  if [ ! -s "$data_dir/PG_VERSION" ]; then
    log "Initializing dedicated PostgreSQL cluster"
    postgres_cmd "$INITDB" \
      --pgdata="$data_dir" \
      --username=postgres \
      --auth-local=trust \
      --auth-host=scram-sha-256 \
      --encoding=UTF8 \
      --locale=C.UTF-8

    postgres_cmd bash -c "cat >> '$data_dir/postgresql.conf'" <<EOF
listen_addresses = '$POSTGRES_HOST'
port = $POSTGRES_PORT
unix_socket_directories = '/tmp'
password_encryption = 'scram-sha-256'
EOF
    postgres_cmd bash -c "cat >> '$data_dir/pg_hba.conf'" <<EOF
host all all 127.0.0.1/32 scram-sha-256
host all all ::1/128 scram-sha-256
EOF
  fi

  if ! postgres_cmd "$PG_CTL" --pgdata="$data_dir" status >/dev/null 2>&1; then
    postgres_cmd "$PG_CTL" \
      --pgdata="$data_dir" \
      --log="$log_file" \
      --options="-h $POSTGRES_HOST -p $POSTGRES_PORT -k /tmp" \
      --wait --timeout=60 start || {
        sudo_cmd tail -n 200 "$log_file" >&2 || true
        die "Dedicated PostgreSQL cluster failed to start"
      }
  fi
}

ensure_postgres_running() {
  "$PG_ISREADY" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" >/dev/null 2>&1 && return
  start_system_postgres || start_dedicated_postgres

  for _ in $(seq 1 120); do
    "$PG_ISREADY" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" >/dev/null 2>&1 && {
      ok "PostgreSQL is ready"
      return
    }
    sleep .25
  done
  die "PostgreSQL did not become ready"
}

ensure_role_and_database() {
  log "Ensuring PostgreSQL role '$POSTGRES_USER'"
  postgres_cmd "$PSQL" \
    --host=/tmp --port="$POSTGRES_PORT" --username=postgres --dbname=postgres \
    --set=ON_ERROR_STOP=1 \
    --set=app_user="$POSTGRES_USER" \
    --set=app_password="$POSTGRES_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'app_user', :'app_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')\gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'app_user', :'app_password')\gexec
SQL

  local exists
  exists="$(
    postgres_cmd "$PSQL" \
      --host=/tmp --port="$POSTGRES_PORT" --username=postgres --dbname=postgres \
      --tuples-only --no-align \
      --command="SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_DB'" |
      tr -d '[:space:]'
  )"

  if [ "$exists" != "1" ]; then
    postgres_cmd "$CREATEDB" \
      --host=/tmp --port="$POSTGRES_PORT" --username=postgres \
      --owner="$POSTGRES_USER" "$POSTGRES_DB"
  fi

  postgres_cmd "$PSQL" \
    --host=/tmp --port="$POSTGRES_PORT" --username=postgres --dbname=postgres \
    --set=ON_ERROR_STOP=1 \
    --command="ALTER DATABASE \"$POSTGRES_DB\" OWNER TO \"$POSTGRES_USER\";" \
    >/dev/null

  PGPASSWORD="$POSTGRES_PASSWORD" "$PSQL" \
    --host="$POSTGRES_HOST" --port="$POSTGRES_PORT" \
    --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
    --no-password --set=ON_ERROR_STOP=1 --command='SELECT 1;' >/dev/null

  ok "Database role and database are ready"
}

set_env_value() {
  local file="$1" key="$2" value="$3" temp
  temp="$(mktemp)"
  if [ -f "$file" ]; then
    awk -v key="$key" '
      BEGIN { pattern = "^[[:space:]]*" key "=" }
      $0 !~ pattern { print }
    ' "$file" > "$temp"
  fi
  printf '%s=%s\n' "$key" "$value" >> "$temp"
  mv "$temp" "$file"
}

write_environment() {
  local env_file="$WORKSPACE_ROOT/.env"
  [ -f "$env_file" ] || {
    if [ -f "$WORKSPACE_ROOT/.env.example" ]; then
      cp "$WORKSPACE_ROOT/.env.example" "$env_file"
    else
      touch "$env_file"
    fi
  }

  set_env_value "$env_file" POSTGRES_HOST "$POSTGRES_HOST"
  set_env_value "$env_file" POSTGRES_PORT "$POSTGRES_PORT"
  set_env_value "$env_file" POSTGRES_DB "$POSTGRES_DB"
  set_env_value "$env_file" POSTGRES_USER "$POSTGRES_USER"
  set_env_value "$env_file" POSTGRES_PASSWORD "$POSTGRES_PASSWORD"
  set_env_value "$env_file" DATABASE_URL "$DATABASE_URL"
  chmod 0600 "$env_file" || true
  ok "Database environment written to $env_file"
}

install_dependencies() {
  log "Installing project dependencies when needed"
  if [ -f "$WORKSPACE_ROOT/package.json" ]; then
    (cd "$WORKSPACE_ROOT" && npm install --prefer-offline --no-audit --no-fund)
  fi
  if [ -f "$WORKSPACE_ROOT/backend/package.json" ]; then
    (cd "$WORKSPACE_ROOT/backend" && npm install --prefer-offline --no-audit --no-fund)
  fi
  if [ -f "$WORKSPACE_ROOT/frontend/package.json" ]; then
    (cd "$WORKSPACE_ROOT/frontend" && npm install --prefer-offline --no-audit --no-fund)
  fi
}

run_project_setup() {
  chmod +x "$WORKSPACE_ROOT"/*.sh 2>/dev/null || true

  [ -f "$WORKSPACE_ROOT/migrate.sh" ] && bash "$WORKSPACE_ROOT/migrate.sh"
  [ -f "$WORKSPACE_ROOT/seed.sh" ] && bash "$WORKSPACE_ROOT/seed.sh"

  [ -f "$WORKSPACE_ROOT/startup.sh" ] ||
    die "Missing $WORKSPACE_ROOT/startup.sh"

  bash "$WORKSPACE_ROOT/startup.sh"
}

main() {
  install_postgresql
  discover_postgres
  ensure_postgres_running
  ensure_role_and_database
  write_environment
  install_dependencies
  run_project_setup

  ok "Workspace setup completed"
}

main "$@"
