# Orchestra

Claude/Codex compatible file-queue orchestration template.

## Requirements

Install the runtime you want to use.

- Claude users: install Claude Code and make sure `claude` is on `PATH`.
- Codex users: install Codex CLI and make sure `codex` is on `PATH`.
- All users: install `cmux`; Orchestra uses cmux panes to keep admin and worker sessions connected.
- Local tools: `bash`, `python3`, and `jq` are not required, but `python3` is used by setup and routing scripts.

You can use only Claude, only Codex, or both. If a task does not override runtime, workers inherit the admin runtime.

## Quick Start

```bash
git clone <repo-url> orchestra
cd orchestra
bash setup.sh
```

The setup script asks for:

- source project absolute path
- orchestration project name
- `team=agent` mappings, for example `backend=main-api frontend=web planning=planner`

Non-interactive setup:

```bash
bash setup.sh --non-interactive --project myapp --source /absolute/path/to/myapp backend=main-api frontend=web planning=planner
```

## What Setup Does

- installs Codex hook trust state into the current user's `~/.codex/config.toml`
- validates Claude hook settings
- creates `{PROJECT}/config.json`
- creates `{PROJECT}/agents/{team}/{agent}/`
- creates `{PROJECT}/tasks/{team}/`, `{PROJECT}/reports/`, and `{PROJECT}/plans/`

For Claude users, `.claude/settings.local.json` is already included in the repo. Claude Code loads it when this orchestration repo is opened, and its `PostToolUse` hook calls `.claude/orchestrate.sh`.

For Codex users, setup writes the hook trust state into the current user's Codex config so `/hooks -> t` is not required for the bundled template hook.

## Using With Claude

1. Install Claude Code.
2. Clone this repo and run `bash setup.sh`.
3. Open this orchestration repo in Claude Code.
4. Create a task file under `{PROJECT}/tasks/{team}/`.

Example task:

```markdown
# TASK-001

Inspect the source project and write a short report.
```

When Claude writes the task file, the Claude `PostToolUse` hook starts or notifies the matching worker pane. The worker writes a report under `{PROJECT}/reports/`, and the report hook notifies the admin pane.

Claude worker model defaults to `sonnet`. Override it with:

```bash
export ORCHESTRATION_CLAUDE_MODEL=opus
```

Set it in the shell that starts the orchestration session.

## Using With Codex

1. Install Codex CLI.
2. Clone this repo and run `bash setup.sh`.
3. Open this orchestration repo in Codex.
4. Create a task file under `{PROJECT}/tasks/{team}/`.

Codex worker model defaults to `gpt-5.5`. Override it with `ORCHESTRATION_CODEX_MODEL`.

## Task Runtime Override

Use frontmatter when a specific task should run on a specific runtime:

```markdown
---
runtime: codex
---

# TASK-001
```

Allowed values are `claude`, `codex`, and `inherit`.

## Runtime Flow

```text
admin writes {PROJECT}/tasks/{team}/TASK.md
-> Claude or Codex PostToolUse hook runs provider adapter
-> .agent/orchestrate.sh routes task to agent
-> cmux worker pane starts Claude or Codex
-> worker writes {PROJECT}/reports/REPORT.md
-> report hook notifies admin surface
```

## Project Config

`{PROJECT}/config.json`:

```json
{
  "project_name": "myapp",
  "project_dir": "/absolute/path/to/myapp",
  "runtime": {
    "default": "inherit",
    "teams": {},
    "agents": {}
  },
  "agents": {
    "backend": {
      "default": "main-api",
      "hints": {}
    }
  }
}
```

Runtime resolution order:

1. task frontmatter `runtime: codex|claude|inherit`
2. `config.json` `runtime.agents.{agent}`
3. `config.json` `runtime.teams.{team}`
4. `config.json` `runtime.default`
5. current admin runtime
6. fallback `claude`

## Validation

```bash
bash -n setup.sh .orchestra/init-project.sh
bash -n .agent/orchestrate.sh .agent/workers/claude.sh .agent/workers/codex.sh
bash -n .claude/orchestrate.sh .codex/orchestrate.sh .codex/hooks/orchestrate_post_tool_use.sh
python3 -m json.tool .claude/settings.local.json >/dev/null
python3 -m json.tool .codex/hooks.json >/dev/null
bash .codex/bootstrap-hooks.sh --check
```
