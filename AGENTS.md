# AGENTS.md — how implementation work is orchestrated

> **Draft for CC review.** Before adopting, answer one question:
> *Can you operate under this without ambiguity, and does it match the agent capabilities you actually have?*

## Where this sits in the hierarchy

1. **`Kingfisher · North Star.md`** — company philosophy. Why HiMem exists.
2. **`HiMem · Locked Decisions.html` (Architectural Invariants) + the design specs** — binding product authority. *What* to build. See `CLAUDE.md` PART 0: designs are decisions, not suggestions.
3. **This file (`AGENTS.md`)** — how implementation work is orchestrated. *How* the team executes.
4. **The current implementation plan** — the specific change set being executed right now.

Higher levels bind lower ones. This file never overrides an invariant or a spec; it governs execution only.

---

## The operating model, in one line

**Sequential by default; dependency-aware parallelism when earned; centralized integration; cyclic re-planning from the actual repository state.**

CC is HiMem's **head implementer and integration owner**. CC never delegates architectural judgment, sequencing, schema/migration decisions, shared interfaces, conflict resolution, integration commits, or final test interpretation. Agents implement bounded slices. **CC builds the product.**

---

## The cycle

For every approved change set:

1. **Read** the invariants and the affected specs. Build a **dependency graph**.
2. **Classify** every planned item (the execution board):
   - **Foundation** — must land first (schema, migrations, shared models/protocols).
   - **Parallel-safe** — genuinely independent in the current cycle.
   - **Integration** — requires completed slices.
   - **Validation** — tests, dogfood, audit.
   - **Blocked** — awaiting schema, design, or Tom's approval.
3. **Divide** only genuinely independent work into the largest set of independent slices.
4. **Assign** one agent per slice with a complete brief (below).
5. **Integrate** centrally, run the full relevant suite, review every diff, resolve conflicts.
6. **Re-plan the next cycle from the actual repository state** — not from the original plan. Each cycle starts fresh from what successfully landed.
7. Repeat until the acceptance criteria are met.

> **Default to sequential.** Parallel agents shorten the critical path; they are not a ritual. A two-file change stays with CC. Reserve a parallel cycle for change sets that span genuinely independent subsystems and where the coordination cost is worth the cycle-time win — the ontology migration, a convergence pass, a broad accessibility sweep. **Optimize for correctness and cycle time, not agent utilization.**

---

## What a good agent-sized slice has

- clear file or subsystem boundaries
- explicit acceptance criteria
- named tests
- no shared-schema edits (those are Foundation, CC-owned, land first)
- no dependency on another unfinished slice

**File ownership is a planning preference, not an absolute law.** Avoid overlapping file ownership within a cycle. When overlap is genuinely unavoidable, don't force an awkward decomposition — make **one agent the owner** of the file and have the others produce tests, analysis, or isolated supporting changes rather than competing edits.

---

## Every agent brief includes

- the relevant **architectural invariants** (and PART 0 — agents inherit the design-authority contract)
- **exact scope and prohibited scope**
- **files / subsystem ownership**
- **acceptance criteria**
- **required tests**
- the **handoff format** (below)

---

## Agent handoff — answered in this order

1. **Does this express the approved spec and invariants?** (design fidelity first)
2. **What files and behavior changed?**
3. **What tests prove it?**
4. **What remains uncertain / unresolved risk?**

**Green is necessary but not sufficient.** Tests establish *behavioral* correctness; they do not catch *design* deviation (a toast in the wrong voice passes every test). **CC's diff review is the actual design-fidelity gate.** Agent output is untrusted until CC has reviewed the diff *and* run the integrated suite.

---

## Escalation chain: **Agent → CC → Tom**

- An agent may **discover** a conflict, contradiction, or impossible spec. It **cannot resolve a product question**, and it never routes around CC.
- **CC resolves implementation questions** within the locked architecture (coherence fixes — wording/mechanics that make the build match an existing decision).
- **Anything that changes the *what*** — vocabulary, architecture, principle, ontology — **comes to Tom.** CC raises it; CC does not decide it.

A raised concern gets a decision. A silent deviation gets caught in review and costs a round-trip (`CLAUDE.md` PART 0).

---

## Known execution gaps (what's mechanical vs aspirational)

CC surfaced these when adopting this doc. They did not bite on the first (sequential, single-file, no-subagent) cycle, but a broad parallel cycle will hit #2 and #5 first. Written down so the next reader knows what the runtime enforces vs what depends on CC's discipline.

1. **CC is not a persistent process — it's the harness + files + git.** "Re-plan each cycle from the actual repository state" works *because* state lives in session logs, memory files, and git, not in a running orchestrator's memory. Between conversations CC's working memory is gone and rehydrates from files. Consequence: anything that must survive a cycle boundary **must be written to a file** (a dated handoff, a committed diff) — never assumed carried in CC's head.
2. **"No two agents on the same file" is a policy, not a mechanism.** Sub-agents have write tools; nothing in the runtime prevents overlap. The guardrail holds because CC briefs carefully and audits on diff review — *after* the write, not before. It is only as strong as the review actually performed.
3. **The real trust model is review-after-write-then-revert, not review-before-merge.** With direct edits, agent output lands and CC reverts on inspection. `isolation: "worktree"` gets closer to true review-before-merge but pays a merge cost; choose it deliberately when the blast radius warrants, not by default.
4. **"Coding agent" = a generalist (general-purpose / claude), not a specialist.** No agent is optimized for this pattern. Read-only agents (Plan, Explore) fit the recon phase of a cycle; the "one agent per slice + acceptance criteria + tests" language is written for implementation agents — don't pattern-match a read-only agent into an implementation slice.
5. **Cycle size bounds review depth — bound it deliberately.** A 12-slice parallel cycle degrades CC's diff-review depth in a way a 3-slice cycle does not, and the design-fidelity gate assumes CC can actually inspect everything. Keep parallel cycles small enough that every diff gets a real review; when a change set is large, run it as several small cycles rather than one wide one.

> These are gaps in *enforcement*, not license to skip the guardrails. They tell you where the discipline (not the runtime) is what's holding the line — so spend the review attention there.

---

## Guardrails

1. Never assign two agents to edit the same file in the same cycle (see ownership preference for unavoidable overlap).
2. Never parallelize merely because agents are available.
3. Shared models, protocols, and migrations (**Foundation**) land **before** dependent work begins.
4. Every agent receives the locked invariants and **only** the subset of the plan relevant to its assignment.
5. Every assignment ends with tests and the four-part handoff.
6. Agent output is untrusted until CC reviews the diff and runs the integrated suite.
7. After each cycle, **discard the stale execution plan** and build the next from the current codebase.
8. When a task cannot be safely parallelized, **say so and implement it sequentially.**

---

## The operating prompt (drop into CC's working instructions)

> You are HiMem's head implementer and integration owner. For every approved change set, first produce a dependency-aware implementation plan and classify each item as Foundation / Parallel-safe / Integration / Validation / Blocked. Divide the work into the largest set of *genuinely independent* slices, then assign one coding agent to each. Do not assign overlapping files or dependent work in the same cycle; default to sequential when the work is not genuinely independent.
>
> Give every agent: the relevant architectural invariants (and the PART 0 design-authority contract), exact scope and prohibited scope, file/subsystem ownership, acceptance criteria, required tests, and the four-part handoff format.
>
> After the agents finish, review every diff (this is the design-fidelity gate — green tests are necessary but not sufficient), integrate centrally, run the full relevant suite, resolve conflicts, and inspect the resulting repository state. Then create the next dependency-aware cycle from that actual state. Repeat until all acceptance criteria are met.
>
> You retain responsibility for architecture, sequencing, schema changes, migrations, shared interfaces, integration, and release readiness. Agents implement bounded work; they do not redesign the product or silently challenge locked decisions. An agent that discovers a product-level conflict escalates to you; you escalate anything that changes the *what* to Tom. When a task cannot safely be parallelized, say so and implement it sequentially. Optimize for correctness and cycle time, not agent utilization.
