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

## 2b · Verify the toolchain before trusting any number

**A gate number is only comparable to the last one if the thing that produced it has not moved.** Check, do not assume — and record the answer either way, because "nothing changed" is a claim that needs a comparison behind it.

- **The active developer directory.** The canonical invocation is:

      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

  This is the one place a path is named rather than a role, deliberately: every
  session before 2026-09-20 names a beta path that **no longer exists**, so an
  inherited command fails loudly — which is the right failure, but the doc
  should teach the current path rather than leave the terminal to.

  **THE LOUD GUARD IS RETIRED, AND IT WAS RETIRED ON PURPOSE (2026-09-20).**
  This bullet used to say the gates run under an explicit override *because the
  system-wide setting points somewhere else*, and warned that a toolchain
  install would invert the failure mode — an invocation forgetting the override
  would stop erroring and start silently succeeding against a different
  toolchain.

  That inversion has now happened: `xcode-select` points at Xcode and a bare
  `xcodebuild` resolves. **It no longer matters, because the thing the guard
  protected against was removed instead.** Its purpose was to stop a forgotten
  override selecting a DIFFERENT toolchain; the betas were deleted at the GA
  upgrade, so there is one Xcode on the machine and a forgotten override now
  reaches the same compiler. Rule replaced by mechanism — the ambiguity is
  gone by construction rather than watched for.

  *Recorded here so a future reader finding no guard finds the reason beside
  it, rather than concluding it lapsed.* If a second Xcode is ever installed,
  the ambiguity returns and the guard does not come back with it — that is the
  moment to re-read this paragraph.
- **The OS build, the SDK builds, and the simulator runtimes** — against the values in the most recent log. The SDK build is what a store upload's acceptance was measured against; the runtime pin is what makes the deliberate-failure count mean the same thing as last time.
- **Any of these moving makes the next gate a NEW BASELINE, not a confirmation.** Say that explicitly. Counts that coincide across a toolchain change are normally a coincidence, not continuity — that has happened here and was recorded as such.

  **The exception, and what it costs to earn:** a coincident count IS continuity
  when nothing else moved *and you can prove it*. The 2026-09-20 GA upgrade is
  the worked example — the tree was frozen (git tree hash, a content hash over
  all 450 Swift sources, and `project.pbxproj` all re-checked after the
  install), and the failing membership was **byte-compared** against a file
  frozen before it, not eyeballed. Identical counts then mean no change rather
  than two numbers that happen to match. Freeze before, compare after; a gate
  that moves across a toolchain change only tells you something if nothing else
  moved.

Where a value must not drift, prefer erasing and recreating on the same version over switching to a different one. "Grab whatever is available" is how a pin is lost inside a routine step nobody thinks of as a decision.

## 3 · Take the next item

From the punch list, in the order the ruling set — not the order that looks cheapest. If the next item is ambiguous, ask before building; a raised question is cheap and a silent reinterpretation is a day.

If an item's finding came from an audit or a prior session's report, **verify its enumeration before acting on it.** Findings have been wrong in both directions: counts short, and comments called stale that were accurate. Acting on a mischaracterised finding can turn a correct comment into a wrong one, which is worse than leaving it alone.

## 4 · Then work

One commit per defect. Both schemes green before each commit — or, where a deliberate failure is the honest state, both schemes at their **stated known position**, with the deliberate failures named.
