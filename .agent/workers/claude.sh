#!/bin/bash
set -euo pipefail

WORK_DIR="${1:?WORK_DIR is required}"
CLAUDE_MODEL="${ORCHESTRATION_CLAUDE_MODEL:-sonnet}"

cd "$WORK_DIR"
exec claude --model "$CLAUDE_MODEL"
