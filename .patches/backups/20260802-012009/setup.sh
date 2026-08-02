#!/usr/bin/env bash
set -Eeuo pipefail

# TenderHeart E2B sandbox setup
#
# What this script does:
#   1. Verifies required base tools.
#   2. Installs PostgreSQL if it is missing.
#   3. Starts PostgreSQL without requiring interactive input.
#   4. Creates or updates the application PostgreSQL role.
#   5. Creates the application database when missing.
#   6. Clones or refreshes the workspace repository in /home/user.
#   7. Writes the local PostgreSQL DATABASE_URL and related variables to .env.
#   8. Runs the cloned repository's startup.sh.
#
# Intended execution:
#   bash /tmp/setup.sh
#
# Optional environment overrides:
#   WORKSPACE_ROOT=/home/user
#   REPOSITORY_URL=https://github.com/billybateman/workspace-default.git
#   REPOSITORY_BRANCH=main
#   POSTGRES_HOST=127.0.0.1
#   POSTGRES_PORT=5432
#   POSTGRES_DB=tenderheart_workspace
#   POSTGRES_USER=tenderheart
#   POSTGRES_PASSWORD=<password>
#   DATABASE_URL=postgresql://...
#   FORCE_RECLONE=0
#   RUN_STARTUP=1

WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/user}"
REPOSITORY_URL="${REPOSITORY_URL:-https://github.com/billybateman/workspace-default.git}"
REPOSITORY_BRANCH="${REPOSITORY_BRANCH:-main}"

POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-tenderheart_workspace}"
POSTGRES_USER="${POSTGRES_USER:-tenderheart}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-tenderheart_local}"

FORCE_RECLONE="${FORCE_RECLONE:-0}"
RUN_STARTUP="${RUN_STARTUP:-1}"

DATABASE_URL="${DATABASE_URL:-postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}}"

log()  { printf '\033[0;34m[setup]\033[0m %s\n' "$*"; }
ok()   { printf '\033[0;32m[ok]\033[0m    %s\n' "$*"; }
warn() { printf '\033[0;33m[warn]\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

sudo_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo -n "$@"
  fi
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
     command -v pg_isready >/dev/null 2>&1; then
    ok "PostgreSQL client tools already installed"
    return
  fi

  log "PostgreSQL is not installed; installing it"

  require_command apt-get

  sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get update
  sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    postgresql \
    postgresql-client \
    postgresql-contrib

  command -v psql >/dev/null 2>&1 ||
    die "PostgreSQL installation completed but psql is unavailable"

  ok "PostgreSQL installed"
}

discover_postgres_paths() {
  PG_BINDIR="$(pg_config --bindir 2>/dev/null || true)"

  if [ -z "$PG_BINDIR" ]; then
    PG_BINDIR="$(dirname "$(command -v psql)")"
  fi

  PSQL="$PG_BINDIR/psql"
  CREATEDB="$PG_BINDIR/createdb"
  PG_ISREADY="$PG_BINDIR/pg_isready"
  PG_CTL="$PG_BINDIR/pg_ctl"
  INITDB="$PG_BINDIR/initdb"

  [ -x "$PSQL" ] || die "psql not found in $PG_BINDIR"
  [ -x "$CREATEDB" ] || die "createdb not found in $PG_BINDIR"
  [ -x "$PG_ISREADY" ] || die "pg_isready not found in $PG_BINDIR"
}

start_system_cluster() {
  if command -v pg_ctlcluster >/dev/null 2>&1 &&
     [ -d /etc/postgresql ]; then
    local version
    version="$(find /etc/postgresql -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -n 1)"

    if [ -n "$version" ]; then
      log "Starting PostgreSQL cluster ${version}/main"
      sudo_cmd pg_ctlcluster "$version" main start >/dev/null 2>&1 || true

      for _ in $(seq 1 60); do
        if "$PG_ISREADY" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" >/dev/null 2>&1; then
          ok "System PostgreSQL cluster is ready"
          return 0
        fi
        sleep 0.5
      done
    fi
  fi

  if command -v service >/dev/null 2>&1; then
    log "Trying PostgreSQL service startup"
    sudo_cmd service postgresql start >/dev/null 2>&1 || true

    for _ in $(seq 1 30); do
      if "$PG_ISREADY" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" >/dev/null 2>&1; then
        ok "PostgreSQL service is ready"
        return 0
      fi
      sleep 0.5
    done
  fi

  return 1
}

start_dedicated_cluster() {
  local data_dir="${POSTGRES_DATA_DIR:-/var/lib/postgresql/tenderheart}"
  local log_file="${POSTGRES_LOG_FILE:-/var/log/postgresql/tenderheart.log}"

  [ -x "$PG_CTL" ] || die "pg_ctl is unavailable"
  [ -x "$INITDB" ] || die "initdb is unavailable"

  log "Using dedicated PostgreSQL cluster at $data_dir"

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
      --wait \
      --timeout=60 \
      start || {
        sudo_cmd tail -n 200 "$log_file" >&2 || true
        die "Dedicated PostgreSQL cluster failed to start"
      }
  fi

  for _ in $(seq 1 120); do
    if "$PG_ISREADY" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" >/dev/null 2>&1; then
      ok "Dedicated PostgreSQL cluster is ready"
      return 0
    fi
    sleep 0.25
  done

  sudo_cmd tail -n 200 "$log_file" >&2 || true
  die "PostgreSQL did not become ready"
}

ensure_postgresql_running() {
  if "$PG_ISREADY" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" >/dev/null 2>&1; then
    ok "PostgreSQL already responding at ${POSTGRES_HOST}:${POSTGRES_PORT}"
    return
  fi

  if start_system_cluster; then
    return
  fi

  warn "System PostgreSQL cluster did not start; falling back to a dedicated cluster"
  start_dedicated_cluster
}

ensure_database_role() {
  log "Ensuring PostgreSQL role '$POSTGRES_USER' exists"

  postgres_cmd "$PSQL" \
    --host=/tmp \
    --port="$POSTGRES_PORT" \
    --username=postgres \
    --dbname=postgres \
    --set=ON_ERROR_STOP=1 \
    --set=app_user="$POSTGRES_USER" \
    --set=app_password="$POSTGRES_PASSWORD" <<'SQL'
SELECT format(
  'CREATE ROLE %I LOGIN PASSWORD %L',
  :'app_user',
  :'app_password'
)
WHERE NOT EXISTS (
  SELECT 1 FROM pg_roles WHERE rolname = :'app_user'
)\gexec

SELECT format(
  'ALTER ROLE %I WITH LOGIN PASSWORD %L',
  :'app_user',
  :'app_password'
)\gexec
SQL

  ok "PostgreSQL role is ready"
}

ensure_database() {
  log "Ensuring PostgreSQL database '$POSTGRES_DB' exists"

  local exists
  exists="$(
    postgres_cmd "$PSQL" \
      --host=/tmp \
      --port="$POSTGRES_PORT" \
      --username=postgres \
      --dbname=postgres \
      --tuples-only \
      --no-align \
      --command="SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_DB'" \
    | tr -d '[:space:]'
  )"

  if [ "$exists" != "1" ]; then
    postgres_cmd "$CREATEDB" \
      --host=/tmp \
      --port="$POSTGRES_PORT" \
      --username=postgres \
      --owner="$POSTGRES_USER" \
      "$POSTGRES_DB"
  fi

  postgres_cmd "$PSQL" \
    --host=/tmp \
    --port="$POSTGRES_PORT" \
    --username=postgres \
    --dbname=postgres \
    --set=ON_ERROR_STOP=1 \
    --command="ALTER DATABASE \"$POSTGRES_DB\" OWNER TO \"$POSTGRES_USER\";" \
    >/dev/null

  PGPASSWORD="$POSTGRES_PASSWORD" "$PSQL" \
    --host="$POSTGRES_HOST" \
    --port="$POSTGRES_PORT" \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --no-password \
    --set=ON_ERROR_STOP=1 \
    --command='SELECT 1;' \
    >/dev/null

  ok "Application database connection verified"
}

preserve_env() {
  PRESERVED_ENV=""
  if [ -f "$WORKSPACE_ROOT/.env" ]; then
    PRESERVED_ENV="$(mktemp)"
    cp "$WORKSPACE_ROOT/.env" "$PRESERVED_ENV"
  fi
}

clone_or_refresh_repository() {
  log "Preparing repository at $WORKSPACE_ROOT"

  preserve_env

  if [ "$FORCE_RECLONE" = "1" ]; then
    log "FORCE_RECLONE=1; removing the existing workspace contents"
    find "$WORKSPACE_ROOT" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi

  if [ -d "$WORKSPACE_ROOT/.git" ]; then
    local current_remote
    current_remote="$(git -C "$WORKSPACE_ROOT" remote get-url origin 2>/dev/null || true)"

    if [ "$current_remote" = "$REPOSITORY_URL" ]; then
      log "Refreshing existing repository"

      git -C "$WORKSPACE_ROOT" fetch --depth=1 origin "$REPOSITORY_BRANCH"
      git -C "$WORKSPACE_ROOT" reset --hard "origin/$REPOSITORY_BRANCH"
      git -C "$WORKSPACE_ROOT" clean -fd \
        -e .env \
        -e .tenderheart \
        -e .tenderheart-runtime

      restore_env
      ok "Repository refreshed"
      return
    fi

    warn "Existing Git repository does not match $REPOSITORY_URL; replacing it"
  elif [ -n "$(find "$WORKSPACE_ROOT" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
    warn "Workspace root contains non-repository files; replacing them"
  fi

  find "$WORKSPACE_ROOT" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

  git clone \
    --depth=1 \
    --branch="$REPOSITORY_BRANCH" \
    "$REPOSITORY_URL" \
    "$WORKSPACE_ROOT"

  restore_env
  ok "Repository cloned"
}

restore_env() {
  if [ -n "${PRESERVED_ENV:-}" ] && [ -f "$PRESERVED_ENV" ]; then
    cp "$PRESERVED_ENV" "$WORKSPACE_ROOT/.env"
    rm -f "$PRESERVED_ENV"
    PRESERVED_ENV=""
  fi
}

set_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local temporary

  temporary="$(mktemp)"

  if [ -f "$file" ]; then
    awk -v key="$key" '
      BEGIN { pattern = "^[[:space:]]*" key "=" }
      $0 !~ pattern { print }
    ' "$file" > "$temporary"
  fi

  printf '%s=%s\n' "$key" "$value" >> "$temporary"
  mv "$temporary" "$file"
}

write_environment() {
  local env_file="$WORKSPACE_ROOT/.env"

  log "Writing PostgreSQL connection settings to $env_file"

  touch "$env_file"

  set_env_value "$env_file" POSTGRES_HOST "$POSTGRES_HOST"
  set_env_value "$env_file" POSTGRES_PORT "$POSTGRES_PORT"
  set_env_value "$env_file" POSTGRES_DB "$POSTGRES_DB"
  set_env_value "$env_file" POSTGRES_USER "$POSTGRES_USER"
  set_env_value "$env_file" POSTGRES_PASSWORD "$POSTGRES_PASSWORD"
  set_env_value "$env_file" DATABASE_URL "$DATABASE_URL"

  chmod 0600 "$env_file" || true
  chown "$(id -u):$(id -g)" "$env_file" 2>/dev/null || true

  ok "Database environment written"
}

run_repository_startup() {
  if [ "$RUN_STARTUP" != "1" ]; then
    warn "RUN_STARTUP=$RUN_STARTUP; skipping startup.sh"
    return
  fi

  [ -f "$WORKSPACE_ROOT/startup.sh" ] ||
    die "Repository does not contain $WORKSPACE_ROOT/startup.sh"

  chmod +x \
    "$WORKSPACE_ROOT/startup.sh" \
    "$WORKSPACE_ROOT/shutdown.sh" \
    "$WORKSPACE_ROOT/migrate.sh" \
    "$WORKSPACE_ROOT/seed.sh" \
    "$WORKSPACE_ROOT/ready.sh" \
    2>/dev/null || true

  log "Running repository startup.sh"
  (
    cd "$WORKSPACE_ROOT"
    bash ./startup.sh
  )

  ok "Repository startup completed"
}

print_summary() {
  local commit
  commit="$(git -C "$WORKSPACE_ROOT" rev-parse HEAD 2>/dev/null || true)"

  printf '\n'
  ok "TenderHeart sandbox setup complete"
  printf '  Workspace root: %s\n' "$WORKSPACE_ROOT"
  printf '  Repository:     %s\n' "$REPOSITORY_URL"
  printf '  Branch:         %s\n' "$REPOSITORY_BRANCH"
  printf '  Commit:         %s\n' "${commit:-unknown}"
  printf '  PostgreSQL:     %s:%s\n' "$POSTGRES_HOST" "$POSTGRES_PORT"
  printf '  Database:       %s\n' "$POSTGRES_DB"
  printf '  Database user:  %s\n' "$POSTGRES_USER"
  printf '  Environment:    %s/.env\n' "$WORKSPACE_ROOT"
}

main() {
  require_command bash
  require_command git
  require_command sudo

  install_postgresql
  discover_postgres_paths
  ensure_postgresql_running
  ensure_database_role
  ensure_database
  clone_or_refresh_repository
  write_environment
  run_repository_startup
  print_summary
}

main "$@"
