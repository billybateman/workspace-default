#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/user}"
RUNTIME_DIR="$WORKSPACE_ROOT/.tenderheart-runtime"
PID_DIR="$RUNTIME_DIR/pids"
LOG_DIR="$RUNTIME_DIR/logs"

mkdir -p "$PID_DIR" "$LOG_DIR"

load_env() {
  if [ ! -f "$WORKSPACE_ROOT/.env" ] && [ -f "$WORKSPACE_ROOT/.env.example" ]; then
    cp "$WORKSPACE_ROOT/.env.example" "$WORKSPACE_ROOT/.env"
  fi

  set -a
  source "$WORKSPACE_ROOT/.env"
  set +a
}

port_listening() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

stop_pid_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  local pid
  pid="$(cat "$file" 2>/dev/null || true)"
  [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
  rm -f "$file"
}

start_process() {
  local name="$1"
  local port="$2"
  local command="$3"

  if port_listening "$port"; then
    echo "$name already listening on $port"
    return 0
  fi

  stop_pid_file "$PID_DIR/$name.pid"
  nohup bash -lc "$command" >>"$LOG_DIR/$name.log" 2>&1 &
  echo $! >"$PID_DIR/$name.pid"
}

wait_http() {
  local url="$1"
  for _ in $(seq 1 120); do
    curl -fsS "$url" >/dev/null 2>&1 && return 0
    sleep .25
  done
  return 1
}

install_if_needed() {
  local directory="$1"
  [ -f "$directory/package.json" ] || return 0

  local fingerprint
  fingerprint="$(
    cat "$directory/package.json" "$directory/package-lock.json" 2>/dev/null |
      shasum -a 256 |
      awk '{print $1}'
  )"

  local marker="$directory/node_modules/.tenderheart-$fingerprint"
  [ -f "$marker" ] && return 0

  if [ -f "$directory/package-lock.json" ]; then
    (cd "$directory" && npm ci --prefer-offline --no-audit --no-fund)
  else
    (cd "$directory" && npm install --prefer-offline --no-audit --no-fund)
  fi

  mkdir -p "$directory/node_modules"
  rm -f "$directory/node_modules/.tenderheart-"* 2>/dev/null || true
  touch "$marker"
}
