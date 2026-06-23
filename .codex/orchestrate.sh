#!/bin/bash
set -euo pipefail

export ORCHESTRATION_RUNTIME="${ORCHESTRATION_RUNTIME:-codex}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATION_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ "${ORCHESTRATE_DRY_RUN:-}" != "1" ] && [ "${ORCHESTRATION_CODEX_WATCH:-0}" = "1" ]; then
    bash "$ORCHESTRATION_ROOT/.codex/ensure-watch.sh"
fi
exec "$ORCHESTRATION_ROOT/.agent/orchestrate.sh"
