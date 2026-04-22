---
name: trace
description: "Root cause analysis — given a bug or error, trace back to the exact source and explain why it happens"
tags: [debugging, analysis, root-cause, diagnosis]
requires_api_key: false
category: debugging
targets: [claude-code, hermes, openclaw]
version: "1.0.0"
author: MCP-Toolkit
---

# Trace — Root Cause Analysis

Evidence-driven causal tracing for bugs, errors, and unexpected behavior.

## Method

1. **Reproduce** — confirm the bug is observable with a minimal reproduction
2. **Hypothesize** — generate 2-3 competing explanations for the cause
3. **Gather evidence** — read code, stack traces, logs to confirm or rule out each hypothesis
4. **Identify root cause** — the deepest causal link, not just the symptom
5. **Propose fix** — minimal change that addresses the root cause

## Output Format

```
SYMPTOM: [what the user observes]

HYPOTHESIS A: [candidate cause 1]
  Evidence for: [...]
  Evidence against: [...]

HYPOTHESIS B: [candidate cause 2]
  Evidence for: [...]
  Evidence against: [...]

ROOT CAUSE: [confirmed cause]
  Location: file.ts:line
  Explanation: [why this produces the symptom]

FIX: [specific change needed]
```

## Activation

> "trace this error: TypeError: Cannot read properties of undefined (reading 'id')"
> "why does the login form submit twice sometimes?"

## Notes

Trace never guesses — every conclusion requires evidence from the actual code or logs. If a hypothesis can't be confirmed, it's marked "unresolved" rather than assumed.
