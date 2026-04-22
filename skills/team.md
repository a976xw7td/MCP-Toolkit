---
name: team
description: "Spawn N coordinated worker agents on a shared task — parallel execution with a lead orchestrator"
tags: [orchestration, multi-agent, parallelism, team]
requires_api_key: false
category: orchestration
targets: [claude-code]
version: "1.0.0"
author: MCP-Toolkit
---

# Team — Multi-Agent Orchestration

Spawn a coordinated team of worker agents to tackle large tasks in parallel.

## Syntax

```
/team N:agent-type "task description"
/team "task description"
```

- **N** — number of workers (1-20, auto-sized if omitted)
- **agent-type** — worker specialty: `executor`, `debugger`, `designer`, `writer`
- **task** — the high-level goal to decompose

## Pipeline

```
team-plan → team-exec → team-verify → team-fix (loop)
```

1. **team-plan**: Lead analyzes the codebase and decomposes the task into N subtasks
2. **team-exec**: Workers execute their subtasks in parallel
3. **team-verify**: Verifier agent checks all outputs
4. **team-fix**: Debugger agents fix any issues found

The verify/fix loop repeats until all verification gates pass (max 3 cycles).

## Examples

```bash
# Fix all TypeScript errors across the project with 4 workers
/team 4:executor "fix all TypeScript errors"

# Build a REST API with parallel backend + test workers
/team 3 "implement CRUD API for user management with tests"

# UI work routed to designer agents
/team 4:designer "implement responsive layouts for all pages"
```

## Notes

- Claude Code only (requires native team management tools)
- Workers are independent — give each a scoped, non-overlapping task
- Lead monitors progress and handles coordination automatically
