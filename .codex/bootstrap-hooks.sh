#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATION_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_JSON="$ORCHESTRATION_ROOT/.codex/hooks.json"
HOOK_SCRIPT="$ORCHESTRATION_ROOT/.codex/hooks/orchestrate_post_tool_use.sh"
CONFIG_FILE="${CODEX_CONFIG_FILE:-$HOME/.codex/config.toml}"
STATE_KEY="[hooks.state.\"$HOOKS_JSON:post_tool_use:0:0\"]"
DEFAULT_TRUSTED_HASH="sha256:948a2265412a0493274a927f7b578ffc69b5cab825afc1a7e5e224bcf8ecaf6a"
TRUSTED_HASH="${ORCHESTRATION_CODEX_HOOK_TRUSTED_HASH:-$DEFAULT_TRUSTED_HASH}"

usage() {
    cat <<EOF
Usage:
  .codex/bootstrap-hooks.sh --check
  .codex/bootstrap-hooks.sh --install-config [sha256:...]
  .codex/bootstrap-hooks.sh --cmux-trust

--check       Validate local files and verify Codex has trusted PostToolUse hook state.
--install-config
              Write Codex hook trust state directly into ~/.codex/config.toml.
--cmux-trust  From an active cmux Codex surface, open /hooks and press trust-all.

If --check fails, open Codex in this repo, run /hooks, then press t.
EOF
}

validate_files() {
    python3 -m json.tool "$HOOKS_JSON" >/dev/null
    bash -n "$HOOK_SCRIPT"
    bash -n "$ORCHESTRATION_ROOT/.codex/orchestrate.sh"
}

has_trust_state() {
    [ -f "$CONFIG_FILE" ] && grep -Fqx "$STATE_KEY" "$CONFIG_FILE"
}

trust_hash_matches() {
    [ -f "$CONFIG_FILE" ] || return 1
    CONFIG_FILE="$CONFIG_FILE" STATE_KEY="$STATE_KEY" TRUSTED_HASH="$TRUSTED_HASH" python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["CONFIG_FILE"])
state_key = os.environ["STATE_KEY"]
trusted_hash = os.environ["TRUSTED_HASH"]
lines = path.read_text().splitlines()
for i, line in enumerate(lines):
    if line != state_key:
        continue
    j = i + 1
    while j < len(lines) and not lines[j].startswith("["):
        if lines[j].strip() == f'trusted_hash = "{trusted_hash}"':
            raise SystemExit(0)
        j += 1
    raise SystemExit(1)
raise SystemExit(1)
PY
}

install_config() {
    validate_files

    local trusted_hash="${1:-$TRUSTED_HASH}"
    if [ -z "$trusted_hash" ]; then
        echo "ERROR: trusted hash is required. Example: --install-config sha256:..." >&2
        return 2
    fi
    case "$trusted_hash" in
        sha256:[0-9a-f][0-9a-f]*) ;;
        *)
            echo "ERROR: trusted hash must look like sha256:<hex>." >&2
            return 2
            ;;
    esac

    mkdir -p "$(dirname "$CONFIG_FILE")"
    touch "$CONFIG_FILE"

    if has_trust_state; then
        CONFIG_FILE="$CONFIG_FILE" STATE_KEY="$STATE_KEY" TRUSTED_HASH="$trusted_hash" python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["CONFIG_FILE"])
state_key = os.environ["STATE_KEY"]
trusted_hash = os.environ["TRUSTED_HASH"]
lines = path.read_text().splitlines()
out = []
i = 0
while i < len(lines):
    out.append(lines[i])
    if lines[i] == state_key:
        i += 1
        replaced = False
        while i < len(lines) and not lines[i].startswith("["):
            if lines[i].startswith("trusted_hash"):
                out.append(f'trusted_hash = "{trusted_hash}"')
                replaced = True
            else:
                out.append(lines[i])
            i += 1
        if not replaced:
            out.append(f'trusted_hash = "{trusted_hash}"')
        continue
    i += 1
path.write_text("\n".join(out).rstrip() + "\n")
PY
    else
        {
            printf '\n'
            if ! grep -Fxq "[hooks.state]" "$CONFIG_FILE"; then
                printf '[hooks.state]\n\n'
            fi
            printf '%s\n' "$STATE_KEY"
            printf 'trusted_hash = "%s"\n' "$trusted_hash"
        } >> "$CONFIG_FILE"
    fi

    check
}

check() {
    validate_files
    if has_trust_state && trust_hash_matches; then
        echo "OK: Codex PostToolUse hook trust state exists."
        return 0
    fi

    cat >&2 <<EOF
ERROR: Codex PostToolUse hook is not trusted for this user.

Required hook:
  $HOOKS_JSON

Fix:
  1. Start Codex in $ORCHESTRATION_ROOT
  Option A: run
    bash .codex/bootstrap-hooks.sh --install-config

  Option B:
    1. Start Codex in $ORCHESTRATION_ROOT
    2. Run /hooks
    3. Press t to trust all
    4. Re-run: bash .codex/bootstrap-hooks.sh --check

EOF
    return 1
}

cmux_trust() {
    validate_files

    if has_trust_state && trust_hash_matches; then
        echo "OK: Codex PostToolUse hook trust state already exists."
        return 0
    fi

    if ! command -v cmux >/dev/null 2>&1; then
        echo "ERROR: cmux command not found. Use /hooks in Codex and press t." >&2
        return 1
    fi

    local surface="${CMUX_SURFACE_ID:-}"
    if [ -z "$surface" ]; then
        surface=$(cmux identify 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("caller", {}).get("surface_ref", ""))
except Exception:
    pass
' 2>/dev/null || true)
    fi

    if [ -z "$surface" ]; then
        echo "ERROR: Cannot identify current cmux surface. Use /hooks in Codex and press t." >&2
        return 1
    fi

    cmux send --surface "$surface" "/hooks" >/dev/null
    cmux send-key --surface "$surface" enter >/dev/null
    sleep 1
    cmux send --surface "$surface" "t" >/dev/null
    sleep 1
    cmux send-key --surface "$surface" esc >/dev/null || true

    if has_trust_state; then
        echo "OK: Codex PostToolUse hook trusted."
        return 0
    fi

    echo "WARN: Trust state was not detected yet. Check /hooks manually." >&2
    return 1
}

case "${1:-}" in
    --check) check ;;
    --install-config) install_config "${2:-}" ;;
    --cmux-trust) cmux_trust ;;
    -h|--help) usage ;;
    *) usage; exit 2 ;;
esac
