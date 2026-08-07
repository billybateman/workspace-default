#!/usr/bin/env bash
set -Eeuo pipefail
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/user}"
source "$WORKSPACE_ROOT/scripts/runtime-common.sh"
stop_pid_file "$PID_DIR/frontend.pid"
stop_pid_file "$PID_DIR/backend.pid"
