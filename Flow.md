# Orchestration Flow

`AGENTS.md` is the canonical operating contract. This file is a short flow reference.

## Layers

```text
Provider adapters
├── .claude/
└── .codex/

Common core
└── .agent/orchestrate.sh

Runtime workers
└── .agent/workers/{claude,codex}.sh

Project queues
└── {PROJECT}/tasks, {PROJECT}/reports, {PROJECT}/.processed
```

## Task Dispatch

```text
admin writes {PROJECT}/tasks/{team}/TASK.md
-> provider PostToolUse hook calls adapter
-> .agent/orchestrate.sh reads {PROJECT}/config.json
-> route team + filename hints to an agent
-> start or notify worker pane
```

## Report Notification

```text
worker writes {PROJECT}/reports/REPORT.md
-> provider PostToolUse hook calls adapter
-> .agent/orchestrate.sh sends report-arrived message to admin surface
```

## Worker Pane Name

```text
[PROJECT:runtime] agent
```
