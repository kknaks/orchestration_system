#!/bin/bash
set -euo pipefail

WORK_DIR="${1:?WORK_DIR is required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATION_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CODEX_MODEL="${ORCHESTRATION_CODEX_MODEL:-gpt-5.5}"

if [ "${ORCHESTRATION_SKIP_CODEX_HOOK_CHECK:-0}" != "1" ]; then
  bash "$ORCHESTRATION_ROOT/.codex/bootstrap-hooks.sh" --check
fi

exec codex \
  --cd "$ORCHESTRATION_ROOT" \
  --add-dir "$WORK_DIR" \
  --model "$CODEX_MODEL" \
  --sandbox workspace-write \
  --ask-for-approval on-request \
  --dangerously-bypass-hook-trust
