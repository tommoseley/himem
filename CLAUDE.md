# CLAUDE.md - himem

## Purpose

himem is a new project. This file establishes development governance — the engineering discipline that applies regardless of what himem becomes.

These rules are derived from battle-tested governance in The Combine (`~/dev/TheCombine/`).

---

## Project Root

**Filesystem path:** `~/dev/himem/`

---

## Development Governance

### Bug-First Testing Rule (Mandatory)

When a runtime error, exception, or incorrect behavior is observed, the following sequence **MUST** be followed:

1. **Reproduce First** -- A failing automated test MUST be written that reproduces the observed behavior. The test must fail for the same reason the runtime behavior failed.
2. **Verify Failure** -- The test MUST be executed and verified to fail before any code changes are made.
3. **Fix the Code** -- Only after the failure is verified may code be modified to correct the issue.
4. **Verify Resolution** -- The test MUST pass after the fix. No fix is considered complete unless the reproducing test passes.

#### Constraints

- Tests MUST NOT be written after the fix to prove correctness.
- Code MUST NOT be changed before a reproducing test exists.
- If a bug cannot be reliably reproduced in a test, the issue MUST be escalated rather than patched heuristically.
- Vibe-based fixes are explicitly disallowed.

This rule applies to all runtime defects including: exceptions, incorrect outputs, state corruption, and boundary condition failures.

### Money Tests

Bug fixes MUST include a "money test" that reproduces the exact root-cause scenario:

- The money test MUST fail before the fix is applied.
- The money test MUST pass after the fix is applied.
- The money test serves as the regression guard for that specific defect.

---

### Reuse-First Rule

Before creating anything new (file, module, schema, service):

1. **Search** the codebase and existing docs.
2. **Prefer** extending or refactoring over creating.
3. **Create new** only when reuse is not viable.

- If you create something new, you MUST be able to justify why reuse was not appropriate.
- Creating something new when a suitable existing artifact exists is a defect.

---

### Complexity Management

#### CRAP Score Thresholds

Functions exceeding CRAP score > 30 are flagged as critical and require remediation.

| Score | Rating |
|-------|--------|
| < 5 | Clean |
| 5-15 | Acceptable |
| 15-30 | Smelly |
| > 30 | Critical -- must remediate |

Remediation path: decompose into focused sub-methods (cyclomatic complexity reduction), add test coverage (coverage increase), or both.

#### Structural Rules

- No god functions: business logic MUST be modular and testable.
- Mechanical/deterministic checks are preferred over heuristic validation wherever possible.
- Make every change as simple as possible. Find root causes, not symptoms.
- No temporary fixes. No "we'll clean this up later" without a tech debt entry.
- Changes should only touch what is necessary.

---

### Code Style

- **Explicit dependencies:** All imports and dependencies MUST be declared.
- **Readability over cleverness:** Favor clarity and maintainability.
- **No silent failures:** Errors MUST be surfaced, not swallowed.
- **No speculative abstractions:** Don't design for hypothetical future requirements. Three similar lines of code is better than a premature abstraction.
- **No unnecessary error handling:** Don't add fallbacks for scenarios that can't happen. Trust internal code and framework guarantees. Only validate at system boundaries (user input, external APIs).

---

### Do No Harm

Before making changes to existing code:

1. **Verify assumptions** -- Read the code you're about to change. Understand what it does and why.
2. **Check for dependents** -- Understand what relies on the code you're modifying.
3. **If assumptions are wrong, STOP** -- Report mismatches before touching anything.

Do not infer intent from partial understanding. If something is unclear, ask rather than guess.

---

### Regression Protection

- Fixes MUST NOT reduce existing test coverage.
- Tests MUST be deterministic -- they MUST NOT depend on external services or non-deterministic inputs.
- Every bug fix MUST include the test name and root cause in its report.

---

## Planning Discipline

### Plan Before Executing

For any non-trivial task (3+ steps or architectural decisions):

- Plan before writing code.
- Get alignment before executing.

If something goes wrong during execution, **STOP and re-plan**. Do not push through a failing approach.

### Simplicity First

- Make every change as simple as possible.
- Find root causes, not symptoms.
- No temporary fixes without a tech debt entry.
- Changes should only touch what is necessary.
- If a fix feels hacky, pause and find the elegant solution.

### Verification Before Done

- Never mark a task complete without proving it works.
- Run tests, check logs, demonstrate correctness.
- "Does this look right?" is not verification. Tests passing is verification.

---

## Autonomous Bug Fixing

When a runtime error or incorrect behavior is encountered during work:

- **Do not stop and ask for instructions.** Fix it.
- Follow the Bug-First Testing Rule autonomously.
- **Report what you fixed, not what you found.** Include the test name and root cause.

Escalate only when:

- The bug cannot be reproduced in a test.
- The fix would require changes outside the current scope.
- The root cause is ambiguous and multiple fixes are plausible.

---

## Session Management

### Starting a Session

1. Read this file (`CLAUDE.md`)
2. Scan recent session logs if they exist
3. Understand the current state before proposing work

### Closing a Session

When the user says "Prepare session close" (or similar):

1. Write session summary to `docs/session_logs/YYYY-MM-DD.md`
   - Scope, decisions, implemented, commits, open threads, risks
   - No prose, no reflection -- facts only
2. Ask: **"Ready to close, or do you want to continue?"**

Session summaries are **immutable logs**. Never edit after writing.

---

## Non-Negotiables

- Do not invent process or ceremony
- Do not assume undocumented context
- Session summaries are logs -- never edit after writing
- Discipline > convenience

---

_Governance derived from TheCombine (~/dev/TheCombine/) -- 2026-04-14_
