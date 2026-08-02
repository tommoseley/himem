# Session end

Codifies the restart handoff from the writing side. The session log is written **for a context-free reader** — assume nothing survives except what is in files and git.

Files are referenced by **role**, never by filename.

---

## 1 · Write the log

Into the session-log directory, dated. Facts only, no reflection. **Immutable once written** — a later correction goes in the next log, never as an edit to a past one.

It must carry:

- **Scope** — what was ruled, and by whom.
- **Repo position** — branch, commits since the last log, what is committed vs uncommitted vs deliberately untracked, and how far ahead/behind the branch sits.
- **The paired gate numbers**, both schemes, as counts of cases and suites read from the result bundle.
- **Decisions and rulings**, including the ones that closed an option — a rejected path is as load-bearing as a taken one, and without it the next session re-litigates it.
- **Retractions.** Anything claimed earlier and later found false, with what the false claim rested on. These are the most valuable lines in the log; a retraction that propagated into other files must name every site it reached.
- **Open threads and risks**, each with enough context to act on cold.

## 2 · State the position plainly

- **Branch and tree** — including anything left deliberately red or deliberately uncommitted, and why.
- **Gate**, stated honestly. If the run was green except for named deliberate failures, say exactly that; do not round it to "green." If any test skipped itself for a missing environment asset, **the gate is a count and not a coverage claim** — say which legs did not run.

## 3 · State what you did **not** verify

This is the load-bearing section and the easiest one to skip, because everything in it is an absence.

Name explicitly:

- **What was reasoned about but never executed** — a fix whose safety rests on reading rather than a red-green cycle, a path with no test coverage, a caller that could not be driven from a test.
- **What was simulator-only** — anything unproven on device, and anything whose device behaviour is known to differ.
- **What was sampled rather than swept**, and the cap that bounded it. A conclusion inherits the weakness of its weakest input; a finding rests on the measurement that produced it, so state the measurement beside it.
- **Which enumerations are trusted rather than re-counted** — including enumerations inherited from an audit, a prior log, or an earlier session's own sweep. These have been wrong repeatedly, in both directions.
- **Which guards were mutation-verified and which were not.** A guard that has never failed is a guard nobody has tested.

A session that reports only what it confirmed reads stronger than it is, and the next reader inherits that overstatement as fact.

## 4 · Close

Ask whether to close or continue. Do not assume the answer, and do not treat a background task's completion as an answer.
