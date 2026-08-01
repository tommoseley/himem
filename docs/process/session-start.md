# Session start

Codifies the restart handoff. **This file does not describe the work** — the punch list is the single source for what to build, and duplicating it here creates a second copy to drift.

Files are referenced by **role**, never by filename. A filename in a process doc rots into the phantom-comment class the moment something is renamed.

---

## 1 · Read the governance docs

In this order, before touching anything:

- **The repo governance file** (repo root) — Bug-First, Measurement Discipline, Assert-the-Meaning, Guard-the-Caller, and the platform-specific locks.
- **The orchestration file** (repo root) — how work is divided when it is divided at all.
- **The architectural invariants** and the **design-system governance file** — what may not be redesigned in passing.
- **The latest session log** — where the previous session actually stopped, as opposed to where it planned to stop.
- **The current punch list / action-items inventory** — the work itself.

If any two of these disagree, that is a finding. Raise it; do not pick one silently.

## 2 · Confirm position before proposing anything

State these back explicitly, because every one of them has been wrong before:

- **Branch** — confirm by asking git, not by assuming the handoff was accurate.
- **Tree state** — tracked changes, untracked work-in-progress, and anything deliberately red.
- **The paired gate numbers** — both schemes, as *counts of cases and suites*, from the result bundle rather than the exit code.

**A gate is a count, not a coverage claim.** If any test skips itself when an environment asset is missing, say so alongside the number — a suite that passes with legs that never ran is green and weaker than it reads.

Known traps, each of which has cost a session:
- A nonzero exit code has at least four meanings (compile failure, assertion failure, launch/infrastructure denial, no project in the working directory). Identify which before reading anything into it.
- A simulator launch denial that **survives** a shutdown is device-specific — switch simulators. One that **clears** after a shutdown was just busy state — re-run.
- The working directory does not survive a `cd` in an earlier command; pass the project path explicitly.

## 3 · Take the next item

From the punch list, in the order the ruling set — not the order that looks cheapest. If the next item is ambiguous, ask before building; a raised question is cheap and a silent reinterpretation is a day.

If an item's finding came from an audit or a prior session's report, **verify its enumeration before acting on it.** Findings have been wrong in both directions: counts short, and comments called stale that were accurate. Acting on a mischaracterised finding can turn a correct comment into a wrong one, which is worse than leaving it alone.

## 4 · Then work

One commit per defect. Both schemes green before each commit — or, where a deliberate failure is the honest state, both schemes at their **stated known position**, with the deliberate failures named.
