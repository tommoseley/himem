# MSA-001 — Memory Stream Application

> Generated: 2026-04-13T15:02:44.917215+00:00
> Renderer: render-md@1.0.0
> Documents: 23
> Governance: native

## Table of Contents

### Project Governance
  - [GOV-SEC-T0-002 -- Tier-0 Secrets Handling and Ingress Control Policy](#gov-sec-t0-002)
  - [POL-ADR-EXEC-001: ADR Execution Authorization Process](#pol-adr-exec-001)
  - [POL-ARCH-001: Architectural Integrity Standard](#pol-arch-001)
  - [POL-CODE-001: Code Construction Standard](#pol-code-001)
  - [POL-QA-001: Testing & Verification Standard](#pol-qa-001)
  - [POL-WS-001: Standard Work Statements](#pol-ws-001)

### Pipeline Documents
- [CI-001 — Concierge Intake: Memory Stream Application](#ci-001)
- [PD-001 — Memory Stream Application](#pd-001)
- [IP-001 — Memory Stream Application: Implementation Plan](#ip-001)
- [TA-001 — Memory Stream Application: Technical Architecture](#ta-001)
- [WP-025 — Voice and Text Input Capture Foundation](#wp-025)
  - [WS-136 — iOS Speech Framework Integration](#ws-136)
  - [WS-137 — Direct Text Input Interface](#ws-137)
  - [WS-138 — Core Data Models and Entry Storage](#ws-138)
  - [WS-139 — Basic Journal Display Implementation](#ws-139)
  - [WS-140 — Siri Integration for Voice Interpretation](#ws-140)
- [WP-026 — Background AI Processing Pipeline](#wp-026)
  - [WS-141 — Implement Processing Queue Manager and Background Task Infrastructure](#ws-141)
  - [WS-142 — Implement Local Entity Extractor with Core ML Models](#ws-142)
  - [WS-143 — Implement Cloud AI Facade with Anthropic API Integration](#ws-143)
  - [WS-144 — Implement AI Processing Engine with Hybrid Processing Orchestration](#ws-144)
  - [WS-145 — Implement Entity Storage Manager with Core Data Integration](#ws-145)
  - [WS-146 — Integrate Background AI Processing Pipeline End-to-End](#ws-146)
- [WP-027 — Structured Data Presentation and Search](#wp-027)
  - [WS-147 — Implement Inline Tag Display Infrastructure](#ws-147)
  - [WS-148 — Enhance Journal Display with Inline Tags](#ws-148)
  - [WS-149 — Implement Enhanced Search Engine](#ws-149)
  - [WS-150 — Implement Tag-Based Navigation and Discovery](#ws-150)
  - [WS-151 — Implement Filter Persistence and Search History](#ws-151)

---

# Project Governance

These standards apply to all work in this project.

---

## GOV-SEC-T0-002 -- Tier-0 Secrets Handling and Ingress Control Policy

# GOV-SEC-T0-002 -- Tier-0 Secrets Handling and Ingress Control Policy

**Status:** Active
**Scope:** All HTTP ingress, PGC workflow nodes, stabilization, rendering, and logging subsystems

---

## 1. Purpose

This policy establishes deterministic, multi-layer controls designed to prevent persistence of credential material within The Combine.

The system is designed to:

- Prevent secret solicitation
- Detect secret ingress
- Block workflow execution
- Redact prior to persistence
- Audit detection events

No claim of infallibility is made.

---

## 2. Definitions

### 2.1 Secret

A Secret is any value that:

- Grants authentication or authorization
- Enables service/API access
- Is intended for storage in a secret manager
- Contains credential material within structured formats

Examples (non-exhaustive):

- API keys
- Passwords
- OAuth tokens
- Bearer tokens
- Private keys
- Access key pairs
- Credential-bearing connection strings

Allowed metadata:

- Secret provider
- Secret identifier/path
- Secret name
- Storage mechanism

Secret metadata is permitted. Secret values are not.

---

## 3. Tier-0 Rules

### 3.1 Prohibited

The system MUST NOT:

- Request secret values
- Persist secret values
- Render secret values into HTML or PDF
- Store secret values in logs
- Store secret values in workflow artifacts

### 3.2 Permitted

PGC may request only:

- Whether a secret is required
- Which provider will manage it
- The identifier/path
- Lifecycle ownership
- Runtime resolution intent

All secret-related questions must concern management intent only.

---

## 4. Detection and Enforcement Model

### 4.1 Dual Gate Architecture (Mandatory)

Secrets screening shall occur at:

1. **HTTP Ingress Boundary**
2. **Orchestrator Tier-0 Governance Boundary**

Both gates must invoke the same canonical detector implementation.

---

## 5. Canonical Secret Detector

There shall be one authoritative detector module:

`combine-config/governance/secrets/detector.v1`

This module must be versioned and auditable.

### 5.1 Detection Hierarchy

**Primary trigger:**

- High entropy string detection (threshold >= configured value)
- Minimum length threshold
- Character distribution analysis

**Secondary accelerators:**

- Known credential patterns (AWS AKIA, PEM headers, etc.)

No vendor-enumeration reliance.

---

## 6. HTTP Ingress Gate

### 6.1 Execution

At HTTP ingress:

- Run canonical detector on raw request body
- Execute before any logging persistence

### 6.2 If Secret Detected

System must:

- Reject request (HTTP 422)
- Not create workflow instance
- Not persist request body
- Log only redacted event: `[REDACTED_SECRET_DETECTED]`

Permitted log metadata:

- Request ID
- Detector version
- Entropy score
- Detection classification

Secret value must never be written.

---

## 7. Orchestrator Tier-0 Gate

### 7.1 Execution Points

Detector must run on:

- PGC user answers
- Generated artifacts before stabilization
- Render inputs (detail_html, pdf)
- Replay or connector payloads

### 7.2 If Secret Detected

System must:

- Issue HARD_STOP
- Abort node execution
- Roll back transaction
- Prevent persistence
- Emit structured governance event
- Allow resumable correction

---

## 8. HARD_STOP Definition

HARD_STOP results in:

- Immediate termination of current workflow node
- Transaction rollback
- No stabilization
- No rendering
- No artifact persistence
- Redacted logging only
- Structured error response
- No human intervention required

---

## 9. Logging Precedence (ADR-010 Alignment)

If a conflict exists between logging requirements and secret protection:

**Tier-0 Secret Protection takes precedence.**

Secret-bearing payloads must be redacted prior to persistence.

Logging may record:

- Detection metadata
- Governance event
- Redacted placeholder

Logging may not store secret material.

---

## 10. Tier-0 Injection Requirement (PGC)

All PGC task and QA prompts must include the injected clause defined in Section 11.

Clause must be injected automatically and be non-removable.

---

## 11. Canonical Injected Clauses

Location:

- `combine-config/governance/tier0/pgc_secrets_clause.v1.txt`
- `combine-config/governance/tier0/pgc_secrets_clause_qa.v1.txt`

### 11.1 PGC Task Clause (Exact Text)

```
[[TIER0_PGC_SECRETS_CLAUSE_V1]]

Tier-0 Governance Rule: Secrets Handling

You MUST NOT request, collect, validate, echo, or persist any credential or secret value.

A secret includes (but is not limited to):
- API keys
- Passwords
- OAuth tokens
- Bearer tokens
- Private keys
- Access key pairs
- Credential-bearing connection strings

You MAY ask how secrets should be managed, including:
- Whether a secret is required
- Which provider will manage it
- The secret identifier or storage path
- Whether runtime resolution should occur

All secret-related questions must concern management intent only.

If a user provides a secret value:
- Do not repeat it
- Do not store it
- Instruct the user to use a supported secret manager
- Continue safely without persisting the value
```

### 11.2 PGC QA Clause (Exact Text)

```
[[TIER0_PGC_SECRETS_CLAUSE_V1]]

Tier-0 Governance Rule: Secrets Validation

You MUST verify that:
- No PGC question requests a secret value
- No artifact contains credential material
- No secret fragments appear in output

If secret solicitation is detected:
- Mark as HARD_STOP violation
- Explain violation clearly

If secret material appears in user input:
- Mark as invalid
- Require use of secret manager
```

---

## 12. Authority

This policy:

- Cannot be overridden by package.yaml
- Cannot be modified via Workbench triad editing
- Is governed as Tier-0 Combine infrastructure

---

_End of GOV-SEC-T0-002_


---

## POL-ADR-EXEC-001: ADR Execution Authorization Process

# POL-ADR-EXEC-001: ADR Execution Authorization Process

| | |
|---|---|
| **Status** | Accepted |
| **Effective Date** | 2026-01-06 |
| **Decision Owner** | Product Owner |
| **Applies To** | All human and AI contributors executing work governed by ADRs |
| **Related Artifacts** | ADRs, POL-WS-001 |

---

## 1. Purpose

This policy defines the mandatory process for authorizing and executing work derived from an accepted Architectural Decision Record (ADR).

It exists to ensure that:

- Architectural decisions are not implemented prematurely
- Execution intent is explicit, reviewed, and authorized
- AI agents do not confuse momentum with permission
- Execution is controlled, auditable, and reversible

---

## 2. Key Principle

**Acceptance of an ADR does not authorize execution.**

Execution is permitted only after completing the authorization steps defined in this policy.

---

## 3. Architectural Status vs Execution State

ADR architectural status and execution state are distinct and independent.

### 3.1 Architectural Status (unchanged)

Architectural status reflects design law only:

- Draft
- Accepted
- Deprecated
- Superseded

### 3.2 Execution State (new)

Execution state governs whether work may proceed:

- `null` — No execution authorized
- `authorized` — Implementation planning complete; Work Statements may be prepared
- `active` — Work Statement accepted; execution permitted
- `complete` — All authorized execution finished

Execution state transitions MUST be explicit and MUST be recorded in the ADR document or a governing system of record.

---

## 4. Trigger

**Trigger:**
A human operator explicitly instructs the system to begin work on a specific ADR that is already in Accepted architectural status.

Implicit triggers (e.g., "the ADR is accepted") are invalid.

---

## 5. Execution Authorization Process

### 5.1 Scope Assessment

Before beginning execution authorization, assess expected scope:

- **Single-commit scope:** One atomic change, no phasing required
- **Multi-commit scope:** Multiple changes, phasing/sequencing required

The expected scope (single-commit or multi-commit) MUST be explicitly declared in the Work Statement or Implementation Plan.

### 5.2 Single-Commit Path

For single-commit work:

1. Work Statement Preparation (per POL-WS-001)
2. Work Statement Review and Acceptance
3. Execution

No Implementation Plan required.

### 5.3 Multi-Commit Path

For multi-commit work:

1. Implementation Plan Draft
2. Implementation Plan Review and Acceptance
3. Authorization to Prepare Execution Artifacts (`execution_state` = `authorized`)
4. Work Statement(s) Preparation
5. Work Statement Review and Acceptance
6. Execution

### 5.4 Scope Escalation

If, during execution, it becomes apparent that the remaining work cannot be completed in a single commit:

1. STOP execution
2. Draft Implementation Plan for remaining work
3. Resume multi-commit path from Step 2

---
## 6. Deviation Handling

**Minor deviations** (within approved scope and intent):

- Require amendment of the affected Work Statement
- Require re-review and re-acceptance of that Work Statement

**Scope or intent changes:**

- Require stopping execution
- Require returning to Implementation Plan review (Step 2)

Unauthorized deviation is prohibited.

---

## 7. Prohibited Actions

The following actions are prohibited:

- Treating ADR acceptance as execution authorization
- Executing work without an accepted Implementation Plan
- Executing work without an accepted Work Statement
- Skipping or collapsing authorization steps
- Performing exploratory, convenience, or refactor work under execution authority

---

## 8. Enforcement

- Work performed outside this process is unauthorized
- Unauthorized work may be rejected regardless of quality
- AI agents MUST refuse execution if any required authorization is missing or ambiguous

---

## 9. Inclusion in AI Bootstrap

AI bootstrap instructions MUST include:

- Recognition of ADR architectural status vs execution state
- Obligation to request an Implementation Plan
- Obligation to request a Work Statement
- Refusal to execute without explicit acceptance signals

---

## 10. Completion

When all authorized Work Statements have been executed and verified:

- The ADR `execution_state` is set to `complete`
- No further work may occur without re-triggering this process

---

*End of Policy*

---

## POL-ARCH-001: Architectural Integrity Standard

# POL-ARCH-001: Architectural Integrity Standard

| | |
|---|---|
| **Status** | Active |
| **Effective Date** | 2026-03-06 |
| **Applies To** | All human and AI contributors modifying architecture, APIs, workflows, or infrastructure in The Combine |
| **Related Artifacts** | CLAUDE.md (Execution Constraints, Non-Negotiables, Execution Model), ADR-009, ADR-010, ADR-040, ADR-049 |

---

## 1. Purpose

This policy formalizes the architectural integrity rules that govern system boundaries, schema authority, workflow composition, API contracts, and traceability in The Combine. These rules ensure the system remains coherent, auditable, and mechanically verifiable.

---

## 2. Separation of Concerns

- **Documents are memory, not LLM context.** The system persists state in documents, not conversation transcripts.
- **Workers are anonymous, interchangeable components.** No execution depends on a specific worker identity.
- **LLMs handle creative/synthesis tasks; code handles mechanical tasks** (storage, validation, rendering, routing).
- **UI, domain, and infrastructure layers MUST remain distinct.** No layer may assume or embed the responsibilities of another.

*Source: CLAUDE.md "Execution Model (Concrete)", ADR-040 (Stateless LLM Execution Invariant)*

---

## 3. Stateless LLM Execution (ADR-040)

Each LLM invocation MUST receive:
- The canonical role prompt
- The task- or node-specific prompt
- The current user input (single turn only)
- Structured `context_state` (governed data derived from prior turns)

Each LLM invocation MUST NOT receive:
- Prior conversation history (even from same execution)
- Previous assistant responses
- Accumulated user messages
- Raw conversational transcripts

Continuity comes from structured state, not transcripts. `node_history` is for audit; `context_state` is for memory. Keep them separate.

*Source: CLAUDE.md "Stateless LLM Execution Invariant (ADR-040)"*

---

## 4. Schema Authority

- All document structures MUST originate from governed schemas in `seed/schemas/`.
- Prompts live in `seed/prompts/` -- they are governed inputs, not documentation.
- Prompt changes require: explicit intent, version bump, re-certification, manifest regeneration.
- Prompts are versioned, certified, hashed (`seed/manifest.json`), and logged on every LLM execution.

*Source: CLAUDE.md "Seed Governance"*

---

## 5. Workflow Integrity (ADR-049)

- Every DCW (Document Creation Workflow) MUST be explicitly composed of gates, passes, and mechanical operations.
- "Generate" is deprecated as a step abstraction -- it hides too much.
- DCWs are first-class workflows, not opaque steps inside POWs.
- Handlers own input assembly, prompt selection, LLM invocation, and output persistence.
- Handlers do NOT infer missing inputs -- they fail explicitly.
- Retry/circuit-breaker logic belongs to the engine, not the plan.

### Composition Patterns

- **Full pattern:** PGC Gate (LLM -> UI -> MECH) -> Generation (LLM) -> QA Gate (LLM + remediation)
- **QA-only pattern:** Generation (LLM) -> QA Gate (LLM + remediation)
- **Gate Profile pattern:** Multi-pass classification with internals

*Source: CLAUDE.md "No Black Boxes (ADR-049)", "Execution Model (Concrete)"*

---

## 6. API & Interface Contracts

- Routes are API contracts -- no silent route removal (deprecation protocol required).
- All API routes live under `/api/v1/`.
- Kebab-case in URL paths, snake_case in JSON fields.
- Command routes are async, idempotent, and return `task_id`.

*Source: Established API conventions, CLAUDE.md "Repository Structure"*

---

## 7. Traceability

- All state changes MUST be explicit and traceable (ADR-009).
- LLM execution MUST be logged with inputs, outputs, tokens, and timing (ADR-010).
- Every execution is replayable via `/api/admin/llm-runs/{id}/replay`.

*Source: CLAUDE.md "Execution Model (Concrete)", ADR-009, ADR-010*

---

## 8. Git & Deployment Integrity

- Session summaries are immutable logs -- never edit after writing.
- ADRs are append-only governance records.
- Docker copies only `app/`, `alembic/`, `alembic.ini` (explicit, not blanket).
- Anything in `ops/` is operator-facing and never in the runtime container.

*Source: CLAUDE.md "Non-Negotiables", "Repository Structure", "Knowledge Layers"*

---

## 9. Governance Boundary

This policy formalizes rules already enforced through CLAUDE.md, ADR-009, ADR-010, ADR-040, ADR-049, and established layer conventions. It does not introduce new rules or enforcement mechanisms. Mechanical enforcement is out of scope and deferred to future quality gate work.

---

*End of Policy*


---

## POL-CODE-001: Code Construction Standard

# POL-CODE-001: Code Construction Standard

| | |
|---|---|
| **Status** | Active |
| **Effective Date** | 2026-03-06 |
| **Applies To** | All human and AI contributors writing or modifying code in The Combine |
| **Related Artifacts** | CLAUDE.md (Reuse-First Rule, Execution Constraints), ADR-045 (System Ontology), ADR-057 (Ontology) |

---

## 1. Purpose

This policy formalizes the code construction rules that govern how code is written, extended, and maintained in The Combine. These rules ensure consistency, reuse, testability, and terminological precision across the codebase.

---

## 2. Reuse-First Rule

Before creating anything new (file, module, schema, service, prompt):

1. **Search** the codebase and existing docs/ADRs.
2. **Prefer** extending or refactoring over creating.
3. **Create new** only when reuse is not viable.

### Constraints

- If you create something new, you MUST be able to justify why reuse was not appropriate.
- Creating something new when a suitable existing artifact exists is a defect.

*Source: CLAUDE.md "Reuse-First Rule"*

---

## 3. Complexity Management

### CRAP Score Thresholds

- Functions exceeding CRAP score > 30 are flagged as critical and require remediation.
- Remediation path: decompose into focused sub-methods (cyclomatic complexity reduction), add test coverage (coverage increase), or both.

### Structural Rules

- No god functions: business logic MUST be modular and testable.
- Mechanical/deterministic checks are preferred over LLM-based validation wherever possible.
- Make every change as simple as possible. Find root causes, not symptoms.
- No temporary fixes. No "we'll clean this up later" without a tech debt entry.
- Changes should only touch what is necessary.

*Source: WP-CRAP-001/002 practices, CLAUDE.md "Planning Discipline - Simplicity First"*

---

## 4. Ontology Compliance

Per ADR-045 and ADR-057, terminological precision is mandatory:

- **One meaning per term, system-wide.** No synonyms in code.
- **Registration before use:** Check the ontology before naming columns, fields, classes, or parameters.
- **Use registered terms:** Code identifiers MUST use registered terms, not alternatives.
- Prose documentation may use natural language; code MUST NOT.

### ADR-045 Taxonomy

| Category | Examples |
|----------|----------|
| **Primitives** | Prompt Fragment, Schema |
| **Composites** | Role, Task, DCW, POW |
| **Ontological terms** | Interaction Pass |

Core principle: Prompt Fragments shape behavior; Schemas define acceptability; Interaction Passes bind and execute both.

*Source: CLAUDE.md "ADR-045 Taxonomy Reference", ADR-057*

---

## 5. Code Style

- **Explicit dependencies:** All imports and dependencies MUST be declared.
- **Readability over cleverness:** Favor clarity and maintainability.
- **No silent failures:** Errors MUST be surfaced, not swallowed.
- **No black boxes:** If a step does something non-trivial, it must show its passes (ADR-049). "Generate" is deprecated as a step abstraction.

*Source: CLAUDE.md "Execution Constraints" (ADR-049), "Non-Negotiables"*

---

## 6. Prompt and Seed Governance

Prompts are governed inputs, not documentation:

- Prompts live in `seed/prompts/` and are versioned, certified, hashed, and logged.
- Do NOT merge role logic into task prompts.
- Do NOT edit prompts without a version bump.
- Prompt changes require: explicit intent, version bump, re-certification, manifest regeneration.

*Source: CLAUDE.md "Seed Governance", "Non-Negotiables"*

---

## 7. Governance Boundary

This policy formalizes rules already enforced through CLAUDE.md, ADR-045, ADR-049, ADR-057, and established CRAP score audit practices. It does not introduce new rules or enforcement mechanisms. Mechanical enforcement is out of scope and deferred to future quality gate work.

---

*End of Policy*


---

## POL-QA-001: Testing & Verification Standard

# POL-QA-001: Testing & Verification Standard

| | |
|---|---|
| **Status** | Active |
| **Effective Date** | 2026-03-06 |
| **Applies To** | All human and AI contributors executing governed work in The Combine |
| **Related Artifacts** | CLAUDE.md (Bug-First Testing Rule, Testing Strategy), ADR-010, POL-WS-001 |

---

## 1. Purpose

This policy formalizes the testing and verification rules that govern all implementation work in The Combine. These rules ensure that defects are understood before modification, fixes are causally linked to observed failures, and regressions are prevented by construction.

---

## 2. Bug-First Testing Rule

When a runtime error, exception, or incorrect behavior is observed, the following sequence **MUST** be followed:

1. **Reproduce First** -- A failing automated test MUST be written that reproduces the observed behavior. The test must fail for the same reason the runtime behavior failed.
2. **Verify Failure** -- The test MUST be executed and verified to fail before any code changes are made.
3. **Fix the Code** -- Only after the failure is verified may code be modified to correct the issue.
4. **Verify Resolution** -- The test MUST pass after the fix. No fix is considered complete unless the reproducing test passes.

### Constraints

- Tests MUST NOT be written after the fix to prove correctness.
- Code MUST NOT be changed before a reproducing test exists.
- If a bug cannot be reliably reproduced in a test, the issue MUST be escalated rather than patched heuristically.
- Vibe-based fixes are explicitly disallowed.

This rule applies to all runtime defects including: exceptions, incorrect outputs, state corruption, and boundary condition failures.

*Source: CLAUDE.md "Bug-First Testing Rule (Mandatory)"*

---

## 3. Money Tests

Bug fixes MUST include a "money test" that reproduces the exact root-cause scenario:

- The money test MUST fail before the fix is applied.
- The money test MUST pass after the fix is applied.
- The money test serves as the regression guard for that specific defect.

*Source: Established session practice (WS-RING0-001, WP-CRAP-001/002)*

---

## 4. Testing Tiers

All tests operate within the following tier structure:

| Tier | Scope | Dependencies | Purpose |
|------|-------|-------------|---------|
| Tier-1 | In-memory repositories, no DB | None | Pure business logic verification (fast unit tests) |
| Tier-2 | Spy repositories | None | Call contract verification (wiring tests) |
| Tier-3 | Real PostgreSQL | Test DB infrastructure | Integration verification (**deferred**) |

### Tier Constraints

- Tier-3 tests are not currently required. Infrastructure does not yet exist.
- Do NOT suggest SQLite as a substitute for PostgreSQL testing.
- Tier-1 and Tier-2 tests MUST pass before any work is considered complete.

*Source: CLAUDE.md "Testing Strategy (Current)"*

---

## 5. Verification Before Completion

- Work is not complete until all tests pass and acceptance criteria are verified.
- Never mark a task complete without proving it works.
- The standard is "does Tier 0 pass?" -- not "does this look right?"
- Tier 0 verification (`ops/scripts/tier0.sh`) is the mandatory baseline for all work.
- When executing a Work Statement, Tier 0 MUST be invoked in WS mode with `--scope` derived from the WS's `allowed_paths[]`.

*Source: CLAUDE.md "Planning Discipline - Verification Before Done", POL-WS-001 Section 6*

---

## 6. Regression Protection

- Fixes MUST NOT reduce existing test coverage.
- Tests MUST be deterministic -- they MUST NOT depend on external services or non-deterministic inputs.
- Every autonomous bug fix MUST include the test name and root cause in its report.

*Source: CLAUDE.md "Bug-First Testing Rule", "Autonomous Bug Fixing"*

---

## 7. Governance Boundary

This policy formalizes rules already enforced through CLAUDE.md, ADR-010, and established session practices. It does not introduce new rules or enforcement mechanisms. Mechanical enforcement is out of scope and deferred to future quality gate work.

---

*End of Policy*


---

## POL-WS-001: Standard Work Statements

# POL-WS-001: Standard Work Statements

| | |
|---|---|
| **Status** | Active |
| **Effective Date** | 2026-01-06 |
| **Applies To** | All human and AI contributors executing governed work in The Combine |
| **Related Artifacts** | ADRs, Governance Policies, Schemas, Work Statements |

---

## 1. Purpose

Standard Work Statements (WS) define how governed work is executed repeatedly, correctly, and without drift.

They translate architectural decisions (ADRs) and governance policies into explicit, mechanical execution procedures suitable for both human contributors and AI agents.

Work Statements exist to:

- Prevent interpretive or "creative" compliance
- Enable safe and repeatable delegation to AI
- Preserve architectural integrity during change
- Ensure auditability and consistent outcomes

---

## 2. When a Work Statement Is Required

A Work Statement **MUST** be used when any of the following apply:

- An ADR or policy is being applied to existing code or systems
- An ADR or policy is being applied to multiple surfaces or instances
- Execution is delegated to an AI agent
- Deviation would introduce architectural drift
- The work establishes or propagates a new architectural pattern

A Work Statement **MAY** be used for:

- Complex one-off changes
- High-risk or irreversible work
- Coordination across multiple components

A Work Statement is **NOT** required for:

- Pure analysis or exploration
- Drafting ADRs or policies
- Non-durable discussion

---

## 3. Relationship to ADRs and Policies

- **ADRs** define *what must be true*
- **Policies** define *how governance operates*
- **Work Statements** define *how work is executed*

Work Statements:

- **MUST** reference the governing ADRs, policies, and schemas
- **MUST NOT** reinterpret, extend, or override ADRs
- **MUST NOT** introduce new architectural decisions

If a governing ADR or policy is unclear, contradictory, or incomplete:

1. **STOP**
2. Escalate for clarification
3. Do not proceed until corrected

---

## 4. Required Structure of a Work Statement

Every Work Statement **MUST** include the following sections:

### Purpose
What work is being executed and why

### Governing References
ADRs, policies, schemas, and standards that control the work

### Verification Mode
`A` (all criteria verified) or `B` (declared exceptions)

### Allowed Paths
A list of file-path prefixes that define the containment boundary for this Work Statement. These prefixes are passed to Tier 0 as `--scope` arguments during WS execution (see Section 6).

Example:
```
## Allowed Paths
- ops/scripts/
- tests/infrastructure/
- combine-config/policies/
- CLAUDE.md
```

### Scope
Explicit statement of what is included and excluded

### Preconditions
Required artifacts, system state, approvals, or inputs

### Procedure
Step-by-step execution instructions

- Written to be followed mechanically
- No assumed knowledge
- No skipped or implicit steps

### Prohibited Actions
Actions that must not be taken (see Section 5)

### Verification Checklist
Objective checks to confirm correct execution

### Definition of Done
Conditions under which the work is considered complete

---

## 5. Prohibited Actions (Authoritative)

A Work Statement **MUST** explicitly list known prohibited actions relevant to the task.

In addition, **all prohibitions and constraints defined in governing ADRs, policies, schemas, and architectural rules are implicitly in force**, whether or not they are restated in the Work Statement.

Lack of explicit prohibition in a Work Statement does **not** grant permission to:

- Violate ADRs
- Violate governance policies
- Breach architectural boundaries
- Circumvent quality gates
- Introduce implicit behavior, shortcuts, or assumptions

If a contributor believes an action is permitted due to omission:

1. **STOP**
2. Escalate for clarification
3. Do not proceed on assumption

---

## 6. Execution Rules

### Do No Harm Audit (Mandatory Pre-Execution)

Before executing any Work Statement, the executor **MUST** verify that the WS's assumptions about the codebase match reality.

1. Identify assumptions the WS makes about existing code, schemas, APIs, configuration, or infrastructure
2. Check each assumption against the actual codebase state
3. If any assumption is materially wrong, **STOP** and report mismatches before touching anything
4. Do not execute a WS whose assumptions do not match the terrain

This audit prevents executing well-structured Work Statements against a codebase that has diverged from what the WS author believed existed. A correct procedure applied to a wrong assumption produces wrong output.

### General Rules

- Work Statements are executed **exactly as written**
- Steps must not be skipped, reordered, merged, optimized, or reinterpreted

If a step cannot be completed as written:

1. **STOP**
2. Escalate for revision or clarification

### Tier 0 Verification in WS Mode

When executing a Work Statement, Tier 0 **MUST** be invoked in WS mode with `--scope` prefixes derived from the Work Statement's `allowed_paths[]` field:

```bash
ops/scripts/tier0.sh --ws --scope <each allowed_paths prefix>
```

If Tier 0 is run in WS mode without `--scope`, it will **FAIL by design**. This prevents "false green" runs where scope was never validated.

### AI-Specific Rules

AI agents:

- Must treat Work Statements as authoritative instructions
- Must not infer missing steps
- Must not generalize beyond stated scope
- Must refuse execution if a required Work Statement is missing

---

## 7. Modification and Versioning

Work Statements are versioned artifacts.

Changes require:

- Explicit revision
- Documented rationale

Silent or informal edits are **prohibited**.

Superseded Work Statements must be clearly marked as such.

---

## 8. Acceptance and Closure

A Work Statement is considered complete only when:

- All procedural steps are executed
- All verification checklist items pass
- The Definition of Done is satisfied
- The outcome conforms to all governing ADRs and policies

Partial completion is **not acceptable** unless explicitly defined in the Work Statement.

---

## 9. Enforcement

Failure to use or comply with a required Work Statement constitutes:

- A governance violation
- Grounds for rejection of the work output

All contributors—human and AI—are held to the same standard.

---

## 10. Inclusion in AI Bootstrap

This policy is a **mandatory reference** in all AI bootstrap prompts.

AI agents must be instructed to:

- Request a Work Statement when required
- Refuse execution in its absence
- Halt execution upon ambiguity, contradiction, or missing governance

---

*End of Policy*


---

# CI-001 — Concierge Intake: Memory Stream Application

## Project Summary

The user wants to build Memory Stream, a natural journaling application that captures thoughts via voice or text input and automatically extracts structured data while preserving the original input. The system bridges spontaneous thought capture with organized, searchable memory storage without feeling like a database.

Memory Stream exists to let people capture thoughts in the moment of work — by voice or text — and turn them into organized, retrievable memory without losing the original thought. It is designed to feel like a natural journal, not a database, preserving what the user said while quietly extracting the projects, entities, issues, ideas, and next actions behind it.

## Project Type

produce_output

User is describing building a new application (Memory Stream) that will be a deliverable product with specific functionality for thought capture and organization.

## Intake Outcome

qualified

Request clearly defines a specific application with well-articulated core functionality and user experience goals. The concept is concrete enough to begin discovery and technical planning.

Proceed to Discovery phase to define technical architecture, platform requirements, and detailed feature specifications for Memory Stream.


---

# PD-001 — Memory Stream Application

## Preliminary Summary

Memory Stream addresses the gap between spontaneous thought capture and organized information retrieval. Users need to quickly capture thoughts via voice or text during work moments, then later find and use that information without the friction of manual organization. The challenge is extracting structured data (projects, entities, issues, ideas, next actions) while preserving the original thought and maintaining a journal-like user experience rather than a database interface.

Native iOS application with local-first data storage, hybrid AI processing (local models for privacy-sensitive operations, selective cloud API usage for complex analysis), and background extraction pipeline that maintains separation between original input preservation and structured data derivation.

iOS app with three primary components: (1) Input capture layer supporting voice-to-text and direct text entry, (2) Background AI processing pipeline using hybrid local/cloud analysis to extract structured entities, and (3) Dual-interface data layer that maintains original entries while building searchable structured indexes. Core Data for local storage with potential iCloud sync for backup.

## Project Name

Memory Stream Application

## Unknowns

| ID | Question | Why It Matters | Impact If Unresolved |
| --- | --- | --- | --- |
| UNK-1 | How should extracted structured data be presented back to users while maintaining the journal-like experience? | The core value proposition depends on making organized data accessible without breaking the natural journaling feel. | Risk of creating a database-like interface that contradicts the fundamental user experience requirement. |
| UNK-2 | What are the specific performance requirements for voice-to-text conversion and AI processing latency? | User experience for spontaneous thought capture depends on responsive processing, especially for voice input. | May select AI processing approach that creates unacceptable delays in the core capture workflow. |
| UNK-3 | Does Memory Stream need to integrate with existing systems or external services? | Integration requirements would significantly affect architecture complexity and data flow design. | Architecture may not accommodate necessary integrations, requiring costly redesign. |
| UNK-4 | Must Memory Stream function offline or with intermittent connectivity? | Offline requirements fundamentally impact data synchronization architecture and local processing capabilities. | May design cloud-dependent architecture that fails when connectivity is poor. |

## Assumptions

| ID | Assumption | Confidence | Validation |
| --- | --- | --- | --- |
| ASM-1 | Enhanced privacy requirements allow selective use of cloud AI APIs with appropriate data handling | medium | Review specific privacy compliance requirements and cloud AI vendor data handling policies |
| ASM-2 | Single-user scale allows for local iOS storage (Core Data/SQLite) without requiring backend infrastructure | high | Validate storage volume estimates against iOS local storage capabilities |
| ASM-3 | Hybrid AI processing means using local models for basic extraction and cloud APIs for complex analysis when privacy permits | medium | Define specific criteria for when each processing approach is used |

## Known Constraints

| ID | Constraint | Type |
| --- | --- | --- |
| CNS-1 | iOS mobile platform only | technical |
| CNS-2 | Single-user application scope | technical |
| CNS-3 | Enhanced privacy level - limited cloud processing acceptable | security |
| CNS-4 | Public consumer application target | other |
| CNS-5 | Hybrid AI processing approach required | technical |

## MVP Guardrails

| ID | Guardrail |
| --- | --- |
| GRD-1 | Must support both voice and text input methods |
| GRD-2 | Must preserve original user input without alteration |
| GRD-3 | Must feel like a natural journal, not a database |
| GRD-4 | Must quietly extract structured data in background without user effort |

## Early Decision Points

### Voice processing architecture

EDP-1

Determines whether voice-to-text happens on-device, via cloud APIs, or hybrid approach, which affects privacy compliance and performance characteristics

- iOS Speech Framework only
- Cloud speech APIs only
- Hybrid with fallback
- Third-party SDK integration

iOS Speech Framework primary with cloud fallback for accuracy when privacy permits

### AI model selection for entity extraction

EDP-2

Choice between local models vs cloud APIs affects app size, processing speed, privacy compliance, and ongoing costs

- Local Core ML models only
- Cloud APIs (OpenAI/Google) only
- Hybrid with privacy-based routing
- Custom trained models

Hybrid approach with local models for basic extraction, cloud APIs for complex analysis when user consents

## Stakeholder Questions

| ID | Question | Directed To | Blocking |
| --- | --- | --- | --- |
| STQ-1 | What specific compliance or regulatory requirements apply to the enhanced privacy level? | legal | No |
| STQ-2 | Are there preferred cloud AI vendors or any vendor restrictions for the hybrid processing approach? | tech_lead | No |
| STQ-3 | What are the target app store approval timeline and any App Store review considerations for AI processing features? | product_owner | No |

## Recommendations for PM

| ID | Recommendation |
| --- | --- |
| RPM-1 | Conduct user interviews focused on current journaling and note-taking workflows to validate the journal-vs-database experience assumption |
| RPM-2 | Create technical spike to evaluate iOS Speech Framework accuracy and performance against user expectations for voice capture |
| RPM-3 | Define privacy compliance requirements early to establish clear boundaries for hybrid AI processing decisions |
| RPM-4 | Prototype the structured data presentation interface to validate that extracted entities can be surfaced without breaking the journal experience |


---

# IP-001 — Memory Stream Application: Implementation Plan

## Plan Summary

Deliver Memory Stream MVP as a native iOS application that enables spontaneous thought capture via voice/text with background AI-powered structured data extraction, maintaining a journal-like experience while making information findable through inline tags and search filters.

A functional iOS app supporting voice and text input capture, local speech-to-text processing via Siri, background entity extraction when connected, inline tag presentation of extracted data, and enhanced search filtering - all while preserving original entries and maintaining journal experience.

- iOS mobile platform only
- Single-user application scope
- Enhanced privacy level with limited cloud processing
- Must preserve original user input without alteration
- Must feel like natural journal, not database interface
- Hybrid AI processing approach required
- Offline voice capture via Siri, cloud AI processing when connected

Voice capture foundation enables core user workflow, followed by AI processing pipeline to extract value, then presentation layer to surface insights. This sequence allows early user validation of capture experience while building toward full value proposition.

- iOS Speech Framework and Siri integration sufficient for offline voice capture
- Core Data adequate for local storage without backend infrastructure
- Hybrid AI approach balances privacy requirements with extraction quality
- Inline tags and search filters maintain journal experience while surfacing structured data

- Multi-user functionality or sharing capabilities
- Advanced export features
- iCloud sync and backup
- Custom entity type definitions
- Integration with external systems

## Work Package Candidates

### Voice and Text Input Capture Foundation

WPC-001

Core user interaction layer enabling spontaneous thought capture through both voice and text modalities, essential for primary user workflow.

- iOS Speech Framework integration for voice-to-text conversion
- Siri integration for offline voice interpretation
- Direct text input interface
- Input validation and basic error handling
- Local storage of raw captured input
- Basic journal-style entry display

- AI processing or entity extraction
- Advanced search functionality
- Data export capabilities
- Cloud synchronization
- Advanced text formatting or rich media

- User can capture voice input that converts to text using iOS Speech Framework
- User can capture direct text input
- Siri integration functions offline for voice interpretation
- All input is stored locally and preserved without alteration
- Basic journal interface displays captured entries chronologically
- Input validation prevents data corruption

Foundation for all other functionality. Consider technical spike for Siri integration complexity assessment.

### Background AI Processing Pipeline

WPC-002

Extracts structured data from captured input to enable findability and organization without user effort, core to value proposition.

- Hybrid AI processing architecture (local models + cloud APIs)
- Entity extraction for projects, people, issues, ideas, next actions
- Background processing queue for cloud AI when connected
- Privacy-compliant cloud API integration
- Structured data storage linked to original entries
- Processing status tracking and error handling

- User-defined entity types
- Real-time processing requirements
- Advanced NLP beyond basic entity extraction
- Integration with external AI services beyond standard APIs
- Manual entity editing or correction interfaces

| Depends On | External Dep | Type | Notes |
| --- | --- | --- | --- |
| WPC-001 | — | must_complete_first | Requires captured input data to process |

- Background processing extracts entities from text input when connected
- Local Core ML models handle basic extraction for privacy-sensitive content
- Cloud API integration processes complex analysis with user consent
- Extracted entities stored with linkage to original entries
- Processing queue handles offline/online state transitions
- Error handling prevents processing failures from affecting user experience

Hybrid approach complexity may require architecture validation during TA phase.

### Structured Data Presentation and Search

WPC-003

Surfaces extracted structured data through inline tags and enhanced search while maintaining journal experience, completing core value delivery.

- Inline tag display within journal entries
- Enhanced search with entity-based filters
- Tag-based navigation and discovery
- Search result highlighting and context
- Filter persistence and search history
- Integration with journal display from WPC-001

- Separate structured data views or dashboards
- Advanced analytics or reporting
- Data export functionality
- Collapsible sidebar panels
- External search integration

| Depends On | External Dep | Type | Notes |
| --- | --- | --- | --- |
| WPC-001 | — | must_complete_first | Requires journal interface foundation |
| WPC-002 | — | can_start_after | Enhanced search requires extracted entity data |

- Extracted entities display as inline tags within journal entries
- Search interface includes entity-based filters
- Users can discover related entries through tag navigation
- Search results maintain journal context and readability
- Tag display preserves natural journal reading experience
- Filter functionality works with both text content and extracted entities

UI complexity for maintaining journal experience while surfacing structured data may need design validation.

## Risk Summary

| Risk | Affected Candidates | Impact | Mitigation |
| --- | --- | --- | --- |
| Siri integration complexity may exceed offline voice capture requirements | ['WPC-001'] | medium | Conduct technical spike during WPC-001 to validate Siri offline capabilities and fallback to iOS Speech Framework if needed |
| Hybrid AI processing architecture complexity may impact delivery timeline and privacy compliance | ['WPC-002'] | high | Define clear privacy routing criteria early and consider phased approach starting with local-only processing |
| Inline tag presentation may compromise journal experience or readability | ['WPC-003'] | medium | Prototype tag display approaches early and validate with user testing before full implementation |
| Performance degradation from background AI processing affecting user experience | ['WPC-001', 'WPC-002'] | medium | Implement processing queue with priority management and ensure UI responsiveness is never blocked |

## Cross-Cutting Concerns

- Privacy compliance across hybrid AI processing approach
- Data consistency between original entries and extracted entities
- Performance optimization for background processing without UI impact
- iOS App Store review considerations for AI processing features
- Local storage capacity management for growing journal content
- Offline/online state handling across all components

## Architecture Recommendations

- Evaluate Core ML model options for local entity extraction to define hybrid processing boundaries
- Design data schema supporting both original entry preservation and extracted entity linkage
- Assess iOS Speech Framework vs Siri integration trade-offs for offline voice capture
- Define cloud AI API integration patterns that maintain privacy compliance
- Consider Core Data performance implications for concurrent read/write during background processing

## Open Questions

| Question | Why It Matters | Owner | Status |
| --- | --- | --- | --- |
| What are the specific performance targets for voice-to-text latency and background processing? | Performance requirements determine processing architecture choices and user experience quality | Product Owner | — |
| Which cloud AI vendors are preferred or restricted for hybrid processing approach? | Vendor selection affects integration complexity, costs, and privacy compliance approach | Technical Lead | — |
| What specific privacy compliance requirements apply beyond 'enhanced privacy level'? | Detailed compliance requirements shape hybrid AI processing implementation and cloud API usage | Legal/Compliance | — |


---

# TA-001 — Memory Stream Application: Technical Architecture

## Architecture Summary

Memory Stream iOS Application Architecture

Layered architecture with hybrid processing pipeline

- Local-first data storage using Core Data with iOS framework integration
- Hybrid AI processing: iOS Speech Framework for voice-to-text, Anthropic API facade for entity extraction
- Background processing queue with offline/online state management
- Inline tag presentation within journal entries to maintain natural reading experience
- High precision entity extraction with confidence thresholds to minimize false positives

## Risks

| Risk | Impact | Mitigation | Status |
| --- | --- | --- | --- |
| iOS Speech Framework accuracy may not meet user expectations for voice capture | medium | Implement fallback to cloud speech APIs when privacy permits and accuracy is insufficient | identified |
| High precision entity extraction may miss too many valid entities | medium | Implement user feedback mechanism to adjust confidence thresholds based on usage patterns | identified |
| Background processing may drain battery or impact performance | high | Implement adaptive processing limits based on battery state and thermal conditions | identified |
| Inline tags may compromise journal reading experience | high | Design subtle tag styling and provide user controls for tag visibility | identified |
| Media references may become i | — | — | — |

## Components

### Voice Input Controller

Handles voice recording and speech-to-text conversion using iOS Speech Framework

Swift, iOS Speech Framework, AVFoundation

- src/input/voice/
- src/speech/

- Speech Recognition API
- Audio Recording Interface

- Entry Storage Manager
- Processing Queue Manager

### Text Input Controller

Manages direct text input capture and validation

Swift, UIKit

- src/input/text/
- src/validation/

- Text Input Interface

- Entry Storage Manager
- Processing Queue Manager

### Entry Storage Manager

Persists original user entries and manages Core Data operations

Swift, Core Data

- src/storage/entries/
- src/models/core/

- Entry Persistence Interface

- Media Reference Manager

### Media Reference Manager

Manages references to images, voice, and video stored in device OS apps with graceful failure handling

Swift, Photos Framework, AVFoundation

- src/media/
- src/references/

- Media Access Interface

### Processing Queue Manager

Manages background AI processing queue with offline/online state transitions

Swift, iOS Background Tasks

- src/processing/queue/
- src/background/

- Background Processing Interface

- AI Processing Engine
- Connectivity Monitor

### AI Processing Engine

Orchestrates hybrid AI processing using local models and Anthropic API facade

Swift, Core ML, URLSession

- src/ai/engine/
- src/extraction/

- Entity Extraction Interface
- Anthropic Facade API

- Local Entity Extractor
- Cloud AI Facade
- Entity Storage Manager

### Local Entity Extractor

Performs basic entity extraction using local Core ML models for privacy-sensitive content

Swift, Core ML, Natural Language Framework

- src/ai/local/
- src/models/ml/

- Local Processing Interface

### Cloud AI Facade

Provides abstracted interface to Anthropic API with fallback capability to other LLMs

Swift, URLSession, Codable

- src/ai/cloud/
- src/facade/

- Anthropic API Interface
- LLM Abstraction Interface

- Connectivity Monitor

### Entity Storage Manager

Persists extracted entities with linkage to original entries using high precision thresholds

Swift, Core Data

- src/storage/entities/
- src/models/entities/

- Entity Persistence Interface

### Journal Display Controller

Renders journal entries with inline tags maintaining natural reading experience

Swift, UIKit, SwiftUI

- src/ui/journal/
- src/display/

- Journal UI Interface

- Tag Renderer
- Entry Storage Manager

### Tag Renderer

Displays extracted entities as inline tags within journal text without compromising readability

Swift, UIKit, NSAttributedString

- src/ui/tags/
- src/rendering/

- Tag Display Interface

- Entity Storage Manager

### Search Engine

Provides enhanced search with entity-based filters across both original text and extracted data

Swift, Core Data, NSPredicate

- src/search/
- src/filters/

- Search Interface

- Entry Storage Manager
- Entity Storage Manager

### Connectivity Monitor

Tracks network connectivity state for hybrid processing decisions

Swift, Network Framework

- src/connectivity/
- src/network/

- Network State Interface

### Configuration Manager

Manages app configuration including API keys, processing thresholds, and user preferences

Swift, UserDefaults, Keychain Services

- src/config/
- src/preferences/

- Configuration Interface

## Workflows

### Voice Input Capture

User initiates voice recording

| # | Action | Component | Output |
| --- | --- | --- | --- |
| 1 | Record audio input | Voice Input Controller | Audio data |
| 2 | Convert speech to text | Voice Input Controller | Transcribed text |
| 3 | Store original entry | Entry Storage Manager | Persisted journal entry |
| 4 | Queue for AI processing | Processing Queue Manager | Processing task created |

### Background Entity Extraction

Processing queue has pending tasks and network available

| # | Action | Component | Output |
| --- | --- | --- | --- |
| 1 | Retrieve next processing task | Processing Queue Manager | Processing task |
| 2 | Route to appropriate AI processor | AI Processing Engine | Processing method selected |
| 3 | Extract entities with confidence scores | Local Entity Extractor | Entity candidates |
| 4 | Filter by high precision threshold | AI Processing Engine | Validated entities |
| 5 | Store extracted entities | Entity Storage Manager | Persisted entities |
| 6 | Mark task completed | Processing Queue Manager | Task status updated |

### Journal Display with Inline Tags

User views journal entries

| # | Action | Component | Output |
| --- | --- | --- | --- |
| 1 | Retrieve journal entries | Entry Storage Manager | Journal entries |
| 2 | Retrieve associated entities | Entity Storage Manager | Extracted entities |
| 3 | Render inline tags within text | Tag Renderer | Tagged text |
| 4 | Display journal with tags | Journal Display Controller | Rendered journal view |

### Enhanced Search

User performs search with filters

| # | Action | Component | Output |
| --- | --- | --- | --- |
| 1 | Parse search query and filters | Search Engine | Search criteria |
| 2 | Query entries and entities | Search Engine | Matching results |
| 3 | Rank by relevance | Search Engine | Sorted results |
| 4 | Render results with context | Journal Display Controller | Search results view |

## Data Models

### JournalEntry

Original user input preserved without alteration

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| id | UUID | Yes | Unique identifier |
| content | String | Yes | Original user text or transcribed speech |
| input_type | String | Yes | voice or text |
| created_at | Date | Yes | Entry creation timestamp |
| media_references | [MediaReference] | No | References to associated media files |

- One-to-many with ExtractedEntity
- One-to-many with MediaReference

### ExtractedEntity

Structured data extracted from journal entries

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| id | UUID | Yes | Unique identifier |
| entry_id | UUID | Yes | Reference to source journal entry |
| entity_type | String | Yes | project, person, issue, idea, next_action |
| value | String | Yes | Extracted entity text |
| confidence_score | Double | Yes | Extraction confidence (0.0-1.0) |
| text_range | NSRange | No | Position in original text |
| processing_method | String | Yes | local or cloud |
| created_at | Date | Yes | Extraction timestamp |

- Many-to-one with JournalEntry

### MediaReference

References to media stored in device OS apps

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| id | UUID | Yes | Unique identifier |
| entry_id | UUID | Yes | Reference to journal entry |
| media_type | String | Yes | image, voice, video |
| os_identifier | String | Yes | OS-specific media identifier |
| is_accessible | Boolean | Yes | Current accessibility status |

- Many-to-one with JournalEntry

### ProcessingTask

Background processing queue items

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| id | UUID | Yes | Unique identifier |
| entry_id | UUID | Yes | Entry to process |
| task_type | String | Yes | entity_extraction |
| status | String | Yes | pending, processing, completed, failed |
| created_at | Date | Yes | Task creation time |
| processed_at | Date | No | Processing completion time |
| error_message | String | No | Error details if failed |

- Many-to-one with JournalEntry

## API Interfaces

### Anthropic Facade API

REST

| Method | Path | Description |
| --- | --- | --- |
| POST | /extract-entities | Extract entities from text using Anthropic API |

### Speech Recognition Interface

internal

| Method | Path | Description |
| --- | --- | --- |
| CALLBACK | /speech/recognize | Process voice input to text |

## Quality Attributes

- Voice-to-text processing completes within 2 seconds
- Background AI entity extraction completes within 5 seconds
- Journal display renders entries within 500ms
- Search results return within 1 second for typical query

- API keys stored in iOS Keychain
- Local Core ML models used for privacy-sensitive content
- No user data transmitted to cloud without explicit processing consent
- Graceful failure when media references become inaccessible

- Core Data handles up to 10,000 journal entries efficiently
- Background processing queue manages up to 100 pending tasks
- Search indexing supports incremental updates

- Facade pattern enables LLM provider switching
- Clear separation between original entries and extracted data
- Modular component design supports independent testing

- Processing queue status monitoring
- Entity extraction confidence score tracking
- Network connectivity state logging
- Media reference accessibility validation


---

# WP-025 — Voice and Text Input Capture Foundation

## Overview

WP-025

Voice and Text Input Capture Foundation

Core user interaction layer enabling spontaneous thought capture through both voice and text modalities, essential for primary user workflow.

PLANNED

## Scope

- iOS Speech Framework integration for voice-to-text conversion
- Siri integration for offline voice interpretation
- Direct text input interface
- Input validation and basic error handling
- Local storage of raw captured input
- Basic journal-style entry display

1. All work statements executed and verified

## Governance

TA-001

- POL-ADR-EXEC-001

## Work Statements

| Statement ID | Order |
| --- | --- |
| WS-136 | a0 |
| WS-137 | a1 |
| WS-138 | a2 |
| WS-139 | a3 |
| WS-140 | a4 |

## Revision

2026-04-07T16:11:49.328489+00:00

system

## Lineage

- WPC-001

kept

Promoted as-is from IP candidate.

work_package_candidate

- WPC-001

kept

Promoted as-is from IP candidate.


---

### WS-136 — iOS Speech Framework Integration

## Work Statement

WS-136

iOS Speech Framework Integration

READY

a0

## Objective

Implement voice recording and speech-to-text conversion using iOS Speech Framework with proper permissions and error handling

## Verification Mode

A

## Scope

- iOS Speech Framework integration for voice-to-text conversion
- Audio recording interface implementation
- Speech recognition permissions handling
- Voice input validation and error handling

- Siri integration
- Cloud-based speech services
- Audio file storage
- Background audio processing

## Allowed Paths

- src/input/voice/
- src/speech/

## Preconditions

- iOS development environment configured
- Speech Framework permissions defined in Info.plist

## Procedure

1. Create Voice Input Controller class structure
2. Implement SFSpeechRecognizer setup with locale configuration
3. Add AVAudioEngine configuration for audio recording
4. Implement speech recognition request handling with SFSpeechAudioBufferRecognitionRequest
5. Add permission request flow for speech recognition and microphone access
6. Implement real-time speech-to-text conversion with confidence scoring
7. Add error handling for recognition failures, permission denials, and audio format issues
8. Create callback interface for transcribed text delivery
9. Implement audio session management for recording lifecycle

## Verification Criteria

1. Voice Input Controller successfully initializes SFSpeechRecognizer
2. Audio recording captures user speech input
3. Speech-to-text conversion produces transcribed text with confidence scores
4. Permission requests function correctly for speech and microphone access
5. Error handling gracefully manages recognition failures and permission denials
6. Transcribed text is delivered via callback interface within 2 seconds
7. Audio session properly manages recording start/stop lifecycle

## Definition of Done

- Voice Input Controller class implemented and tested
- Speech-to-text conversion functional with iOS Speech Framework
- All error cases handled gracefully
- Permission flows implemented and tested

## Prohibited Actions

- Do not implement cloud speech services
- Do not store audio files persistently
- Do not implement Siri integration

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-025


---

### WS-137 — Direct Text Input Interface

## Work Statement

WS-137

Direct Text Input Interface

READY

a1

## Objective

Implement direct text input capture with validation and error handling for manual journal entry

## Verification Mode

A

## Scope

- Direct text input interface implementation
- Text input validation and basic error handling
- Text input controller structure

- Rich text formatting
- Auto-completion features
- Spell checking integration
- Text templates

## Allowed Paths

- src/input/text/
- src/validation/

## Preconditions

- UIKit framework available
- Basic validation rules defined

## Procedure

1. Create Text Input Controller class structure
2. Implement UITextView-based text input interface
3. Add input validation for minimum/maximum length constraints
4. Implement basic error handling for invalid input
5. Create text sanitization for special characters and formatting
6. Add input completion callback interface
7. Implement clear/reset functionality for input fields
8. Add keyboard management for input lifecycle

## Verification Criteria

1. Text Input Controller successfully captures user text input
2. Input validation enforces length constraints and basic formatting rules
3. Error handling displays appropriate messages for invalid input
4. Text sanitization removes or handles special characters appropriately
5. Input completion callback delivers validated text
6. Clear/reset functionality properly empties input fields
7. Keyboard appears and dismisses correctly during input lifecycle

## Definition of Done

- Text Input Controller class implemented and tested
- Input validation functional with error messaging
- Text sanitization working correctly
- Keyboard management implemented

## Prohibited Actions

- Do not implement rich text formatting
- Do not add auto-completion features
- Do not integrate spell checking

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-025


---

### WS-138 — Core Data Models and Entry Storage

## Work Statement

WS-138

Core Data Models and Entry Storage

READY

a2

## Objective

Implement Core Data models for journal entries and establish entry storage management with persistence operations

## Verification Mode

A

## Scope

- Core Data model definition for journal entries
- Entry Storage Manager implementation
- Local storage of raw captured input
- Core Data persistence operations

- Entity extraction models
- Media reference storage
- Search indexing
- Data migration

## Allowed Paths

- src/storage/entries/
- src/models/core/

## Preconditions

- Core Data framework available
- JournalEntry data model requirements defined

## Procedure

1. Create Core Data model file with JournalEntry entity definition
2. Define JournalEntry fields: id (UUID), content (String), input_type (String), created_at (Date)
3. Implement Entry Storage Manager class with Core Data stack initialization
4. Add create operation for new journal entries
5. Add read operations for entry retrieval by ID and date ranges
6. Add update operation for entry modifications
7. Add delete operation for entry removal
8. Implement error handling for Core Data operations
9. Add persistent container setup and context management

## Verification Criteria

1. Core Data model successfully defines JournalEntry entity with required fields
2. Entry Storage Manager initializes Core Data stack without errors
3. Create operation successfully persists new journal entries
4. Read operations retrieve entries by ID and date ranges correctly
5. Update operation modifies existing entries and persists changes
6. Delete operation removes entries from persistent store
7. Error handling manages Core Data operation failures gracefully
8. Context management properly handles save and rollback operations

## Definition of Done

- Core Data model created with JournalEntry entity
- Entry Storage Manager class implemented with CRUD operations
- All persistence operations functional and tested
- Error handling implemented for Core Data failures

## Prohibited Actions

- Do not implement entity extraction models
- Do not add media reference storage
- Do not implement search indexing

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-025


---

### WS-139 — Basic Journal Display Implementation

## Work Statement

WS-139

Basic Journal Display Implementation

READY

a3

## Objective

Implement basic journal-style entry display with chronological listing and entry rendering

## Verification Mode

A

## Scope

- Basic journal-style entry display
- Entry listing and rendering
- Chronological display ordering

- Inline tag rendering
- Search functionality
- Entry editing interface
- Media display

## Allowed Paths

- src/ui/journal/
- src/display/

## Preconditions

- Entry Storage Manager implemented
- JournalEntry model available
- UIKit/SwiftUI framework available

## Procedure

1. Create Journal Display Controller class structure
2. Implement UITableView-based entry listing interface
3. Add entry cell design for displaying content, input type, and timestamp
4. Implement data source methods for table view population
5. Add chronological sorting (newest first) for entry display
6. Integrate with Entry Storage Manager for data retrieval
7. Implement pull-to-refresh functionality
8. Add empty state handling when no entries exist
9. Implement basic entry detail view for full content display

## Verification Criteria

1. Journal Display Controller successfully loads and displays journal entries
2. Entry listing shows content, input type, and creation timestamp
3. Entries display in chronological order with newest entries first
4. Data source properly populates table view from Entry Storage Manager
5. Pull-to-refresh updates entry list with latest data
6. Empty state displays appropriate message when no entries exist
7. Entry detail view shows full content for selected entries
8. Display renders entries within 500ms performance requirement

## Definition of Done

- Journal Display Controller implemented with table view interface
- Entry cells designed and functional
- Chronological sorting working correctly
- Integration with Entry Storage Manager complete

## Prohibited Actions

- Do not implement inline tag rendering
- Do not add search functionality
- Do not implement entry editing

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-025


---

### WS-140 — Siri Integration for Voice Interpretation

## Work Statement

WS-140

Siri Integration for Voice Interpretation

READY

a4

## Objective

Implement Siri integration for offline voice interpretation and voice command handling

## Verification Mode

A

## Scope

- Siri integration for offline voice interpretation
- Voice command recognition
- Siri shortcuts configuration

- Custom voice commands beyond journal entry
- Siri response generation
- Voice synthesis
- Complex intent handling

## Allowed Paths

- src/input/voice/
- src/speech/

## Preconditions

- Voice Input Controller implemented
- Intents framework available
- Siri permissions configured

## Procedure

1. Create Siri Intent definition for journal entry creation
2. Implement INExtension for handling Siri requests
3. Add intent handler for voice-triggered journal entries
4. Configure Siri shortcuts for journal entry commands
5. Integrate Siri intent handling with Voice Input Controller
6. Implement offline voice interpretation using SiriKit
7. Add intent response handling for success/failure states
8. Configure Info.plist entries for Siri integration
9. Test Siri voice command recognition and processing

## Verification Criteria

1. Siri Intent successfully defined for journal entry creation
2. INExtension handles Siri requests without errors
3. Intent handler processes voice-triggered journal entries correctly
4. Siri shortcuts respond to configured voice commands
5. Integration with Voice Input Controller functions properly
6. Offline voice interpretation works without network connectivity
7. Intent responses provide appropriate feedback for success/failure
8. Siri integration appears in iOS Settings and functions correctly

## Definition of Done

- Siri Intent and INExtension implemented
- Voice command recognition functional
- Integration with Voice Input Controller complete
- Offline operation verified

## Prohibited Actions

- Do not implement custom voice commands beyond journal entry
- Do not add voice synthesis capabilities
- Do not implement complex multi-step intents

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-025


---

# WP-026 — Background AI Processing Pipeline

## Overview

WP-026

Background AI Processing Pipeline

Extracts structured data from captured input to enable findability and organization without user effort, core to value proposition.

PLANNED

## Scope

- Hybrid AI processing architecture (local models + cloud APIs)
- Entity extraction for projects, people, issues, ideas, next actions
- Background processing queue for cloud AI when connected
- Privacy-compliant cloud API integration
- Structured data storage linked to original entries
- Processing status tracking and error handling

1. All work statements executed and verified

## Governance

TA-001

- POL-ADR-EXEC-001

## Work Statements

| Statement ID | Order |
| --- | --- |
| WS-141 | a0 |
| WS-142 | a1 |
| WS-143 | a2 |
| WS-144 | a3 |
| WS-145 | a4 |
| WS-146 | a5 |

## Revision

2026-04-07T16:12:53.665325+00:00

system

## Lineage

- WPC-002

kept

Promoted as-is from IP candidate.

work_package_candidate

- WPC-002

kept

Promoted as-is from IP candidate.


---

### WS-141 — Implement Processing Queue Manager and Background Task Infrastructure

## Work Statement

WS-141

Implement Processing Queue Manager and Background Task Infrastructure

READY

a0

## Objective

Establish the background processing queue system that manages AI processing tasks with offline/online state transitions

## Verification Mode

A

## Scope

- Processing Queue Manager component implementation
- Background processing queue for cloud AI when connected
- Processing status tracking and error handling
- ProcessingTask data model implementation
- Background task lifecycle management

- Actual AI processing logic
- Entity extraction algorithms
- Cloud API integration
- User interface components

## Allowed Paths

- src/processing/queue/
- src/background/
- src/models/entities/

## Preconditions

- Core Data stack configured
- iOS Background Tasks framework available

## Procedure

1. Create ProcessingTask Core Data entity with all required fields
2. Implement Processing Queue Manager class with task creation, retrieval, and status update methods
3. Implement background task registration and execution handlers
4. Add queue state management for offline/online transitions
5. Implement error handling and retry logic for failed tasks
6. Add task persistence using Core Data operations
7. Create unit tests for queue operations and state transitions

## Verification Criteria

1. ProcessingTask entity exists with id, entry_id, task_type, status, created_at, processed_at, error_message fields
2. Processing Queue Manager can create, retrieve, update, and delete processing tasks
3. Background processing executes when system resources allow
4. Queue handles up to 100 pending tasks as specified in performance requirements
5. Task status transitions correctly between pending, processing, completed, failed states
6. Error messages are captured and persisted for failed tasks
7. Unit test coverage >90% for queue operations

## Definition of Done

- Processing Queue Manager component fully implemented and tested
- Background processing infrastructure operational
- Task status tracking and error handling verified

## Prohibited Actions

- Implementing AI processing logic
- Adding cloud API calls
- Creating user interface elements
- Modifying entry storage components

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-026


---

### WS-142 — Implement Local Entity Extractor with Core ML Models

## Work Statement

WS-142

Implement Local Entity Extractor with Core ML Models

READY

a1

## Objective

Build the local entity extraction component using Core ML and iOS Natural Language Framework for privacy-compliant processing

## Verification Mode

A

## Scope

- Local Entity Extractor component implementation
- Entity extraction for projects, people, issues, ideas, next actions
- Local Core ML model integration
- Privacy-compliant local processing
- Confidence scoring for extracted entities

- Cloud API integration
- Background queue management
- Entity storage operations
- User interface components

## Allowed Paths

- src/ai/local/
- src/models/ml/
- src/extraction/

## Preconditions

- iOS Natural Language Framework available
- Core ML framework available
- Entity type definitions established

## Procedure

1. Create Local Entity Extractor class with entity extraction interface
2. Implement Core ML model loading and initialization
3. Integrate iOS Natural Language Framework for text processing
4. Implement entity extraction logic for each entity type (project, person, issue, idea, next_action)
5. Add confidence score calculation for extracted entities
6. Implement text range detection for entity positions
7. Create unit tests for entity extraction accuracy and performance
8. Add error handling for model loading failures

## Verification Criteria

1. Local Entity Extractor extracts entities for all 5 specified types
2. Confidence scores are calculated and returned between 0.0-1.0
3. Text range positions are accurately identified for extracted entities
4. Entity extraction completes within 5 seconds as per performance requirements
5. Core ML models load successfully on iOS devices
6. Natural Language Framework integration functional
7. Unit tests validate extraction accuracy for sample inputs

## Definition of Done

- Local entity extraction operational for all entity types
- Confidence scoring implemented and validated
- Privacy-compliant local processing verified

## Prohibited Actions

- Making network requests to cloud services
- Storing extracted entities in persistence layer
- Implementing background processing logic
- Creating user interface elements

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-026


---

### WS-143 — Implement Cloud AI Facade with Anthropic API Integration

## Work Statement

WS-143

Implement Cloud AI Facade with Anthropic API Integration

READY

a2

## Objective

Create the cloud AI facade component with Anthropic API integration and fallback capability for enhanced entity extraction

## Verification Mode

A

## Scope

- Cloud AI Facade component implementation
- Privacy-compliant cloud API integration
- Anthropic API facade with fallback capability
- Network connectivity awareness
- Cloud-based entity extraction with confidence scoring

- Local entity processing
- Background queue management
- Entity storage operations
- User interface components

## Allowed Paths

- src/ai/cloud/
- src/facade/
- src/network/

## Preconditions

- Connectivity Monitor component available
- iOS URLSession framework available
- API key management system in place

## Procedure

1. Create Cloud AI Facade class with LLM abstraction interface
2. Implement Anthropic API client with URLSession
3. Add JSON request/response handling with Codable protocols
4. Implement entity extraction API calls with confidence thresholds
5. Add network connectivity checking before API calls
6. Implement error handling for network timeouts, rate limits, and service unavailability
7. Add fallback mechanism for LLM provider switching
8. Create unit tests for API integration and error scenarios
9. Implement request/response logging for observability

## Verification Criteria

1. Cloud AI Facade successfully calls Anthropic API for entity extraction
2. JSON request/response handling works correctly with Codable
3. Network connectivity is verified before making API calls
4. Error handling covers all specified error cases (timeout, rate limit, invalid key, unavailable)
5. Fallback mechanism enables switching between LLM providers
6. API responses include entities with confidence scores
7. Unit tests cover successful and error scenarios
8. Request/response logging captures processing time and status

## Definition of Done

- Cloud AI integration operational with Anthropic API
- Privacy-compliant API calls with error handling
- Fallback capability implemented for provider switching

## Prohibited Actions

- Implementing local entity processing
- Managing background processing queue
- Storing entities in persistence layer
- Creating user interface elements

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-026


---

### WS-144 — Implement AI Processing Engine with Hybrid Processing Orchestration

## Work Statement

WS-144

Implement AI Processing Engine with Hybrid Processing Orchestration

READY

a3

## Objective

Build the central AI Processing Engine that orchestrates hybrid processing between local models and cloud APIs with high precision filtering

## Verification Mode

A

## Scope

- AI Processing Engine component implementation
- Hybrid AI processing architecture (local models + cloud APIs)
- High precision entity filtering with confidence thresholds
- Processing method routing and selection
- Integration with both local and cloud AI components

- Background queue management
- Entity storage operations
- Specific AI model implementations
- User interface components

## Allowed Paths

- src/ai/engine/
- src/extraction/

## Preconditions

- Local Entity Extractor component implemented
- Cloud AI Facade component implemented
- Processing Queue Manager component available
- Connectivity Monitor component available

## Procedure

1. Create AI Processing Engine class with entity extraction interface
2. Implement processing method routing logic (local vs cloud)
3. Add connectivity-based processing decisions
4. Implement high precision threshold filtering for entity validation
5. Add confidence score aggregation and comparison logic
6. Integrate with Local Entity Extractor for privacy-sensitive content
7. Integrate with Cloud AI Facade for enhanced extraction
8. Implement processing result validation and filtering
9. Add performance monitoring and processing time tracking
10. Create unit tests for routing logic and threshold filtering

## Verification Criteria

1. AI Processing Engine routes tasks to appropriate processor based on connectivity
2. High precision threshold filtering removes low-confidence entities
3. Integration with Local Entity Extractor functional
4. Integration with Cloud AI Facade functional
5. Processing method selection works correctly for local vs cloud
6. Confidence score filtering operates according to specified thresholds
7. Processing completes within 5 seconds as per performance requirements
8. Unit tests validate routing decisions and filtering logic

## Definition of Done

- Hybrid processing architecture operational
- High precision entity filtering implemented
- Processing orchestration between local and cloud verified

## Prohibited Actions

- Managing background processing queue directly
- Storing entities in persistence layer
- Implementing specific AI models
- Creating user interface elements

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-026


---

### WS-145 — Implement Entity Storage Manager with Core Data Integration

## Work Statement

WS-145

Implement Entity Storage Manager with Core Data Integration

READY

a4

## Objective

Create the Entity Storage Manager component that persists extracted entities with linkage to original journal entries using Core Data

## Verification Mode

A

## Scope

- Entity Storage Manager component implementation
- ExtractedEntity data model implementation
- Structured data storage linked to original entries
- Core Data operations for entity persistence
- Entity-to-entry relationship management

- AI processing logic
- Background queue management
- Journal entry storage
- User interface components

## Allowed Paths

- src/storage/entities/
- src/models/entities/

## Preconditions

- Core Data stack configured
- JournalEntry entity available for relationships
- ExtractedEntity data model requirements defined

## Procedure

1. Create ExtractedEntity Core Data entity with all required fields
2. Implement Entity Storage Manager class with persistence interface
3. Add CRUD operations for extracted entities
4. Implement relationship management between entities and journal entries
5. Add batch operations for storing multiple entities
6. Implement query methods for entity retrieval by type and confidence
7. Add data validation for entity fields and relationships
8. Create unit tests for storage operations and data integrity
9. Implement Core Data migration support for entity schema

## Verification Criteria

1. ExtractedEntity entity exists with all required fields (id, entry_id, entity_type, value, confidence_score, text_range, processing_method, created_at)
2. Entity Storage Manager provides complete CRUD operations
3. Relationships between ExtractedEntity and JournalEntry work correctly
4. Batch storage operations handle multiple entities efficiently
5. Query methods return entities filtered by type and confidence
6. Data validation prevents invalid entities from being stored
7. Unit tests verify storage operations and data integrity
8. Core Data handles up to 10,000 journal entries efficiently as per scalability requirements

## Definition of Done

- Entity storage component fully operational
- Structured data storage with entry linkage verified
- Core Data integration tested and validated

## Prohibited Actions

- Implementing AI processing logic
- Managing background processing queue
- Storing original journal entries
- Creating user interface elements

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-026


---

### WS-146 — Integrate Background AI Processing Pipeline End-to-End

## Work Statement

WS-146

Integrate Background AI Processing Pipeline End-to-End

READY

a5

## Objective

Complete the integration of all AI processing components into a cohesive background processing pipeline with comprehensive error handling and status tracking

## Verification Mode

A

## Scope

- End-to-end background processing workflow integration
- Component integration between queue, engine, extractors, and storage
- Processing status tracking and error handling
- Background processing queue coordination
- Complete AI processing pipeline validation

- Individual component implementations
- User interface integration
- Voice input processing
- Journal display features

## Allowed Paths

- src/processing/queue/
- src/ai/engine/
- src/background/

## Preconditions

- Processing Queue Manager implemented and tested
- AI Processing Engine implemented and tested
- Local Entity Extractor implemented and tested
- Cloud AI Facade implemented and tested
- Entity Storage Manager implemented and tested

## Procedure

1. Integrate Processing Queue Manager with AI Processing Engine
2. Connect AI Processing Engine with Entity Storage Manager
3. Implement complete background processing workflow
4. Add comprehensive error handling across all components
5. Implement processing status updates throughout the pipeline
6. Add retry logic for failed processing tasks
7. Integrate connectivity monitoring for cloud processing decisions
8. Create end-to-end integration tests for complete workflows
9. Add performance monitoring and processing time tracking
10. Implement graceful degradation when components fail

## Verification Criteria

1. Complete background entity extraction workflow executes successfully
2. Processing tasks move correctly through pending, processing, completed, failed states
3. Error handling captures and reports failures at each pipeline stage
4. Retry logic handles transient failures appropriately
5. Processing completes within 5 seconds as per performance requirements
6. Background processing manages up to 100 pending tasks as per scalability requirements
7. Integration tests validate complete workflow scenarios
8. Performance monitoring captures processing times and success rates
9. Pipeline gracefully handles component failures without data loss

## Definition of Done

- Background AI processing pipeline fully operational end-to-end
- All components integrated with comprehensive error handling
- Processing status tracking and queue coordination verified

## Prohibited Actions

- Modifying individual component implementations
- Adding user interface elements
- Implementing voice input processing
- Creating journal display features

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-026


---

# WP-027 — Structured Data Presentation and Search

## Overview

WP-027

Structured Data Presentation and Search

Surfaces extracted structured data through inline tags and enhanced search while maintaining journal experience, completing core value delivery.

PLANNED

## Scope

- Inline tag display within journal entries
- Enhanced search with entity-based filters
- Tag-based navigation and discovery
- Search result highlighting and context
- Filter persistence and search history
- Integration with journal display from WPC-001

1. All work statements executed and verified

## Governance

TA-001

- POL-ADR-EXEC-001

## Work Statements

| Statement ID | Order |
| --- | --- |
| WS-147 | a0 |
| WS-148 | a1 |
| WS-149 | a2 |
| WS-150 | a3 |
| WS-151 | a4 |

## Revision

2026-04-07T16:13:40.518216+00:00

system

## Lineage

- WPC-003

kept

Promoted as-is from IP candidate.

work_package_candidate

- WPC-003

kept

Promoted as-is from IP candidate.


---

### WS-147 — Implement Inline Tag Display Infrastructure

## Work Statement

WS-147

Implement Inline Tag Display Infrastructure

READY

a0

## Objective

Create the foundational components for rendering extracted entities as inline tags within journal entry text without compromising readability

## Verification Mode

A

## Scope

- Tag Renderer component implementation
- NSAttributedString-based tag styling
- Entity-to-text position mapping
- Tag visibility controls
- Integration with Entity Storage Manager

- Entity extraction logic
- Search functionality
- Journal entry creation
- Background processing

## Allowed Paths

- src/ui/tags/
- src/rendering/
- src/models/entities/

## Preconditions

- Entity Storage Manager component exists
- ExtractedEntity data model with text_range field available

## Procedure

1. Implement Tag Renderer component in src/ui/tags/
2. Create NSAttributedString-based styling for inline tags
3. Implement text range to visual position mapping logic
4. Add tag visibility toggle controls
5. Create interface for retrieving entities by entry ID
6. Implement tag styling that maintains text readability
7. Add unit tests for tag rendering logic

## Verification Criteria

1. Tag Renderer component successfully renders entities as inline tags
2. Tags maintain readable text styling without visual interference
3. Tag visibility can be toggled on/off by user
4. Entity text ranges map correctly to visual positions
5. Unit tests pass with >90% code coverage for tag rendering

## Definition of Done

- Tag Renderer component fully implemented and tested
- Inline tags render correctly within journal text
- User controls for tag visibility are functional
- Code passes all verification criteria

## Prohibited Actions

- Modifying entity extraction logic
- Implementing search functionality
- Creating new data models beyond interface requirements

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-027


---

### WS-148 — Enhance Journal Display with Inline Tags

## Work Statement

WS-148

Enhance Journal Display with Inline Tags

READY

a1

## Objective

Integrate inline tag rendering into the journal display system to show extracted entities within entry text while maintaining natural reading experience

## Verification Mode

A

## Scope

- Journal Display Controller enhancement for tag integration
- Entry retrieval with associated entities
- Inline tag rendering within journal entries
- Performance optimization for tag display

- Tag styling implementation
- Search functionality
- Entity extraction
- Entry creation workflows

## Allowed Paths

- src/ui/journal/
- src/display/

## Preconditions

- Tag Renderer component implemented and tested
- Entry Storage Manager component exists
- Entity Storage Manager component exists

## Procedure

1. Enhance Journal Display Controller to integrate Tag Renderer
2. Implement entity retrieval for displayed entries
3. Add tagged text rendering to journal entry display
4. Optimize performance for entries with multiple entities
5. Implement lazy loading for entity data
6. Add error handling for missing or invalid entity references
7. Create integration tests for journal display with tags

## Verification Criteria

1. Journal entries display with inline tags correctly positioned
2. Performance remains acceptable with 500ms render time for typical entries
3. Tagged entries maintain natural reading flow
4. Error handling gracefully manages missing entity data
5. Integration tests pass for journal display with tag scenarios

## Definition of Done

- Journal Display Controller successfully shows inline tags
- Performance meets 500ms render time requirement
- Tagged journal entries maintain readability
- All integration tests pass

## Prohibited Actions

- Implementing tag styling logic
- Creating search interfaces
- Modifying entity storage schemas

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-027


---

### WS-149 — Implement Enhanced Search Engine

## Work Statement

WS-149

Implement Enhanced Search Engine

READY

a2

## Objective

Create comprehensive search functionality with entity-based filtering, relevance ranking, and result highlighting to enable discovery of journal content through structured data

## Verification Mode

A

## Scope

- Search Engine component implementation
- Entity-based filter system
- Relevance ranking algorithm
- Search result highlighting
- Query parsing for text and entity filters

- Search UI components
- Search history persistence
- Tag rendering within search results
- Entry creation or modification

## Allowed Paths

- src/search/
- src/filters/

## Preconditions

- Entry Storage Manager component exists
- Entity Storage Manager component exists
- ExtractedEntity and JournalEntry data models available

## Procedure

1. Implement Search Engine component in src/search/
2. Create query parsing logic for text and entity-based searches
3. Implement Core Data NSPredicate-based search queries
4. Add entity type filtering (project, person, issue, idea, next_action)
5. Implement relevance ranking based on text match and entity confidence
6. Create result highlighting for matched text and entities
7. Add search result context extraction
8. Implement unit tests for search functionality

## Verification Criteria

1. Search Engine returns relevant results within 1 second for typical queries
2. Entity-based filters correctly narrow search results
3. Relevance ranking prioritizes best matches appropriately
4. Search result highlighting identifies matched terms
5. Unit tests achieve >90% code coverage for search logic

## Definition of Done

- Search Engine component fully implemented and tested
- Entity-based filtering works correctly for all entity types
- Search performance meets 1-second response time requirement
- Result highlighting and ranking function properly

## Prohibited Actions

- Creating search UI interfaces
- Implementing search history storage
- Modifying entity extraction logic

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-027


---

### WS-150 — Implement Tag-Based Navigation and Discovery

## Work Statement

WS-150

Implement Tag-Based Navigation and Discovery

READY

a3

## Objective

Enable users to navigate and discover journal content through entity-based browsing, creating pathways for exploration beyond traditional search

## Verification Mode

A

## Scope

- Entity browsing interface
- Tag-based navigation workflows
- Entity relationship discovery
- Content discovery through entity connections

- Search result display
- Entry editing capabilities
- Entity extraction or modification
- Search history features

## Allowed Paths

- src/ui/journal/
- src/display/
- src/search/

## Preconditions

- Search Engine component implemented
- Tag Renderer component implemented
- Journal Display Controller with tag integration complete

## Procedure

1. Extend Journal Display Controller with entity navigation
2. Implement entity browsing interface showing all entities of a type
3. Create navigation from inline tags to related entries
4. Add entity-based content discovery workflows
5. Implement related entity suggestions
6. Create navigation history for tag-based browsing
7. Add integration tests for navigation workflows

## Verification Criteria

1. Users can tap inline tags to navigate to related content
2. Entity browsing shows all entities grouped by type
3. Navigation between related entries works smoothly
4. Entity-based discovery surfaces relevant connections
5. Navigation performance maintains responsive user experience

## Definition of Done

- Tag-based navigation fully functional
- Entity browsing interface complete
- Content discovery through entities works effectively
- All navigation workflows tested and verified

## Prohibited Actions

- Implementing search result display logic
- Creating entry editing interfaces
- Modifying search engine core functionality

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-027


---

### WS-151 — Implement Filter Persistence and Search History

## Work Statement

WS-151

Implement Filter Persistence and Search History

READY

a4

## Objective

Provide persistent search filters and search history functionality to improve user experience and enable quick access to frequently used search patterns

## Verification Mode

A

## Scope

- Search filter persistence mechanism
- Search history storage and retrieval
- Recent searches interface
- Saved search filters functionality

- Search engine core logic
- Tag rendering functionality
- Entity extraction processes
- Journal entry display

## Allowed Paths

- src/search/
- src/storage/
- src/config/
- src/preferences/

## Preconditions

- Search Engine component implemented and tested
- Configuration Manager component exists

## Procedure

1. Design search history data model
2. Implement search filter persistence using UserDefaults
3. Create search history storage mechanism
4. Add recent searches retrieval functionality
5. Implement saved filter management
6. Create search history cleanup and limits
7. Add unit tests for persistence functionality

## Verification Criteria

1. Search filters persist across app sessions
2. Search history stores and retrieves recent queries accurately
3. Saved filters can be applied to new searches
4. Search history respects storage limits and cleanup policies
5. Persistence functionality passes all unit tests

## Definition of Done

- Filter persistence works reliably across app restarts
- Search history functionality complete and tested
- Saved filters can be managed by users
- Storage limits and cleanup mechanisms function properly

## Prohibited Actions

- Modifying search engine ranking algorithms
- Implementing search UI components
- Creating new entity types or extraction logic

## Governance

TA-001

- POL-ADR-EXEC-001
- POL-WS-001

WP-027



---

## Ontology Evaluation (ADR-059)

**apam (v1.1)**: ontology clean — 29 artifacts checked, 0 cross-layer leakage findings

---

## WP Boundary Overlap Evaluation

**Boundaries clean** — 3 WPs checked, 0 overlap findings

---

## Cross-Layer Contradiction Evaluation (ADR-061)

**No contradictions detected** — 16 WSs checked against TA authority surfaces

---

## Duplicate WS Objective Detection (ADR-062)

**Potential duplicates: 1** (16 WSs checked)

| Rule | Work Statements | WPs | Type | Evidence |
| --- | --- | --- | --- | --- |
| DUP-SCOPE-001 | WS-138, WS-145 | WP-025, WP-026 | scope_overlap | Scope similarity 62% between WS-138 and WS-145 |

---
## Operator Corrections Audit (ADR-069)

Documents generated with active operator corrections:

- **TA-001**: 1 correction(s) active (record IDs: 6a7f759f...)