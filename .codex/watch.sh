#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATION_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="${CODEX_WATCH_STATE:-/private/tmp/orchestration_system_codex_watch.state}"
INTERVAL="${CODEX_WATCH_INTERVAL:-2}"

snapshot() {
    for project_dir in "$ORCHESTRATION_ROOT"/*; do
        [ -d "$project_dir" ] || continue
        [ -f "$project_dir/config.json" ] || continue
        find "$project_dir/tasks" "$project_dir/reports" \
            \( -path "*/tasks/*/*.md" -o -path "*/reports/*.md" \) -type f -print 2>/dev/null
    done |
    while IFS= read -r file; do
        stat -f '%m %z	%N' "$file"
    done |
    sort
}

emit_hook_json() {
    local file_path="$1"
    python3 - "$file_path" <<'PY'
import json
import sys

print(json.dumps({
    "tool_name": "Write",
    "tool_input": {
        "file_path": sys.argv[1],
    },
}, ensure_ascii=False))
PY
}

mkdir -p "$(dirname "$STATE_FILE")"

if [ ! -s "$STATE_FILE" ]; then
    initial_state=$(mktemp)
    snapshot > "$initial_state"
    mv "$initial_state" "$STATE_FILE"
fi

while true; do
    next_state=$(mktemp)
    snapshot > "$next_state"

    comm -13 "$STATE_FILE" "$next_state" | while IFS=$'\t' read -r _state file_path; do
        [ -z "${file_path:-}" ] && continue
        emit_hook_json "$file_path" | "$ORCHESTRATION_ROOT/.codex/orchestrate.sh"
    done

    mv "$next_state" "$STATE_FILE"
    sleep "$INTERVAL"
done
