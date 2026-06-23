#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATION_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CODEX_CONFIG_FILE="${CODEX_CONFIG_FILE:-$HOME/.codex/config.toml}"

usage() {
    cat <<EOF
Usage:
  bash .orchestra/install-permissions.sh PROJECT_NAME SOURCE_DIR

Installs local runtime permissions for:
  - Codex project trust for this orchestration repo and the source project
  - Claude source-project settings for reading queue files and writing reports
EOF
}

PROJECT_NAME="${1:-}"
SOURCE_DIR="${2:-}"

if [ -z "$PROJECT_NAME" ] || [ -z "$SOURCE_DIR" ]; then
    usage
    exit 2
fi

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
PROJECT_DIR="$ORCHESTRATION_ROOT/$PROJECT_NAME"

install_codex_project_trust() {
    mkdir -p "$(dirname "$CODEX_CONFIG_FILE")"
    touch "$CODEX_CONFIG_FILE"

    CODEX_CONFIG_FILE="$CODEX_CONFIG_FILE" ORCHESTRATION_ROOT="$ORCHESTRATION_ROOT" SOURCE_DIR="$SOURCE_DIR" python3 - <<'PY'
import os
from pathlib import Path

config_path = Path(os.environ["CODEX_CONFIG_FILE"])
paths = [
    os.environ["ORCHESTRATION_ROOT"],
    os.environ["SOURCE_DIR"],
]
text = config_path.read_text()
lines = text.splitlines()

def upsert_project(lines, project_path):
    header = f'[projects."{project_path}"]'
    out = []
    i = 0
    found = False
    while i < len(lines):
        out.append(lines[i])
        if lines[i] == header:
            found = True
            i += 1
            replaced = False
            while i < len(lines) and not lines[i].startswith("["):
                if lines[i].startswith("trust_level"):
                    out.append('trust_level = "trusted"')
                    replaced = True
                else:
                    out.append(lines[i])
                i += 1
            if not replaced:
                out.append('trust_level = "trusted"')
            continue
        i += 1
    if not found:
        if out and out[-1] != "":
            out.append("")
        out.append(header)
        out.append('trust_level = "trusted"')
    return out

for project_path in paths:
    lines = upsert_project(lines, project_path)

config_path.write_text("\n".join(lines).rstrip() + "\n")
PY
}

install_claude_source_settings() {
    local settings_dir="$SOURCE_DIR/.claude"
    local settings_file="$settings_dir/settings.local.json"
    mkdir -p "$settings_dir"

    if [ ! -f "$settings_file" ]; then
        printf '{}\n' > "$settings_file"
    fi

    SETTINGS_FILE="$settings_file" PROJECT_DIR="$PROJECT_DIR" ORCHESTRATION_ROOT="$ORCHESTRATION_ROOT" python3 - <<'PY'
import json
import os
from pathlib import Path

settings_path = Path(os.environ["SETTINGS_FILE"])
project_dir = os.environ["PROJECT_DIR"]
orchestration_root = os.environ["ORCHESTRATION_ROOT"]

try:
    data = json.loads(settings_path.read_text())
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

permissions = data.setdefault("permissions", {})
if not isinstance(permissions, dict):
    permissions = {}
    data["permissions"] = permissions

allow = permissions.setdefault("allow", [])
if not isinstance(allow, list):
    allow = []
    permissions["allow"] = allow

entries = [
    f"Read({project_dir}/**)",
    f"Write({project_dir}/reports/**)",
    f"Edit({project_dir}/.processed)",
    f"Read({orchestration_root}/AGENTS.md)",
    f"Read({orchestration_root}/CLAUDE.md)",
]

for entry in entries:
    if entry not in allow:
        allow.append(entry)

# Install the report-notify hook so workers running inside the source project
# trigger this orchestration root's adapter when they write reports/.processed.
# Kept additive: any pre-existing hooks (e.g. another orchestration root) are
# preserved, and each adapter early-exits on paths outside its own root.
hook_command = f"{orchestration_root}/.claude/orchestrate.sh"

hooks = data.setdefault("hooks", {})
if not isinstance(hooks, dict):
    hooks = {}
    data["hooks"] = hooks

post = hooks.setdefault("PostToolUse", [])
if not isinstance(post, list):
    post = []
    hooks["PostToolUse"] = post


def has_command(blocks, command):
    for block in blocks:
        if not isinstance(block, dict):
            continue
        for hook in block.get("hooks", []) or []:
            if isinstance(hook, dict) and hook.get("command") == command:
                return True
    return False


if not has_command(post, hook_command):
    post.append({
        "matcher": "Write|Edit",
        "hooks": [{"type": "command", "command": hook_command}],
    })

settings_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
}

install_codex_project_trust
install_claude_source_settings

echo "OK: installed runtime permissions."
