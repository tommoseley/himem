# Session log · 2026-08-19 evening · the gate definition · four device items · B23 · the eighth count

Facts only. Immutable. **Written for a context-free reader.** Covers `0a6efe3..3f4f956` (3 commits).

---

## Repo position

- Branch **`f8-overlay-and-wiring`** @ **`3f4f956`**, **45 ahead of `main`**, **0 unpushed**.
- **`main` @ `36ce159`** — deliberately behind; every C2 rebuild commit lives on `f8` only.
- Code tree **clean**. `docs/design/` holds Tom's uncommitted work and was extended this session at his direction (below) but **left unstaged** — that directory is his working set, and a `git add -A docs/design/` has nearly swept it into an unrelated commit before.
- **One deliberate untracked artefact:** `MemoryStreamTests/DuplicateEdgeConvergenceTests.swift.held` — B26's deferred reconcile with its survivor policy already ruled. Inherited, not re-decided.
- A second `.held` file existed transiently this session (`BenchHeaderCountTests.swift.held`) and was **released green**, not adjusted. It is now a normal test file.

### Gate — both read from result bundles via `scripts/gate-report.sh`, isolated `-derivedDataPath`, `DEVELOPER_DIR` on Xcode-beta, run **sequentially** with the watch pair booted immediately before

| Scheme | Result | Destination |
|---|---|---|
| `MemoryStream` | **1491 cases / 210 suites** — 1480 passed, 3 skips, **8 deliberate failures**, **0 crash lines** | sim `E3C0710E` (**iOS 26.4.1**) |
| `Himem Watch Watch App` | **34 cases / 6 suites, 0 failed, 0 crash lines** | watch `B17233F6` + paired `74EED5FE` (**watchOS 26.5**) |

The 8 are `SpeechAssetGate`. Membership verified **byte-identical by `diff`** against a set **re-derived mechanically this session** from the 8 gate call sites across 6 files — not inherited from the prior log. **The gate is a count, not a coverage claim:** those 8 legs are the only end-to-end coverage of record → compress → transcribe and none of them ran; this machine reports the en_US speech asset as `unsupported`.

Counts moved **1476/207 → 1491/210** (phone) and **37/8 → 34/6** (watch — a *deliberate reduction*, see Ruling 1). Runtimes held; **no rotation**.

---

## Scope and rulings (all Tom unless stated)

1. **Delete the three watch stub tests; keep the target in the gate.** Baseline becomes 34/6 with every case a real assertion.
2. **The four narrow device items plus rulings 1 and 2 were added to the device pass** — the latter two were ruled sight-unseen on 2026-08-19 and the prior device pass predated them.
3. **B23's memoization: build it.** Taken ahead of the layout flip, which is a written ruling available at any time.
4. **The count finding is verified before the layout ruling**, because it changes which layout option is correct.
5. **On the layout flip: none of the three options. Fix the count defect now; hold the re-partition.** The axis is recorded as wrong-but-stable; re-partitioning is post-tag and starts with the **field** decision, not the layout.
6. **Record the axis finding as its own item** so the next reader inherits the diagnosis rather than only the flag.
7. **Log `PreviouslyConnectedStore` as the fourth prune-rule instance.**

**Options closed (do not re-litigate):**

- **Re-applying `-skip-testing:` to the watch UI test target — rejected.** Its July justification no longer holds (below).
- **Removing the UI test target from the scheme — rejected.** It stays in the gate.
- **All three routes to a `returned` signal — rejected for now.** Enumerated in B27 below; the rejection is the ruling, and each route's cost is recorded so it is not re-derived.
- **Memoizing `composeDrawnBench` as a whole — rejected on mechanism**, not preference: it takes `now:`.

---

## Ruling 1 — the watch gate: a stale exclusion and three tests that could not fail (`0dc8a80`)

**How it surfaced: an inherited number that did not match the tree.** Session-open returned **34/6** against an inherited baseline of **37/8**. Rather than theorise, the target was enumerated: six files, six suites, 8+6+5+2+9+4 = **34** `@Test` functions. **34/6 is mechanically exact for the watch unit target.** The 3-case / 2-suite remainder resolved by arithmetic to `Himem Watch Watch AppUITests`, confirmed by a run without `-skip-testing:` returning exactly 37/8, 0 failed, **zero install-denial signatures**.

**F6c clause 2 is retired, and it was correct when made.** July excluded that target because its runner failed to install on every invocation (`Unknown application display identifier`). Under Xcode 27 / watchOS 26.5 it installs and runs.

**The three cases it contributed were Xcode template scaffolding:** `testExample()` (launches, asserts nothing), `testLaunchPerformance()` (measures), `testLaunch()` (screenshots). All passed unconditionally — the `#expect(true)` shape (F23 T2.5) and the gate-erosion class F6 names.

**A red found by building the ruling.** Deleting both files emptied the target, and **a UI test target with no compiled source builds an `.xctest` with NO EXECUTABLE**; the runner then fails with *"Failed to load the test bundle … its executable couldn't be located"* — a **System Failure at 35/7**: 0 compile errors, 0 crash lines, no assertion. The launch/infrastructure class, identified from the bundle rather than the exit code. So *"delete the three stubs"* and *"keep the target in the gate"* cannot both hold literally. One bare `final class …: XCTestCase {}` is the minimum that keeps the bundle loadable; it carries a doc comment stating that holding the target open is its only job.

**July's 34/6 was 34 real cases plus a *skipped* target. Today's is 34 real cases plus a target that builds, installs and runs with nothing in it.** Same number, different meaning.

---

## The device pass — all six items pass

Build 28 (`v1.0 (28)`), Tom's iPhone `C7830D7E`, fixtures seeded, Tom driving. Cable **in** for items 1–5, **out** for item 6 per the Device Hub protocol.

| # | Item | Result |
|---|---|---|
| 1 | C2 step 3's partition — a photo drawn once, in the right region | **PASS** |
| 2 | B17(a) — a memory made from a proposal arrives untitled | **PASS** |
| 3 | B17(b) — the same fact stated once, not twice | **PASS** |
| 4 | Ruling 1 — a set-aside photo returns to the loose card | **PASS** |
| 5 | Ruling 2 — Delete session takes the photo and note too | **PASS** |
| 6 | The partition's other half — a lone photo lands in the stack | **PASS** |
| — | B18 — chip identity | **PASS** — no `ForEach … occurs multiple times` anywhere in the run |

**B17(a) splits, and half of it was never exercised.** The load-bearing half — *a proposal must not name the memory it becomes* — passed: the committed memory read *"Last look at Harbor Lantern on the way back —…"*, `displayTitle` deriving from the first clip's transcript, **not** the proposal's name. The other half — the card's largest line dropping *"Together at"* — **did not run**, and that was **CC's instruction being wrong**: it aimed at a word-match cluster, but the string is produced only by `proposeTimePlace`, and the fixtures **carry no location at all by design** so that rule structurally cannot fire. Confirmed two ways: the seeder's own doc says so, and every session in the device trace logged `coord=no` with every FORMED proposal tagged `wordMatch`.

**It needs no device pass.** `ProposalNamingTests.aTimePlaceClusterNamesTheWindowWithoutAssertingTheGrouping()` builds a genuine time+place cluster and pins the **literal absence** of "Together at" *and* that `"AM"/"PM"` survives — bounded on both sides, with a self-test that the fixture actually clusters. Composed with the device showing the card drawing `proposedName` verbatim, the item is covered.

**The fixture gap named in the previous log closed by accident.** Setting a photo aside from a cluster produced a **voiceless (media-only) session** — `s0 · clips=0` in `[ClusterTrace]`, B25's own shape, on device for the first time. It reached the proposer **and was not filtered** (ruling 5's guard-not-filter posture, on hardware), and both clusters still FORMED and SURVIVED around it. **Half the gap only:** B25's collapse needed *two* voiceless sessions overwriting one bucket; one is the case the old code got right by coincidence (`0 + 1 == 1`). A two-voiceless-session check was proposed and remains undone.

**Also observed on hardware, and never seen composed before:** the header read *"15 clips · 10 sessions · today, 12:13 PM–9:13 PM"* with observation-shaped eyebrows (*"3 clips from 3 sittings · 30 minutes apart"*) under *"MIGHT GO TOGETHER"* — the J2 / J5 / F37 stack, three separate rulings, drawing correctly together.

**One trace reading left unresolved:** the loose session left the trace at 22:19:06 (`sessions 7 → 6`) and returned at 22:19:36 (`sessions=7`). Tom could not account for it precisely (moving in and out of the drill-in and Recently Deleted around then). **Recorded as observed, unexplained, not contradicted.** The innocent reading is likely and is not claimed.

---

## B23 — the memo (`2d6473f`)

### The inherited target did not reproduce, and the gap is recorded as unexplained

| | Inherited (earlier 2026-08-19) | This run, build 28 |
|---|---|---|
| Regroups in first 2.0 s | 16 | **11** |
| Per regroup | 27.5–92.9 ms | **11.6–20.5 ms** |
| Total | 532 ms | **138.9 ms** |

Bench composition, thermal state and NLTagger warmth are all candidates; none is evidence. **532 ms is not carried forward as a target.** What survives both readings is the redundancy:

```
regroup #1  · 20.5ms · sessions=1 · lens=15 · t+0.09s
…
regroup #11 · 12.2ms · sessions=1 · lens=15 · t+0.24s
```

**Eleven regroups in 0.24 s at an identical bench state** — ten redundant. The shape recurs in use (four inside 70 ms at t+184.2), so it is not launch-only.

**A measurement error caught before it became a finding.** A first pass reported regroups "#1–#12, then #18, #20, #25, #50" and treated #13–#17 as dropped by the console. They were not: `BenchPerf.shouldLog(n) = n <= 20 || n % 25 == 0`, and the apparent gap was a `head`/`tail` framing of the author's own command. The emitter is complete and the stream lost nothing.

### Why only the proposer is memoized

`RenderedBench.compose` takes `now:` and uses it for `stillInPlay` (`now − latest < 10 min`), so the composition **is time-dependent**: a memo over it keyed on data alone would freeze a bench whose window should have expired — a stale-bench defect wearing a performance fix's clothes. `propose` takes **no clock** (`proposeTimePlace` reads each clip's `capturedAt`), so it is a pure function of its inputs.

### The signature is the inputs themselves

`ClipGroup.==` compares `lhs.clips == rhs.clips` — full membership **and** content — and `InboxClip`'s `Equatable` is **synthesized**, with no custom `==` anywhere, so `transcript`, `latitude`, `longitude` and `capturedAt` all participate. **Verified before relying on it:** an id-only equality would have silently frozen the proposals of a clip that had just gained its words, which is routine here.

### Quieting a Busy Path — checked, not assumed

Nothing goes quiet but the proposer. `registerSessionIds()` is called at each trigger site **beside** `regroupSessions()`, not inside it, so it cannot be stranded — the passenger that stopped riding when B15 quieted the retry sweep and left *Select all* inert. `stillInPlay`, `BenchSiblingStackBus`, `siblingStackHasRows` and `[ResolveProbe]` all still run every trigger.

### A trap the fix nearly created itself

On a hit the trace is never written into, and `BenchPerf.clusterTrace` gates on the trace's **signature** — emitting it would have printed `sessions=0 · formed=0` and announced an empty bench. **Two instruments in two days already reported churn they invented** (B21, then the FORMED array a day later); this would have been the third, caused by the fix. The trace now emits only on a miss.

### The first attempt was not a red

A new file for the memo compiled into the test target and was invisible to the app: `cannot find 'BenchProposalMemo' in scope`, 9 compile errors — **proves nothing** (Bug-First step 3). Cause: `MemoryStreamTests`, the watch app and its test targets are `PBXFileSystemSynchronizedRootGroup`s, but **`MemoryStream/MemoryStream/` uses explicit `project.pbxproj` references** (every app source appears 4×). F18's mixed-groups lesson. Reuse-first pointed the same way; the memo lives beside the proposer it wraps. **SourceKit flagged this before the build did** — per Measurement Discipline that class is a symptom, not lag, and it was right.

The real red, hit branch disabled: 0 compile errors, 0 crash lines, `counter.calls → 2` on the money test, `counter.calls → 11` on the launch burst, and a hit returning different proposals from the miss.

---

## THE EIGHTH COUNT — the Clips header counted one of its two regions (`3f4f956`)

**Found by reading the value, not by seeing it on a device.**

`DrawnBench.items` was `loose + clusteredSessions + inFlight`, where `loose` is narrowed by `DrawnBench.from(…, drawsVoicelessSessions: false)` to `.filter(\.hasVoice)`. The **sibling day-grouped stack** — `ClipsTabView.unplacedDayGroupedStack`, fed from `RenderedBench.siblingStackSessions` through `BenchSiblingStackBus` — draws the complement, and **nothing in `items` accounted for it**. So `count`, `capturedAts` (the span) and `sessionTerm` all described the session-card block, while the header they feed sits above **both** regions.

**Measured before the fix: the header said 2 with 4 items drawn** (2 as session cards, 2 in the stack), and `count` was **2** against **3** loose items composed.

This violates the 2026-08-10 lock directly — *"A count must describe the thing it sits on… it must be the number visible beneath it"* — and **`count`'s own doc claimed the opposite**: *"Every item on screen, in any region. One set — so the count, the span and the session term cannot describe different things, which is the identity seven defects violated."* A **phantom comment** in the F23 sense, sitting over a live F37-class defect. It is the **eighth** instance of that class.

**Why nothing caught it.** It requires a voiceless session, which the QA seeder does not produce — the fixture gap the previous log recorded. Every fixture on this surface gives its media a voice clip to sit with, so the second region never existed in a test. The control (`withNoVoicelessSessionTheHeaderIsAlreadyCorrect`) pins that with one region the header was always right: **latent, not always-wrong.**

**The fix: a region, not a set.** `DrawnBench` gained `siblingStack`, the distinction `inFlight` already carried in its own doc (*"a third REGION, not a third SET… a partition of `items`"*). `items`, `count`, `capturedAts`, `drawnSessionCount` and `sessionTerm` all follow from it.

`sessionTerm` needed its own thought: the rule is *"nil when every session is clustered"*, and a stack session is not clustered, so the nil test became `loose.isEmpty && siblingStack.isEmpty`.

**It deliberately does NOT change what the session cards draw.** `SessionListView` still renders `drawn.loose`. Folding the stack into `loose` **is** the layout flip — a *what*, unruled, deferred (B27). The arithmetic now describes the **current** layout honestly rather than quietly assuming a different one.

*Corollary, left in place:* the empty-state gate's own comment says *"Gating on the drawn set is the same fix as the header's: ask the value that knows what is on screen."* It did not know about the stack, which is why `hasSiblingContent || siblingStackHasRows` was OR'd in beside it. That OR is now belt-and-braces rather than load-bearing. Removing it was **not** part of this change.

### M16 — the finding inside the fix

| Mutation | Result |
|---|---|
| M15 · `items` drops the stack again | 2 failed |
| M16 · `sessionTerm` tests `loose` alone | **INITIALLY PASSED** |
| M17 · `siblingStack` always empty | 3 failed |

**M16 left the entire suite green.** `sessionTerm`'s participation of the stack in the nil test was carried by **no test at all** — CLAUDE.md § *Guard the Caller* exactly: the value was right and nothing asked. Without the mutation it would have shipped as an untested invariant looking identical to a tested one.

`aVoicelessSittingBesideAClusterKeepsTheSessionTerm` was added. **Its first fixture failed its own self-test**, and the reason is worth carrying: it passed the proposal only to `DrawnBench.from`, **but `claiming` — which is what moves a session out of `loose` — happens inside `RenderedBench.compose(…, proposals:)`**. So the "clustered" session stayed loose and `#expect(drawn.loose.isEmpty)` correctly refused the fixture. Corrected to pass `proposals:` to `compose`, matching `RenderedBenchTests.theSessionTermDropsWhenEverySessionIsClustered`. M16 re-run: it bites.

### Two tests re-pointed — meaning kept, proxy replaced

`BenchStackPartitionTests.everyLooseItemIsDrawnByExactlyOneSurface` and the money test both expressed their invariants against `drawn.items` **as a stand-in for "the card region"**. That stand-in now means "every item in every region", so the expressions referenced a structure that moved. **The invariants are unchanged** — no item drawn twice; the header counts everything — and are now asserted against the surfaces themselves (`loose + clusteredSessions` vs `siblingStackSessions`). Per § *Assert the Meaning, Not the Phrasing*: the meaning did not move, the proxy did. The partition test also gained an assertion that `DrawnBench.siblingStack` and `RenderedBench.siblingStackSessions` agree, so the value the header counts and the value the view is fed cannot diverge.

---

## B27 — THE BENCH PARTITIONS ON "DID YOU SPEAK", NOT ON NEW-VS-RETURNED

**Recorded, not built. Ruled wrong-but-stable; re-partitioning is post-tag and blocked on a FIELD decision, not on layout.**

P7-1 (July 18 2026) describes the Clips layout as **new/unshaped on top, returned-from-memory below** — *"older, previously-connected-now-loose refs, running back months… Whatever is surfaced as 'to look at' leads the screen."* It exists because the reversed ordering **already shipped once** and buried new arrivals after May 19.

**The implementation is `siblingStackSessions = loose.filter { !$0.hasVoice }`.** That is not new-vs-returned. It is *did the user happen to speak.* A photo captured thirty seconds ago with no voice clip beside it is drawn in the region designed for months-old returned material.

**The evidence is this session's own device pass.** Tom captured a photo with the Clips `+` and it landed in the lower stack. CC called it a pass — **correctly**, because it matches the code. It matched the code and was still wrong. Also in tension with the July 10 FAB lock: *"the new clip drops into the list already in view — recognition, no navigation."*

### Why it is blocked on a field, not on layout

**"Returned" means: has had ≥1 `MemoryClipEdge` at some point, and has 0 now.** The second half is derivable. **The first is not** — edges are deleted and leave no trace. That is why `PreviouslyConnectedStore` exists at all.

**Three routes, all rejected:**

1. **Extend `PreviouslyConnectedStore` to the memory-deletion path.** Cheap, no schema. But it stays **per-device** — a clip returned on the iPad is not "returned" on the phone — and a *layout* axis differing per device is worse than review state, where per-device was explicitly accepted as noise reduction.
2. **A synced `everConnected` / `firstConnectedAt` on `MediaReference`.** Correct cross-device. Costs the Production CloudKit deploy ceremony **and reopens a closed decision**: the last-reference rule's own source says *"Pure edge-count at delete time — no `everConnected`/history field, no deploy."*
3. **Derive it from recycled edges.** Let Go **preserves** edges (`recycledAt` is a soft flag), so a clip whose only edges point at recycled memories *is* distinguishable with no new field. But it misses user-detach, where the edge is genuinely gone. **(3)+(1) is two definitions of one concept — the F6a shape just retired over a week.**

**None of these is a thing to build days before Judi's build.** The honest position is that the axis is wrong-but-stable, recorded as such, and re-partitioning starts with the field decision.

---

## `PreviouslyConnectedStore` — the fourth prune-rule instance

Added to CLAUDE.md's table. A `UserDefaults` `Set<String>` keyed by `MediaReference` id: **two** write sites (both in `EntryLifecycleService.removeClipFromMemory`), **one** read (`ClipsTabView:1828`), and **nothing deletes**. A reused or reseeded id inherits *"was connected"* — verbatim the `BenchClipReviewStore` defect that cost three sessions.

Cosmetic today (one advisory line); it stops being cosmetic the moment anything structural depends on it, which was proposed and declined the same day.

**A second, opposite weakness, recorded so it is not rediscovered:** `record` is **never called on the memory-deletion path** (`recycle(entryId:)`), so a clip returned to the bench by deleting its memory — the largest producer of returned clips — is not marked at all. **Insert-only AND incomplete.**

---

## Retractions

1. **"You drove step 6 with the cable in."** False, and then **the correction was also wrong**: Tom's *"Cable is (and was) out"* was over-read as "out for the whole pass". The actual state is the one originally instructed — **cable in for items 1–5, out for item 6**. The misleading observation was the console still emitting after the cable came out, because `devicectl` was streaming over the network. **Results unaffected; the reasoning was sloppier than the reporting should have been.** Recorded here rather than only in conversation.
2. **"Regroups #13–#17 are missing from the log — the console dropped lines."** False. `BenchPerf.shouldLog(n) = n <= 20 || n % 25 == 0` emits all of #1–#20; the gap was a `head`/`tail` framing of CC's own command. Caught before any conclusion rested on it.
3. **A first mechanical derivation of the `SpeechAssetGate` membership named the suite `DummyError`** — a nested `struct DummyError: Error {}` declared inside a test body, matched by a "last type seen" heuristic. Corrected to top-level declarations before the membership file was used; the final diff was byte-identical to the bundle.
4. **"App terminated due to signal" at session end is not a crash.** Signal **9** (SIGKILL) — the console session being torn down. The whole device log carries **zero** crash signatures under the full multi-phrasing pattern.

---

## What was NOT verified

**This is an absence section. It is the part most expensive to inherit wrong.**

- **B23's benefit is unmeasured.** The memo is proven to skip the call in tests; **what it is worth in milliseconds on hardware has never been measured.** `[BenchPerf] regroup` gained `memo=hit` / `memo=miss · propose=N.Nms` for exactly this, and **no device run has carried them.** A fix with a measured *defect* and an unmeasured *benefit*.
- **The corrected header has not been seen on a device.** The fixtures still cannot produce a voiceless session; reproducing it needs the set-aside done by hand. The tests carry it.
- **B17(a)'s "Together at" half never ran on device** and cannot from this fixture set. Test-pinned only.
- **The two-voiceless-session check was proposed and not done** — B25 is dead in tests and half-demonstrated on device.
- **The watch UI test target's emptiness was not verified across a clean build of fresh DerivedData** — this session's measurement reused the CLI tree. The failure mode if it regresses is the named System Failure, which is loud.
- **`hasSiblingContent || siblingStackHasRows` was not re-examined** after `drawn.count` became authoritative. Left deliberately; it is now redundant rather than wrong.
- **Enumerations trusted rather than re-counted:** none inherited this session. The `SpeechAssetGate` membership (8 sites / 6 files), the watch target's 34 cases, and `PreviouslyConnectedStore`'s 4 references were each swept mechanically **this session**.
- **The 7→6→7 trace reading is unexplained** — see the device pass.

### Guards added, and which were mutation-verified

| Guard | Mutation-verified |
|---|---|
| `BenchProposalMemoTests` (B23 money test + 6 invalidation guards) | **Yes** — M13 fails all five invalidation guards, no collateral |
| `BenchProposalCallerGuardTests` (the bench consults the memo) | **Yes** — M14, with its own scanner self-test still green |
| `BenchHeaderCountTests` (header counts both regions) | **Yes** — M15, M17 |
| `BenchHeaderCountTests.aVoicelessSittingBesideAClusterKeepsTheSessionTerm` | **Yes** — M16, **and it was added BECAUSE M16 initially did not bite** |
| `BenchStackPartitionTests` bus-agreement assertion | **Yes** — M17 |
| The watch UI target's placeholder class | **No** — its absence was observed as a System Failure, which is the same evidence in a different form |

---

## Open threads

- **Measure B23 on device** (`memo=` / `propose=`) — the installed build already reports them.
- **See the corrected header on device** — needs a hand-made voiceless session.
- **The two-voiceless-session check** — one tap, closes B25 on device.
- **B27** — post-tag, starts with the field decision.
- **B26's reconcile** (C-family) with the survivor policy already ruled.
- **C2 step 5** — retires ~59 source-scan assertions; **the gate count will fall while coverage rises**. That figure is **inherited from an earlier log and not re-counted.**
- Carried: B19, B22 ⊘ retired, D1 · D3 · D4 · D7 · F34/C15 · D9b · C1–C15.

## Risks

- **`main` and `f8` are 45 apart.** Pushed, so the exposure is integration, not loss.
- **B24 is fixed in mechanism, not proven in absence.** Zero crash lines across every gate this session is consistent with the fix **and** with the old luck. **A recurrence is a second mechanism, not a failed fix** — compare against the 51-crash bundle rather than re-deriving.
- **`PreviouslyConnectedStore` is insert-only and incomplete.** Harmless while one advisory line reads it.
- **The axis is wrong-but-stable.** It will keep producing individually-correct-looking behaviour that is wrong, exactly as the step-6 pass was.
- Disk fell to **~12 Gi**; bundles cleared at close, back to **20 Gi**. Simulators shut down.
