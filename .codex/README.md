# Codex Orchestration Entrypoint

이 디렉토리는 Codex에서 오케스트레이션을 시작하기 위한 entrypoint를 둔다.

`.codex/orchestrate.sh`는 Codex runtime wrapper 역할을 한다. Codex 기반 trigger, manual command, automation은 이 wrapper를 호출하고, 실제 공통 routing은 provider-neutral core인 `.agent/orchestrate.sh`가 처리한다.

`.codex/hooks.json`은 Codex `PostToolUse` hook으로 모든 tool 이벤트를 `.codex/hooks/orchestrate_post_tool_use.sh`에 전달한다. hook script가 payload에서 `reports/*.md` 변경만 골라 `.codex/orchestrate.sh`에 전달한다.

`.codex/watch.sh`는 hook을 사용할 수 없는 환경을 위한 polling fallback이다. 기존 파일은 첫 실행 시 기준선으로만 기록하고, 이후 변경된 `tasks/**/*.md`와 `reports/*.md`를 hook JSON으로 변환해 `.codex/orchestrate.sh`에 전달한다.

## Contract

- 호출자는 공통 hook JSON을 stdin으로 전달한다.
- wrapper는 `ORCHESTRATION_RUNTIME=codex`를 설정한다.
- 이후 `.agent/orchestrate.sh`로 위임한다.
- `.claude/orchestrate.sh`에는 의존하지 않는다.

## Hooks

Codex hook은 `.codex/hooks.json`에 정의한다.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash .codex/hooks/orchestrate_post_tool_use.sh"
          }
        ]
      }
    ]
  }
}
```

Codex가 새 hook을 신뢰해야 하므로 사용자별로 한 번 trust 상태를 만들어야 한다.

```bash
cd orchestration_system
bash .codex/bootstrap-hooks.sh --install-config
bash .codex/bootstrap-hooks.sh --check
```

`--install-config`는 현재 템플릿 hook의 trusted hash를 `~/.codex/config.toml`에 직접 기록한다. 수동 확인을 원하면 Codex에서 `/hooks`를 열고 `t`를 눌러 trust all을 승인한다. cmux 안의 Codex surface에서 자동 입력을 시도하려면:

```bash
bash .codex/bootstrap-hooks.sh --cmux-trust
bash .codex/bootstrap-hooks.sh --check
```

Codex worker는 시작 전에 이 check를 수행한다. trust 상태가 없으면 worker를 띄우지 않고 실패하게 해서, report는 생성됐지만 admin 알림이 누락되는 상태를 방지한다.

## Watcher Fallback

```bash
cd orchestration_system
.codex/watch.sh
```

Polling interval은 기본 2초다. watcher가 실행 중이어야 Codex worker가 쓴 `reports/*.md` 변경이 admin surface 알림으로 이어진다.

수동 watcher는 디버깅/비상용이다.

```bash
CODEX_WATCH_INTERVAL=1 .codex/watch.sh
```

State file 위치를 바꾸려면:

```bash
CODEX_WATCH_STATE=/private/tmp/my-watch.state .codex/watch.sh
```

orchestrate 호출 때 fallback watcher를 강제로 켜려면:

```bash
ORCHESTRATION_CODEX_WATCH=1 .codex/orchestrate.sh
```
