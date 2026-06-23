#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATION_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_DIR="${CODEX_WATCH_RUN_DIR:-/private/tmp/orchestration_system_codex}"
PID_FILE="$RUN_DIR/watch.pid"
LOG_FILE="$RUN_DIR/watch.log"
STATE_FILE="${CODEX_WATCH_STATE:-$RUN_DIR/watch.state}"

if [ "${ORCHESTRATION_CODEX_WATCH:-1}" = "0" ]; then
    exit 0
fi

mkdir -p "$RUN_DIR"

if [ -f "$PID_FILE" ]; then
    PID="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
        exit 0
    fi
    rm -f "$PID_FILE"
fi

nohup env \
    CODEX_WATCH_STATE="$STATE_FILE" \
    CODEX_WATCH_INTERVAL="${CODEX_WATCH_INTERVAL:-2}" \
    "$ORCHESTRATION_ROOT/.codex/watch.sh" >> "$LOG_FILE" 2>&1 &

echo "$!" > "$PID_FILE"
