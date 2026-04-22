---
name: ralph
description: "Persistent retry loop — keeps working until the task is verifiably done, not just attempted"
tags: [orchestration, persistence, reliability, retry]
requires_api_key: false
category: orchestration
targets: [claude-code, hermes, openclaw]
version: "1.0.0"
author: MCP-Toolkit
---

# Ralph — Persistence Loop

Ralph is a persistence wrapper that ensures work is **completed and verified**, not just attempted.

## What Ralph Does

1. Accepts a task description
2. Executes it fully (using autopilot-style execution)
3. Verifies the result against the original goal
4. If verification fails → diagnoses the gap, fixes it, re-verifies
5. Repeats until verified OR explicitly blocked with evidence

## When to Use

- Tasks that tend to be "almost done" but have lingering issues
- Multi-step work where early steps can invalidate later ones
- Anything where you want a guarantee, not a best-effort attempt

## Activation

Triggered by the keyword "ralph" in a request.

## Loop Behavior

```
attempt → verify → pass? → done
                 → fail? → diagnose → fix → verify again
                                            (max 5 cycles)
```

After 5 failed cycles, Ralph stops, reports what it tried, what passed, and what remains blocked.

## Example

> "ralph: migrate the database schema and make sure all tests still pass"

Ralph will run the migration, check test output, fix any failures it can, and only report done when tests are green.
