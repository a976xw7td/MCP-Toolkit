---
name: review
description: "Code review — correctness, maintainability, performance, and security with severity ratings"
tags: [review, code-quality, security, performance]
requires_api_key: false
category: quality
targets: [claude-code, hermes, openclaw]
version: "1.0.0"
author: MCP-Toolkit
---

# Code Review

Provides structured, actionable code review feedback with severity ratings.

## Severity Levels

| Level | Meaning |
|-------|---------|
| CRITICAL | Must fix before merge — correctness or security issue |
| MAJOR | Should fix — will cause problems in production |
| MINOR | Nice to fix — code smell or suboptimal pattern |
| INFO | Observation or suggestion — no action required |

## Review Dimensions

1. **Correctness** — does the code do what it's supposed to?
2. **Security** — injection, auth bypass, data exposure risks (OWASP Top 10)
3. **Performance** — N+1 queries, blocking operations, memory leaks
4. **Maintainability** — readability, naming, complexity, SOLID principles
5. **Test coverage** — are the important paths tested?

## Output Format

```
CRITICAL [security] src/api/users.ts:42
  SQL query built with string concatenation — SQL injection risk
  Fix: use parameterized queries

MAJOR [performance] src/db/queries.ts:88
  N+1 query inside loop — will degrade at scale
  Fix: batch with WHERE IN clause

MINOR [style] src/utils/format.ts:15
  Function does two things — consider splitting
```

## Activation

> "review the changes in src/auth/"
> "review this PR for security issues"
> "do a full code review of the payment module"
