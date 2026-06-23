#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATION_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="/private/tmp/orchestration_system_codex_hooks.log"

INPUT="$(cat)"
printf '%s\n' "$INPUT" >> "$LOG_FILE" 2>/dev/null || true

EVENT_JSON="$(HOOK_INPUT="$INPUT" ORCHESTRATION_ROOT="$ORCHESTRATION_ROOT" python3 - <<'PY'
import json
import os
import sys

raw = os.environ.get("HOOK_INPUT", "")
try:
    data = json.loads(raw)
except Exception:
    raise SystemExit(0)

event = data.get("hook_event_name") or data.get("event") or data.get("hook")
if event and str(event).lower() not in {"posttooluse", "post_tool_use"}:
    raise SystemExit(0)

tool_name = data.get("tool_name") or data.get("tool", {}).get("name") or ""
tool_input = data.get("tool_input") or data.get("input") or data.get("tool", {}).get("input") or {}
file_path = tool_input.get("file_path") or tool_input.get("path") or data.get("file_path") or data.get("path") or ""

if tool_name not in {"Write", "Edit", "MultiEdit", "apply_patch"}:
    raise SystemExit(0)

def candidate_paths(value):
    if isinstance(value, str):
        # Direct absolute/relative paths in JSON payloads.
        for token in value.replace("\n", " ").split():
            token = token.strip("\"',")
            if ("/tasks/" in token or "/reports/" in token) and token.endswith(".md"):
                yield token
        # Codex apply_patch payloads.
        for line in value.splitlines():
            line = line.strip()
            for prefix in ("*** Add File: ", "*** Update File: ", "*** Delete File: "):
                if line.startswith(prefix):
                    yield line[len(prefix):].strip()
    elif isinstance(value, dict):
        for nested in value.values():
            yield from candidate_paths(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from candidate_paths(nested)

if not file_path:
    for candidate in candidate_paths(tool_input):
        if "/tasks/" in candidate or "/reports/" in candidate:
            file_path = candidate
            break

if not file_path or ("/tasks/" not in file_path and "/reports/" not in file_path):
    raise SystemExit(0)

if not file_path.startswith("/"):
    file_path = f"{os.environ['ORCHESTRATION_ROOT']}/{file_path}"

print(json.dumps({
    "tool_name": "Write",
    "tool_input": {
        "file_path": file_path,
    },
}, ensure_ascii=False))
PY
)"

[ -n "$EVENT_JSON" ] || exit 0
printf '%s\n' "$EVENT_JSON" | ORCHESTRATION_CODEX_WATCH=0 "$ORCHESTRATION_ROOT/.codex/orchestrate.sh"
