# Agent Runtime Layer

`.agent`는 Claude/Codex 공용 worker runtime 계약을 담는 provider-neutral layer다.

`.claude/`와 `.codex/`는 각 provider의 entrypoint이고, `.agent/`는 공통 routing, worker 실행 정책, prompt 계약을 정의한다.

## Files

```text
.agent/
├── runtime.json
├── orchestrate.sh
├── workers/
│   ├── claude.sh
│   └── codex.sh
└── prompts/
    └── worker.md
```

## Runtime Contract

- `inherit`: 현재 admin runtime을 따른다.
- `claude`: Claude worker를 실행한다.
- `codex`: Codex worker를 실행한다.

`.agent/orchestrate.sh`는 공통 hook JSON을 받아 task/report 이벤트를 처리한다. provider wrapper는 `ORCHESTRATION_RUNTIME`만 설정하고 이 core로 위임한다.

orchestrator는 최종 runtime을 결정한 뒤 `.agent/workers/{runtime}.sh "$WORK_DIR"` 형태로 worker command를 구성한다.

## Prompt Contract

`.agent/prompts/worker.md`는 provider-neutral template이다. provider 이름에 의존하지 않고 agent 정의 파일과 큐 규칙을 설명한다.

provider-specific 기능은 사용할 수 있을 때만 사용한다. 핵심 계약은 task queue 처리, report 작성, `.processed` 갱신이다.
