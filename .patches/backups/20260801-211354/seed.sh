#!/usr/bin/env bash
set -Eeuo pipefail
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/user}"
source "$WORKSPACE_ROOT/scripts/runtime-common.sh"
load_env
cd "$WORKSPACE_ROOT/backend"
npm run seed
