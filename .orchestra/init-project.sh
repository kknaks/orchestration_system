#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATION_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<EOF
Usage:
  bash .orchestra/init-project.sh PROJECT_NAME SOURCE_DIR [team=agent ...]

Example:
  bash .orchestra/init-project.sh myapp /path/to/myapp backend=main-api frontend=web planning=planner

Creates:
  PROJECT_NAME/config.json
  PROJECT_NAME/.processed
  PROJECT_NAME/agents/{team}/{agent}/{role,skills,tools,rules,workflow}.md
  PROJECT_NAME/tasks/{team}/
  PROJECT_NAME/reports/
  PROJECT_NAME/plans/
EOF
}

PROJECT_NAME="${1:-}"
SOURCE_DIR="${2:-}"
shift 2 2>/dev/null || true

if [ -z "$PROJECT_NAME" ] || [ -z "$SOURCE_DIR" ]; then
    usage
    exit 2
fi

case "$PROJECT_NAME" in
    */*|.*|"")
        echo "ERROR: PROJECT_NAME must be a simple directory name." >&2
        exit 2
        ;;
esac

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
PROJECT_DIR="$ORCHESTRATION_ROOT/$PROJECT_NAME"

if [ "$#" -eq 0 ]; then
    set -- "planning=planner"
fi

PROJECT_NAME="$PROJECT_NAME" SOURCE_DIR="$SOURCE_DIR" PROJECT_DIR="$PROJECT_DIR" python3 - "$@" <<'PY'
import json
import os
import sys
from pathlib import Path

project_name = os.environ["PROJECT_NAME"]
source_dir = os.environ["SOURCE_DIR"]
project_dir = Path(os.environ["PROJECT_DIR"])

agents = {}
for item in sys.argv[1:]:
    if "=" not in item:
        raise SystemExit(f"Invalid team=agent mapping: {item}")
    team, agent = item.split("=", 1)
    team = team.strip()
    agent = agent.strip()
    if not team or not agent:
        raise SystemExit(f"Invalid team=agent mapping: {item}")
    agents[team] = {"default": agent, "hints": {}}

project_dir.mkdir(parents=True, exist_ok=True)
(project_dir / "reports").mkdir(exist_ok=True)
(project_dir / "plans").mkdir(exist_ok=True)
(project_dir / ".processed").touch()

for team, cfg in agents.items():
    agent = cfg["default"]
    (project_dir / "tasks" / team).mkdir(parents=True, exist_ok=True)
    agent_dir = project_dir / "agents" / team / agent
    agent_dir.mkdir(parents=True, exist_ok=True)
    files = {
        "role.md": f"# {agent} Role\n\nYou are the `{agent}` worker agent for the `{team}` team.\n",
        "skills.md": f"# {agent} Skills\n\n- Read tasks from `{project_name}/tasks/{team}/`.\n- Produce focused implementation or analysis reports.\n",
        "tools.md": "# Tools\n\nUse available runtime tools conservatively. Prefer reading local project context before editing.\n",
        "rules.md": "# Rules\n\n- Do not modify unrelated files.\n- Write one report per completed task.\n- Append completed task filenames to `.processed`.\n",
        "workflow.md": f"# Workflow\n\n1. Read `{project_name}/.processed`.\n2. Find unprocessed `.md` files in `{project_name}/tasks/{team}/`.\n3. Complete tasks in filename order.\n4. Write reports to `{project_name}/reports/`.\n5. Append processed task filenames to `{project_name}/.processed`.\n",
    }
    for name, text in files.items():
        path = agent_dir / name
        if not path.exists():
            path.write_text(text, encoding="utf-8")

config = {
    "project_name": project_name,
    "project_dir": source_dir,
    "runtime": {
        "default": "inherit",
        "teams": {},
        "agents": {},
    },
    "agents": agents,
}
(project_dir / "config.json").write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

claude = project_dir / "CLAUDE.md"
if not claude.exists():
    claude.write_text(
        f"# {project_name}\n\nThis project is managed by the orchestration root. See `AGENTS.md` at the root.\n",
        encoding="utf-8",
    )

print(f"OK: initialized {project_dir}")
PY
