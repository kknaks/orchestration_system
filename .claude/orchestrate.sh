#!/bin/bash
set -euo pipefail

export ORCHESTRATION_RUNTIME="${ORCHESTRATION_RUNTIME:-claude}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATION_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
exec "$ORCHESTRATION_ROOT/.agent/orchestrate.sh"
