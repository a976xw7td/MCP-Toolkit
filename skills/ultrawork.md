---
name: ultrawork
description: "Maximum-effort deep work mode — exhaustive analysis, multiple passes, highest quality output"
tags: [orchestration, deep-work, quality, analysis]
requires_api_key: false
category: orchestration
targets: [claude-code, hermes, openclaw]
version: "1.0.0"
author: MCP-Toolkit
---

# Ultrawork

Deep work mode for tasks that demand thorough, high-quality output rather than fast output.

## What Ultrawork Does

- Reads all relevant context before acting (no assumptions)
- Generates multiple candidate approaches and selects the best one
- Executes with full attention to edge cases and error handling
- Self-reviews the output for quality before finishing
- Produces results that would survive a senior engineer's code review

## Activation

Triggered by the keyword "ulw" or "ultrawork" in a request.

## Difference from Autopilot

| Mode | Speed | Depth | Best for |
|------|-------|-------|----------|
| autopilot | Fast | Standard | Clear tasks with known solutions |
| ultrawork | Thorough | Maximum | Complex problems, architecture decisions, important features |

## Process

1. **Context gathering** — read all related files, not just the obvious ones
2. **Approach analysis** — consider at least 2-3 implementation strategies
3. **Execution** — implement the chosen approach completely
4. **Self-review** — check for: correctness, edge cases, security, performance
5. **Verify** — run tests or checks to confirm it works

## Example

> "ulw: redesign the authentication flow to support OAuth2 and JWT refresh tokens"

Ultrawork will study the existing auth code, research the OAuth2 flow, implement it carefully with proper error handling, write tests, and do a self-review pass before reporting done.
