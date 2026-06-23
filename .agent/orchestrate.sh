#!/bin/bash
# orchestrate.sh - provider-neutral orchestration core
# tasks/ 에 파일 쓰면 같은 workspace 안에서 split pane 생성 + 선택 runtime 실행
# reports/ 에 파일 쓰면 admin pane에 알림

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATION_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_ROOT="$ORCHESTRATION_ROOT/.agent"

normalize_runtime() {
    case "${1:-}" in
        claude|codex) echo "$1" ;;
        inherit) echo "inherit" ;;
        *) echo "" ;;
    esac
}

ADMIN_RUNTIME=$(normalize_runtime "${ORCHESTRATION_RUNTIME:-inherit}")
[ -z "$ADMIN_RUNTIME" ] || [ "$ADMIN_RUNTIME" = "inherit" ] && ADMIN_RUNTIME="claude"

# Hook에서 stdin으로 JSON이 들어옴
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); i=d.get('tool_input',{}); print(i.get('file_path',''))" 2>/dev/null || echo "")

# Write/Edit 가 아니면 무시
[ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ] && exit 0

# orchestration root 경로가 아니면 무시
[[ "$FILE_PATH" != "$ORCHESTRATION_ROOT/"* ]] && exit 0

# ─── 프로젝트명 추출 ($ORCHESTRATION_ROOT/{PROJECT}/tasks/...) ───
RELATIVE_PATH="${FILE_PATH#"$ORCHESTRATION_ROOT"/}"
PROJECT="${RELATIVE_PATH%%/*}"

[ -z "$PROJECT" ] && exit 0

PROJECT_DIR="$ORCHESTRATION_ROOT/$PROJECT"
CONFIG="$PROJECT_DIR/config.json"

[ ! -f "$CONFIG" ] && exit 0

WORK_DIR=$(python3 -c "import json; print(json.load(open('$CONFIG'))['project_dir'])" 2>/dev/null || echo "")
[ -z "$WORK_DIR" ] && exit 0

# admin surface ID 저장 경로
ADMIN_SURFACE_FILE="$PROJECT_DIR/.admin_surface"

# ─── 헬퍼: 현재 surface ref 가져오기 ───
get_current_surface() {
    cmux identify 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
caller = data.get('caller', {})
print(caller.get('surface_ref', ''))
" 2>/dev/null || echo ""
}

# ─── 헬퍼: tab 이름으로 surface 찾기 ───
find_surface_by_name() {
    local name="$1"
    # tree 출력에서 surface 이름 매칭
    cmux tree 2>/dev/null | python3 -c "
import sys
name = '$name'
for line in sys.stdin:
    line = line.strip()
    if 'surface:' in line and name in line:
        # surface:N 추출
        parts = line.split()
        for p in parts:
            if p.startswith('surface:'):
                print(p)
                sys.exit(0)
" 2>/dev/null || echo ""
}

cmux_output() {
    local output
    if ! output=$(cmux "$@" 2>&1); then
        echo "ERROR: cmux $* failed: $output" >&2
        return 1
    fi
    printf '%s\n' "$output"
}

# ─── 헬퍼: 파일명에서 에이전트 결정 ───
resolve_agent() {
    local team="$1"
    local filename="$2"

    python3 -c "
import json, sys
config = json.load(open('$CONFIG'))
team_cfg = config['agents'].get('$team', {})
hints = team_cfg.get('hints', {})
default = team_cfg.get('default', '')
filename = '$filename'.lower()
for keyword, agent in hints.items():
    if keyword in filename:
        print(agent)
        sys.exit(0)
print(default)
" 2>/dev/null || echo ""
}

# ─── 헬퍼: task frontmatter에서 runtime 결정 ───
frontmatter_runtime() {
    local task_path="$1"

    TASK_PATH="$task_path" python3 -c '
import os

path = os.environ.get("TASK_PATH", "")
try:
    with open(path, encoding="utf-8") as f:
        first = f.readline()
        if first.strip() != "---":
            raise SystemExit
        for line in f:
            if line.strip() == "---":
                break
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            if key.strip() == "runtime":
                value = value.strip().strip("\"").strip(chr(39)).lower()
                if value in {"claude", "codex", "inherit"}:
                    print(value)
                break
except Exception:
    raise SystemExit
' 2>/dev/null || echo ""
}

# ─── 헬퍼: config.json에서 runtime 결정 ───
config_runtime() {
    local team="$1"
    local agent="$2"

    RUNTIME_CONFIG="$CONFIG" RUNTIME_TEAM="$team" RUNTIME_AGENT="$agent" python3 -c '
import json
import os

config_path = os.environ["RUNTIME_CONFIG"]
team = os.environ["RUNTIME_TEAM"]
agent = os.environ["RUNTIME_AGENT"]

try:
    config = json.load(open(config_path, encoding="utf-8"))
except Exception:
    raise SystemExit

runtime = config.get("runtime", {})
if not isinstance(runtime, dict):
    raise SystemExit

agents = runtime.get("agents", {})
teams = runtime.get("teams", {})
values = [
    agents.get(agent) if isinstance(agents, dict) else None,
    teams.get(team) if isinstance(teams, dict) else None,
    runtime.get("default"),
]

for value in values:
    if isinstance(value, str):
        value = value.lower()
        if value in {"claude", "codex", "inherit"}:
            print(value)
            break
' 2>/dev/null || echo ""
}

# ─── 헬퍼: 최종 runtime 결정 ───
resolve_runtime() {
    local team="$1"
    local agent="$2"
    local task_file="$3"
    local task_path="$PROJECT_DIR/tasks/$team/$task_file"
    local runtime

    runtime=$(frontmatter_runtime "$task_path")
    [ -z "$runtime" ] && runtime=$(config_runtime "$team" "$agent")
    runtime=$(normalize_runtime "$runtime")

    if [ -z "$runtime" ] || [ "$runtime" = "inherit" ]; then
        runtime="$ADMIN_RUNTIME"
    fi

    normalize_runtime "$runtime"
}

# ─── 헬퍼: 팀 리드 여부 확인 ───
is_team_lead() {
    local team="$1"
    python3 -c "
import json
config = json.load(open('$CONFIG'))
team_cfg = config['agents'].get('$team', {})
print('true' if team_cfg.get('team_lead', False) else 'false')
" 2>/dev/null || echo "false"
}

# ─── 헬퍼: 처리 완료 파일 경로 ───
PROCESSED_FILE="$PROJECT_DIR/.processed"
touch "$PROCESSED_FILE" 2>/dev/null

# ─── 헬퍼: 태스크가 이미 처리됐는지 확인 ───
is_processed() {
    local task="$1"
    grep -qxF "$task" "$PROCESSED_FILE" 2>/dev/null
}

# ─── 헬퍼: shell 인자 안전 quoting ───
shell_quote() {
    printf "%q" "$1"
}

# ─── 헬퍼: worker 실행 command 생성 ───
worker_command() {
    local runtime="$1"
    local worker_script="$AGENT_ROOT/workers/$runtime.sh"

    if [ ! -f "$worker_script" ]; then
        runtime="claude"
        worker_script="$AGENT_ROOT/workers/claude.sh"
    fi

    echo "bash $(shell_quote "$worker_script") $(shell_quote "$WORK_DIR")"
}

# ─── 헬퍼: provider-neutral worker prompt 생성 ───
render_worker_prompt() {
    local runtime="$1"
    local team="$2"
    local agent="$3"
    local agent_dir="$4"
    local template="$AGENT_ROOT/prompts/worker.md"

    if [ ! -f "$template" ]; then
        echo "너는 ${runtime} runtime에서 실행 중인 @${agent} 에이전트다. ${agent_dir}/ 의 role.md, skills.md, tools.md, rules.md, workflow.md를 모두 읽고 역할을 파악해. 큐 기반으로 동작해: 1) ${PROJECT_DIR}/.processed 파일을 읽어서 이미 처리된 태스크 목록을 확인해. 2) ${PROJECT_DIR}/tasks/${team}/ 디렉토리의 .md 파일 중 .processed에 없는 것을 찾아서 순서대로 처리해. 3) 각 태스크 완료 후 ${PROJECT_DIR}/reports/ 에 리포트를 작성하고, 처리한 파일명을 ${PROJECT_DIR}/.processed 에 한 줄 추가해. 4) 미처리 태스크가 더 있으면 계속 처리하고, 없으면 '대기 중'이라고 말하고 멈춰."
        return 0
    fi

    RUNTIME="$runtime" \
    TEAM="$team" \
    AGENT="$agent" \
    AGENT_DIR="$agent_dir" \
    PROJECT_DIR_ENV="$PROJECT_DIR" \
    WORK_DIR_ENV="$WORK_DIR" \
    python3 - "$template" <<'PY'
import os
import sys

template_path = sys.argv[1]
text = open(template_path, encoding="utf-8").read()
replacements = {
    "{{runtime}}": os.environ["RUNTIME"],
    "{{team}}": os.environ["TEAM"],
    "{{agent}}": os.environ["AGENT"],
    "{{agent_dir}}": os.environ["AGENT_DIR"],
    "{{project_dir}}": os.environ["PROJECT_DIR_ENV"],
    "{{work_dir}}": os.environ["WORK_DIR_ENV"],
}
for key, value in replacements.items():
    text = text.replace(key, value)
print(text)
PY
}

# ─── 헬퍼: split pane 생성 + runtime 실행 ───
spawn_worker() {
    local role="$1"
    local team="$2"
    local agent="$3"
    local task_file="$4"
    local runtime
    runtime=$(resolve_runtime "$team" "$agent" "$task_file")
    [ -z "$runtime" ] || [ "$runtime" = "inherit" ] && runtime="claude"
    local tab_name="[$PROJECT:$runtime] $role"

    if [ "${ORCHESTRATE_DRY_RUN:-}" = "1" ]; then
        echo "project=$PROJECT"
        echo "team=$team"
        echo "agent=$agent"
        echo "runtime=$runtime"
        echo "tab_name=$tab_name"
        echo "command=$(worker_command "$runtime")"
        return 0
    fi

    # 이미 해당 role/runtime의 surface가 있으면 → 새 태스크 도착 알림
    local existing_surface
    existing_surface=$(find_surface_by_name "$tab_name" 2>/dev/null || echo "")
    if [ -n "$existing_surface" ]; then
        cmux_output send --surface "$existing_surface" "새 태스크가 큐에 추가됐다. ${PROJECT_DIR}/tasks/${team}/ 에서 미처리 태스크를 확인하고 처리해. .processed 파일 기준으로 아직 처리 안 된 것만 순서대로." >/dev/null
        cmux_output send-key --surface "$existing_surface" enter >/dev/null
        cmux notify --title "[$PROJECT] Task → $role" --body "$task_file" 2>/dev/null || true
        return 0
    fi

    # 같은 workspace 안에서 오른쪽으로 split
    local new_surface
    local split_output
    split_output=$(cmux_output new-split right)
    new_surface=$(printf '%s\n' "$split_output" | grep -oE 'surface:[0-9]+' | head -1 || true)
    if [ -z "$new_surface" ]; then
        echo "ERROR: cmux new-split did not return a surface ref. Output: $split_output" >&2
        return 1
    fi

    # tab 이름으로 식별 가능하게 설정
    cmux_output rename-tab --surface "$new_surface" "$tab_name" >/dev/null

    # 선택된 runtime 실행
    sleep 0.5
    cmux_output send --surface "$new_surface" "$(worker_command "$runtime")" >/dev/null
    cmux_output send-key --surface "$new_surface" enter >/dev/null

    # runtime 시작 대기
    sleep 3

    # 팀 리드 여부에 따라 프롬프트 분기
    local agent_dir="$PROJECT_DIR/agents/$team/$agent"
    local is_lead
    is_lead=$(is_team_lead "$team")

    local prompt
    if [ "$is_lead" = "true" ]; then
        prompt="$(render_worker_prompt "$runtime" "$team" "$agent" "$agent_dir")

추가 팀 리드 규칙: 직접 코딩하지 않고, 사용 가능한 하위 에이전트/작업 위임 도구가 있으면 워커 에이전트를 spawn한다. 독립적인 모듈은 병렬 실행하고 결과를 취합한다."
    else
        prompt="$(render_worker_prompt "$runtime" "$team" "$agent" "$agent_dir")"
    fi

    cmux_output send --surface "$new_surface" "$prompt" >/dev/null
    cmux_output send-key --surface "$new_surface" enter >/dev/null
    cmux notify --title "[$PROJECT] Spawned $role" --body "$task_file" 2>/dev/null
}

FILENAME=$(basename "$FILE_PATH")

# ─── tasks/ 에 쓰면 → admin surface 저장 + split pane으로 워커 생성 ───
if [[ "$FILE_PATH" == *"/tasks/backend/"* ]]; then
    # admin이 task를 쓰는 시점 → 현재 surface가 admin
    CURRENT_SURFACE=$(get_current_surface)
    [ -n "$CURRENT_SURFACE" ] && echo "$CURRENT_SURFACE" > "$ADMIN_SURFACE_FILE"
    AGENT=$(resolve_agent "backend" "$FILENAME")
    spawn_worker "$AGENT" "backend" "$AGENT" "$FILENAME"

elif [[ "$FILE_PATH" == *"/tasks/frontend/"* ]]; then
    CURRENT_SURFACE=$(get_current_surface)
    [ -n "$CURRENT_SURFACE" ] && echo "$CURRENT_SURFACE" > "$ADMIN_SURFACE_FILE"
    AGENT=$(resolve_agent "frontend" "$FILENAME")
    spawn_worker "$AGENT" "frontend" "$AGENT" "$FILENAME"

elif [[ "$FILE_PATH" == *"/tasks/planning/"* ]]; then
    CURRENT_SURFACE=$(get_current_surface)
    [ -n "$CURRENT_SURFACE" ] && echo "$CURRENT_SURFACE" > "$ADMIN_SURFACE_FILE"
    AGENT=$(resolve_agent "planning" "$FILENAME")
    spawn_worker "$AGENT" "planning" "$AGENT" "$FILENAME"

elif [[ "$FILE_PATH" == *"/tasks/agent/"* ]]; then
    CURRENT_SURFACE=$(get_current_surface)
    [ -n "$CURRENT_SURFACE" ] && echo "$CURRENT_SURFACE" > "$ADMIN_SURFACE_FILE"
    AGENT=$(resolve_agent "agent" "$FILENAME")
    spawn_worker "$AGENT" "agent" "$AGENT" "$FILENAME"

# ─── reports/ 에 쓰면 → 저장된 admin surface에 알림 ───
elif [[ "$FILE_PATH" == *"/reports/"* ]]; then
    ADMIN_SURFACE=""
    if [ -f "$ADMIN_SURFACE_FILE" ]; then
        ADMIN_SURFACE=$(cat "$ADMIN_SURFACE_FILE")
    fi
    if [ -n "$ADMIN_SURFACE" ]; then
        cmux_output send --surface "$ADMIN_SURFACE" "리포트가 도착했다. $PROJECT_DIR/reports/$FILENAME 읽고 확인해" >/dev/null
        cmux_output send-key --surface "$ADMIN_SURFACE" enter >/dev/null
        cmux notify --title "[$PROJECT] Report" --body "$FILENAME"
    fi
fi

exit 0
