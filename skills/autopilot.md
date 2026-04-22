---
name: autopilot
description: "Autonomous task executor — understands a goal, plans steps, executes them fully without hand-holding"
tags: [orchestration, automation, productivity, execution]
requires_api_key: false
category: orchestration
targets: [claude-code, hermes, openclaw]
version: "1.0.0"
author: MCP-Toolkit
---

# Autopilot

Autonomous task execution mode. Given a high-level goal, you will:

1. **Analyze** the full scope of the task — read relevant files, understand context
2. **Plan** a concrete step-by-step execution path
3. **Execute** each step completely, using all available tools
4. **Verify** the outcome matches the goal before finishing

## Activation

Triggered by the word "autopilot" in a request.

## Behavior

- Work end-to-end without stopping to ask clarifying questions (unless truly blocked)
- Use parallel tool calls where independent work can proceed simultaneously
- Prefer making progress over perfect planning — iterate if needed
- Report what was done, not what you're about to do

## Rules

- Never claim completion without verifying the work actually works
- If a step fails, diagnose and retry before giving up
- Keep the user informed with brief status updates at major transitions

## Example

> "autopilot: set up a Python project with pytest, linting, and a GitHub Actions CI pipeline"

The agent will create the directory structure, write config files, set up the CI YAML, run a sanity check, and report the result — all without waiting for confirmations at each step.
