# Orchestra Agent Rules

This repository is a reusable Claude/Codex multi-agent orchestration template.

## Directory Contract

```text
orchestra/
├── AGENTS.md
├── CLAUDE.md
├── README.md
├── setup.sh
├── .agent/
│   ├── orchestrate.sh
│   ├── prompts/worker.md
│   └── workers/{claude,codex}.sh
├── .claude/
│   ├── orchestrate.sh
│   └── settings.local.json
├── .codex/
│   ├── hooks.json
│   ├── bootstrap-hooks.sh
│   ├── orchestrate.sh
│   └── hooks/orchestrate_post_tool_use.sh
├── .orchestra/
│   └── init-project.sh
└── {PROJECT}/
    ├── config.json
    ├── .processed
    ├── agents/{team}/{agent}/
    ├── tasks/{team}/
    ├── reports/
    └── plans/
```

## Roles

- Human: defines goals and priorities.
- Admin agent: creates task files and reviews reports.
- Worker agent: reads its agent definition, processes task queue, writes reports, and updates `.processed`.
- Orchestrator: resolves project/team/agent/runtime and manages worker panes.

## Queue Contract

- Completed task filenames are recorded one per line in `{PROJECT}/.processed`.
- Workers process `.md` files in `{PROJECT}/tasks/{team}/` that are not in `.processed`.
- Workers write reports to `{PROJECT}/reports/`.
- Workers append processed task filenames to `{PROJECT}/.processed`.

## Agent Definition Contract

Each worker agent has:

```text
agents/{team}/{agent}/
├── role.md
├── skills.md
├── tools.md
├── rules.md
└── workflow.md
```

Agent files should be provider-neutral. Runtime-specific behavior belongs in runtime adapters or explicit runtime capability notes.
