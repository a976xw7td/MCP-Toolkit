---
name: ultraqa
description: "Exhaustive QA pass — tests happy paths, edge cases, regressions, and accessibility in one sweep"
tags: [testing, qa, quality, verification]
requires_api_key: false
category: testing
targets: [claude-code, hermes, openclaw]
version: "1.0.0"
author: MCP-Toolkit
---

# UltraQA

Comprehensive quality assurance sweep for any feature or codebase change.

## What It Checks

### Functional
- Happy path flows work as expected
- Edge cases (empty input, max values, special characters)
- Error states and error messages are meaningful
- API contracts match documentation

### Regression
- Existing tests still pass
- Related features not broken by the change
- Database migrations are reversible

### Code Quality
- No obvious security vulnerabilities (injection, XSS, auth bypass)
- No N+1 queries or obvious performance traps
- Error handling is present at system boundaries

### Accessibility (for UI changes)
- Interactive elements have accessible labels
- Color contrast meets WCAG AA minimum
- Keyboard navigation works

## Output Format

UltraQA produces a structured report:

```
PASS ✓  [feature] happy path
PASS ✓  [feature] empty state
FAIL ✗  [feature] XSS in comment field — <script> not escaped
WARN ⚠  [perf] missing index on user_id in posts table
```

## Activation

Say "ultraqa" followed by what you want tested:

> "ultraqa the new user registration flow"
