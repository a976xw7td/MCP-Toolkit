---
name: security-review
description: "Security-focused audit — OWASP Top 10, authentication, authorization, data exposure, dependency vulnerabilities"
tags: [security, audit, owasp, vulnerability]
requires_api_key: false
category: security
targets: [claude-code, hermes, openclaw]
version: "1.0.0"
author: MCP-Toolkit
---

# Security Review

Comprehensive security audit covering the most common and critical vulnerability classes.

## Coverage

### OWASP Top 10
- A01 Broken Access Control
- A02 Cryptographic Failures
- A03 Injection (SQL, NoSQL, Command, LDAP)
- A04 Insecure Design
- A05 Security Misconfiguration
- A06 Vulnerable and Outdated Components
- A07 Identification and Authentication Failures
- A08 Software and Data Integrity Failures
- A09 Security Logging and Monitoring Failures
- A10 Server-Side Request Forgery (SSRF)

### Additional Checks
- Hardcoded secrets and API keys in source code
- JWT implementation (algorithm confusion, expiry, signature verification)
- CORS misconfiguration
- Rate limiting and brute-force protection
- Input validation at API boundaries
- Error messages leaking internal details

## Output

Each finding includes:
- **Severity**: Critical / High / Medium / Low
- **Location**: file:line
- **Vulnerability**: what the issue is
- **Impact**: what an attacker can do with it
- **Fix**: concrete remediation steps

## Activation

> "security-review the authentication module"
> "check this API handler for injection vulnerabilities"
> "audit the entire src/ directory for hardcoded secrets"

## Notes

Security review never exploits vulnerabilities — it identifies and reports them. All findings should be treated as confidential.
