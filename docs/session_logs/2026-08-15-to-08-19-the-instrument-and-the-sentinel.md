# Session log · 2026-08-15 → 08-19 · the proposal instrument · B21 · C2 steps 3 + 4A/4B · the sentinel collapse

Facts only. Immutable. **Written for a context-free reader.** Covers `b2d3e3f..24e02ad` (8 commits).

---

## Repo position

- Branch **`f8-overlay-and-wiring`** @ **`24e02ad`**, **35 ahead of `main`, 0 unpushed** (pushed throughout, ruled 2026-08-15).
- **`main` @ `36ce159`** — deliberately behind; every C2 rebuild commit lives on `f8` only.
- Tree clean of tracked code **except one held red** (below). `docs/design/` holds Tom's uncommitted work plus **B21–B26**, added this stretch.
- **Two numbers, stated separately from here on** (ruled): *ahead of `main`* and *unpushed to origin* are different measurements and were conflated at session open.

### Gate — both read from result bundles, isolated `-derivedDataPath`, `DEVELOPER_DIR` on Xcode-beta

| Scheme | Result | Destination |
|---|---|---|
| `MemoryStream` | **1461 cases / 202 suites** — 1450 passed, 3 skips, **8 deliberate failures**, **0 crash messages in the bundle** | sim `E3C0710E` (**iOS 26.4.1**) |
| `Himem Watch Watch App` | **37 cases / 8 suites, 0 failed** | watch `B17233F6` + paired `74EED5FE` (**watchOS 26.5**) |

The 8 are `SpeechAssetGate`; membership verified **byte-identical by `diff`**, not by eye. Runtimes held; no rotation.

**Counts moved 1433/193 → 1461/202** across the stretch. One step went *down* (1452 → 1451) while suites went up: four source-scan/subtraction guards retired against three behavioural ones. **Coverage rose while the number fell** — the step-5 trade arriving early.

---

## THE HEADLINE — B25: a sentinel used as a dictionary key

`mediaBySessionId` is keyed by `project(session).id`. `projectGroup` keeps **voice only**, so a media-only session projects to `ClipGroup(clips: [])`, whose id is `ClipSessionGrouper.emptyGroupId` — a **fixed sentinel** (`…E317`) introduced by `18021bc` to close the Clips freeze.

That sentinel's own doc says *"two empty groups now COLLIDE."* It was reasoned about for `ForEach` identity and **never joined to the fact that the same value is a dictionary key.** So every voiceless session writes one bucket, each overwriting the last, and every one reads back whatever the last writer left.

Device, via `[ResolveProbe]`: three sessions at `resolved=6 legacy=1` and `resolved=4 legacy=1` ×2, all `key=00000000 map=HIT`, all `kinds=` media-only.

### WHICH SIDE IS WRONG — this reframes slice C

**`resolved` iterates the session's own items and is CORRECT. `legacy` reads the collapsed bucket.** The path being *retired* is the defective one, and the value C2 step 4 migrates *to* is sound.

So **slice C is the remedy for a diagnosed defect, not a refactor blocked by an unknown.** CC had flagged `resolved` as the suspect purely because it was the side that disagreed; Tom's correction inverted the blocker, and the correction is the load-bearing part of the finding.

### Reproduced, not inferred — and the assertion that PASSED is the proof

`twoVoicelessSessionsEachKeepTheirOwnMedia` fails with exactly **two** issues:

- `keyA != keyB` — **FAILS**, both are the sentinel
- `map[keyA]?.count == 2` — **FAILS**, session A reads back B's three refs
- `map[keyB]?.count == 3` — **PASSES**, B was the last writer

That third line explains the device's rotating report: a voiceless session holding exactly **one** item agrees by coincidence (`0 + 1 == 1`) and stays silent, so which sessions appear depends on what the last writer left.

### There is no smaller fix

The collapse is not a mis-chosen key that can be swapped. It is caused by projecting a session to a **voice-only type** and using that projection's id as identity. Keying by `UnifiedSession.id` does not help either: the **lookups** are `mediaBySessionId[session.id]` where `session` is the projected `ClipGroup`. **Retiring the projection is the fix, and that is slice C.**

**SECOND SITE, in scope for slice C (ruled): `SessionListView:1148`** — `allSessions.first(where: { $0.id == sessionId })` returns the first of N colliding sentinels. Retiring the map does **not** touch it.

**Latent today, live tomorrow.** After C2 step 3, voiceless sessions are drawn by the sibling stack from the bus, so nothing reads the collapsed bucket — step 3 made this unreachable without knowing it was there. Step 4's swap or the deferred layout flip puts it back on a card path.

---

## THE HELD RED — do not soften it to pass

**Path:** `MemoryStream/MemoryStreamTests/BenchMediaKeyCollapseTests.swift.held` (untracked, in the working tree).

It was first parked in the session scratchpad; **that path is session-scoped and would not have survived**, so it was moved into the repo. The `.held` suffix means it is not a `.swift` file, so it **cannot compile into the test target and cannot silently redden a gate**, while `git status` keeps it visible.

Slice C opens with `mv …swift{.held,}`. **It turns green when the projection retires.** The branch never carries a knowingly-failing gate — the same handling the 2b-ii-b red got — and the test is **not** to be adjusted to pass.

---

## B18 WAS MIS-DIAGNOSED, AND THE CORRECTION IS B26

B18 was recorded as *"two memories sharing a title collide."* **That was wrong.** The identical SwiftUI warning is produced by **one memory appearing twice**, and keying by `UUID` proves which: the warning **survives with a duplicate id**.

Keying by identity rather than by label was right on its own merits (a label is never an identity) — but it fixed the key, and **the duplicate is in the data**.

**B26 · duplicate `MemoryClipEdge` rows**, one clip attached to the same memory twice. `memoriesArray` is `edgesArray.compactMap { $0.memory }` with **no dedupe**.

**The consequence lands at the worst possible moment:** `referencingMemoryCount` counts `memoriesArray`, so the delete warning reads *"This clip is part of 2 memories. Deleting it removes it from all of them"* when it is **one** — a confident falsehood at the instant of destruction, which is the Honest-Label class where it costs most.

**Own cycle, not a fold-in (ruled).** The question that matters is *how two edges were created*; a render-side dedupe is downstream of that and must not be mistaken for the fix.

---

## B24 · AN INTERMITTENT HOST CRASH — logged, NOT diagnosed

A full phone gate returned **67 failures**. It is **one defect**: 63 carry `Test crashed with signal abrt.`, the other 4 are the standing `SpeechAssetGate` set. The spread — `VoiceComposerBreathRotation`, `Linkify`, `TopicFilterBus`, `EdgeAnnotation`, `SummaryFieldMigration` — has no relationship to the change under test (a sort in a trace and three log fields).

An immediate re-run of the identical tree was clean at 1461/202 with byte-identical membership, so it is **intermittent, not deterministic**. `signal abrt` is the `libsystem_malloc` family CLAUDE.md names, whose remedy is a lock **at the owner**, never `@Suite(.serialized)`.

**Suspect, stated as a suspect:** three new suites now each construct `StorageService(inMemory: true)` — the B14 tipping shape, where adding a handful of tests turns a latent race into crashes.

### METHOD NOTE — the expensive half

**The crash text lives in the result bundle's `Failure Message` nodes, NOT in the `.log`.** A grep for crash signatures over the log returned **0**, which reads as *"no crash"* and would have sent the next reader hunting 67 unrelated defects. Same family as the `head -8` that produced "no callers exist": a well-formed search of the wrong artifact.

**Also of that family, in the safe direction:** a `head -4` on a mutation's failing list reported one failing test when there were two, *understating* coverage. Re-read unbounded and corrected.

---

## B23 CONFIRMED, WITH A TARGET — and on the right instrument

**25 regroups in 16 s**, first at **373 ms**, the rest 27–50 ms, each carrying a full NLTagger pass (27–87 ms measured).

**The evidence is `[BenchPerf]`'s independent counter, not `[ClusterTrace]`'s emission count.** The trace's count was never clean until this stretch's ordering fix, and B23 had originally been logged on it. It also survived a **second** wrong reading: the entry first claimed `regroupSessions()` runs per `body`. It does not — there are **seven** `onAppear`/`onChange` triggers and none is the view body, so a fix hoisting work out of `body` would have optimised a path that was never the cost. **Both wrong readings are kept in the entry.**

The memoization stays **unwritten** (ruled) until slice C's outcome is known.

---

## THE INSTRUMENTS — and both reported churn they invented

**`[ClusterTrace]`** (`0c45585`) — every proposal *as formed* with rule tag and claimed ids, then its fate: **four** fates, not two (eaten by overlap with the ratio *and* the eater named, dismissed, below minimum size, survived), plus a verdict per shared token and the sessions as the proposer received them.

**It exonerated the proposer immediately:** all three fixture clusters FORMED and SURVIVED. Sparrow Quarry had cost four wrong theories; the instrument ended it in one reading.

**Then it manufactured a finding.** It fired ~16 times over an unchanging bench because its verdict order came from a `Dictionary` — that became B23 "a regroup storm." Fixed (B21). **Then it did it again** from the FORMED array, which `recordFormed` captures *before* `propose`'s final sort — one day after B21 fixed the same defect's other two faces.

**Verified on hardware: one emission against ~16 on the same bench.** The instrument is finally reporting the bench rather than itself. Fixed at **both** root and capture, deliberately: the instrument's stability must not depend on the thing it measures staying correct.

**`[ResolveProbe]`** (`486b607`, extended `7223de1`) — composes `ResolvedSession` alongside the legacy `(ClipGroup, mediaBySessionId)` pair and reports disagreement. Extended with `key=`, `map=HIT|MISS` and `kinds=[…]` **rather than picking one of three candidate mechanisms** — the reading then named the sentinel outright.

---

## The rest of the work

| Commit | What |
|---|---|
| `c8a905c` | **B21** — the cluster name was decided by dictionary order; `signalStrength` reads that name, so the dedup could order differently between runs under a doc claiming "same input always produces the same output". Fixed to a total order (proper noun ≻ non-proper, then lexicographic). |
| `55b85eb` | **B17(a)** — `"Together at Sun 5:44 PM"` asserted the grouping its own eyebrow only proposes, in the card's largest type; now `"Sun 5:44 PM"`. **A memory made from a proposal now arrives UNTITLED** (both sites, including `SortBatchCommit`, which has **zero production callers**). **B17(b)** — the delete warning's zero branch dropped. **B18** — `MemoryChip` keyed by the memory's `UUID`. |
| `9986067` | **C2 step 3** (option 3, ruled) — the sibling stack stops re-fetching what the bench composed. Predicates were **identical**; only the sort differed, so the stack re-applies its own descending order (`groupedByDay` preserves input order *within* a day). `hasSiblingContent` OR'd with the view's own composition to avoid an F22-class false-empty frame. **No pixels moved.** |
| `486b607` | **C2 step 4 slices A+B** — `ResolvedSession` (unresolved ids **reported, not dropped**) and the probe. |
| `24e02ad` | **B25's seam** — `mediaBySession` extracted behaviour-preserving; `projectGroup` made internal rather than adding a `…ForTesting` alias. |

**`ClipGroup` survives step 4**, and the step list must not be read otherwise: `ClipClusterProposer.propose` takes `[ClipGroup]` and `ClipSessionGrouper` produces them. Step 4 migrates the **card layer** only.

**Two guards retired because their subject became structurally impossible**, each recorded in place with its invariant's new home named — not deleted quietly. A guard whose defect can no longer occur is a different thing from a guard that was wrong.

**A guard passed its own mutation.** The set-aside scanner split source on `"/// "`, so each chunk carried the following *code* and the exclusion count rose with the literal it was meant to exclude; M4 restored the retired label and it **passed**. Rewritten to scan non-comment lines and re-verified against the still-live mutation. **The matcher, not the rule, was the defect** — third instance of that family here.

---

## What was NOT verified

**This is an absence section. It is the part most expensive to inherit wrong.**

- **Nothing from this stretch has had a device pass beyond the two probe readings themselves.** C2 step 3's partition, B17's untitled memory, B18's chip identity, B25's seam and every guard added are proven in tests only.
- **Slice C has not started.** The target is written down; the edit is not made.
- **B24 is not diagnosed** — intermittent, one occurrence, suspect stated as a suspect.
- **B26 is not investigated** — how two edges were created is unknown.
- **B23's memoization is unwritten**, deliberately.
- **The deferred layout flip is unruled** — whether voiceless sessions eventually draw as session cards in one list, dissolving P7-1's two regions. It is a *what*, not a parameter change, and step 3 deliberately did not touch it.

## Open threads

- **Slice C** — `mv BenchMediaKeyCollapseTests.swift{.held,}`, retire the projection, fix `:1148`, watch it go green. Held for a fresh session **on the 2b-ii precedent**: that revert was a large atomic edit *in this same file* at the tail of a long stretch, and its log says that timing "is not a coincidence worth reproducing."
- **B26** own cycle · **B24** undiagnosed · **B23** with a target · the layout flip · **C2 step 5** (retires ~59 source-scan assertions; **the gate count will fall while coverage rises**).
- Carried: B17 closed, B18 superseded by B26, B19, B22 ⊘ retired (the Core Data round-trip: accused twice, exonerated twice by cheaper evidence), D1 · D3 · D4 · D7 · F34/C15 · D9b · C1–C15.

## Risks

- **`main` and `f8` are 35 apart.** Pushed, so the exposure is integration, not loss.
- **The held red is untracked.** A `git clean -fd` would delete it; the log carries its content location for that reason.
- **Two instruments in two days reported churn they invented.** Both are fixed and both are guarded, but the pattern is the one to watch: an instrument that manufactures a finding costs more than no instrument.
- **Concurrent phone+watch gates left the watch pair shut down twice**, once wedging a run for 16½ minutes. Discriminator: flat CPU **and** a stale log mtime **and** no booted sims — any one alone is not enough. `pkill` then yields **exit 144**, another meaning for that pile. **Run the gates sequentially, booting the pair immediately before the watch invocation.**
- Disk fell to ~9 Gi at its lowest; trees cleared at close.
