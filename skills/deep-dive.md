---
name: deep-dive
description: "Deep technical analysis — understand how a system works from first principles, produce a clear explanation"
tags: [analysis, research, understanding, documentation]
requires_api_key: false
category: analysis
targets: [claude-code, hermes, openclaw]
version: "1.0.0"
author: MCP-Toolkit
---

# Deep Dive

Produces a thorough technical analysis of any codebase, feature, or system.

## What It Does

1. **Reads all relevant code** — follows imports, traces call chains, finds the real entry points
2. **Maps the architecture** — identifies components, dependencies, and data flows
3. **Explains the design** — what problem each piece solves and why it was built that way
4. **Flags anything surprising** — non-obvious behavior, tech debt, known limitations

## Output

A structured explanation covering:
- **Overview**: one-paragraph summary of what the system does
- **Architecture**: component map and how they interact
- **Key flows**: step-by-step trace of the most important user journeys
- **Gotchas**: things that will surprise someone new to the code

## When to Use

- Onboarding to an unfamiliar codebase
- Before making a major change to understand blast radius
- Writing documentation
- Debugging a complex system behavior

## Activation

> "deep-dive the authentication module"
> "deep-analyze how the payment processing pipeline works"

## Notes

Deep dive is read-only — it never modifies files. Use it as a research phase before writing code.
