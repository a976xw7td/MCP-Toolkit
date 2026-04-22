---
name: wiki
description: "Generate comprehensive project documentation — README, architecture docs, API reference, onboarding guides"
tags: [documentation, writing, wiki, readme]
requires_api_key: false
category: documentation
targets: [claude-code, hermes, openclaw]
version: "1.0.0"
author: MCP-Toolkit
---

# Wiki — Documentation Generator

Produces high-quality technical documentation by reading the actual code, not guessing.

## What It Can Generate

| Document | Contents |
|----------|----------|
| README.md | Project overview, quick start, feature list, badges |
| ARCHITECTURE.md | System design, component map, key decisions |
| API.md | Endpoint reference with request/response examples |
| ONBOARDING.md | New developer guide, local setup, common workflows |
| CONTRIBUTING.md | PR process, coding standards, testing guide |

## Process

1. Reads all relevant source files
2. Identifies patterns, entry points, and public interfaces
3. Drafts documentation that matches the actual behavior
4. Formats for GitHub-flavored Markdown

## Activation

> "wiki: generate a README for this project"
> "create an ARCHITECTURE.md that explains how the auth system works"
> "write an API reference for all endpoints in src/routes/"

## Quality Standard

- Every code example in the docs is extracted from real code or verified to work
- No placeholder text ("TODO: fill this in")
- Bilingual output (English + Chinese) available on request
