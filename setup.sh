#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<EOF
Usage:
  bash setup.sh [--non-interactive --project NAME --source DIR [team=agent ...]]

Interactive setup asks for:
  - source project path
  - orchestration project name
  - team=agent mappings

Examples:
  bash setup.sh
  bash setup.sh --non-interactive --project myapp --source /path/to/myapp backend=main-api frontend=web planning=planner
EOF
}

PROJECT_NAME=""
SOURCE_DIR=""
NON_INTERACTIVE=0
TEAM_ARGS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --non-interactive)
            NON_INTERACTIVE=1
            shift
            ;;
        --project)
            PROJECT_NAME="${2:-}"
            shift 2
            ;;
        --source)
            SOURCE_DIR="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *=*)
            TEAM_ARGS+=("$1")
            shift
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

prompt() {
    local label="$1"
    local default="${2:-}"
    local value
    if [ -n "$default" ]; then
        read -r -p "$label [$default]: " value
        printf '%s\n' "${value:-$default}"
    else
        read -r -p "$label: " value
        printf '%s\n' "$value"
    fi
}

default_project_name() {
    basename "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-'
}

if [ "$NON_INTERACTIVE" != "1" ]; then
    echo "== Orchestra setup =="
    if [ -z "$SOURCE_DIR" ]; then
        SOURCE_DIR="$(prompt "Source project absolute path")"
    fi
    if [ -z "$PROJECT_NAME" ]; then
        PROJECT_NAME="$(prompt "Orchestration project name" "$(default_project_name "$SOURCE_DIR")")"
    fi
    if [ "${#TEAM_ARGS[@]}" -eq 0 ]; then
        echo "Enter team=agent mappings separated by spaces."
        echo "Example: backend=main-api frontend=web planning=planner"
        mappings="$(prompt "Mappings" "planning=planner")"
        # shellcheck disable=SC2206
        TEAM_ARGS=($mappings)
    fi
fi

if [ -z "$PROJECT_NAME" ] || [ -z "$SOURCE_DIR" ]; then
    echo "ERROR: project name and source path are required." >&2
    usage >&2
    exit 2
fi

if [ "${#TEAM_ARGS[@]}" -eq 0 ]; then
    TEAM_ARGS=("planning=planner")
fi

echo "Installing Codex hook trust state..."
bash "$SCRIPT_DIR/.codex/bootstrap-hooks.sh" --install-config

echo "Validating Claude hook settings..."
python3 -m json.tool "$SCRIPT_DIR/.claude/settings.local.json" >/dev/null
bash -n "$SCRIPT_DIR/.claude/orchestrate.sh"

echo "Creating project scaffold..."
bash "$SCRIPT_DIR/.orchestra/init-project.sh" "$PROJECT_NAME" "$SOURCE_DIR" "${TEAM_ARGS[@]}"

cat <<EOF

OK: setup complete.

Next:
  - Open this orchestration repo in Claude or Codex.
  - Create task files under $PROJECT_NAME/tasks/{team}/.
  - Worker reports will be written under $PROJECT_NAME/reports/.
EOF
