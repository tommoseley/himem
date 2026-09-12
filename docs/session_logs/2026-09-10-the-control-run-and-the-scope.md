# Session log · 2026-09-10 → 09-11 · the control run, the decoupled observer, and a query pointed at the complement

Facts only. Immutable. **Written for a context-free reader.** Covers `bb95bed..cdf7378` (4 commits).

---

## Repo position

- Branch **`f8-overlay-and-wiring`** @ **`cdf7378`**, **78 ahead of `main`**, **0 behind**, **0 unpushed**.
- **`main` @ `36ce159`** — deliberately behind; every C2 rebuild commit lives on `f8` only.
- Code tree **clean**. `docs/design/` holds Tom's uncommitted work (6 modified, 10 untracked); CC edited exactly one file there under direction — the Rule 4 supersession in `HiMem · Memory canvas.html` — and left it **unstaged**, per the standing rule that the directory is Tom's.
- **One deliberate tracked artefact, unchanged:** `MemoryStreamTests/DuplicateEdgeConvergenceTests.swift.held` — B26's deferred reconcile. `.held` so it never compiles. Not a pending red.

### Gate — both read from result bundles via `scripts/gate-report.sh`, isolated `-derivedDataPath`, `DEVELOPER_DIR` on Xcode-beta, run **sequentially** with the watch pair booted immediately before

| Scheme | Result | Destination |
|---|---|---|
| `MemoryStream` | **1537 cases / 216 suites** — 1526 passed, 3 skipped, **8 deliberate failures**, **0 crash lines** | sim `E3C0710E` (**iOS 26.4.1**) |
| `Himem Watch Watch App` | **34 cases / 6 suites, 0 failed, 0 crash lines, 0 install failures** | watch `B17233F6` + paired `74EED5FE` (**watchOS 26.5**) |

Phone exited **65**, identified before being read: 0 build failures, 0 compile errors, 0 launch-denial signatures, 0 `ValidateEmbeddedBinary` platform errors, `Test run with` present ⇒ **assertion failure**, the only one of the five meanings that is a red.

The 8 are `SpeechAssetGate`. **The gate is a count, not a coverage claim** — those 8 legs are the only end-to-end coverage of record → compress → transcribe, and **none of them ran**; this machine reports the en_US speech asset as `unsupported` on the pinned 26.4.1 runtime.

**Counts moved 1517/214 → 1537/216**, and every step reconciled against a prediction made before the run: **+13** (observer suite), **+3** (ordering), **+4** (B29). Runtimes held; **no rotation**.

Toolchain unchanged: **Xcode 27.0 / `27A5237l`**, iOS SDK `24A5408c`, simulator runtimes **iOS 26.4.1 (`23E254a`)** and **watchOS 26.5 (`23T570`)**.

---

## THE HEADLINE — the watch gate is restored, and the cause is unestablished

The watch test-runner install had failed **five consecutive times** since 08-25, blocking every paired gate: `Failed to install or launch the test runner (Invalid device state)` with `Mach error -308 — (ipc/mig) server died` from `installApplication`, at the `Testing started` boundary.

### The artifact nobody had read

**`~/Library/Logs/CoreSimulator/CoreSimulator.log`** — 28,951 lines spanning **Aug 4 → today**, so it covers every green run *and* every failure. It had never been opened in any prior session.

It showed the `-308`s attached to **clone** devices, not the pinned ones:

```
Error setting IDS relay active for gizmo:
  Clone 1 of Apple Watch Series 11 (46mm) (ED836A6A…, watchOS 26.5, Shutting Down)
  — NSMachErrorDomain Code=-308 "(ipc/mig) server died"
```

And the schemes carry an exact asymmetry:

| Scheme | Testables | `parallelizable` | `Clone N of <its own device>` in 28,951 lines |
|---|---|---|---|
| `MemoryStream` (phone — installs fine) | 1 | *absent* → NO | **0** |
| `Himem Watch Watch App` (failing) | 2 | **`YES` on both** | watch ×4 + paired iPhone ×4 per run |

### THE CONTROL DISCONFIRMED IT

| Run | Variable | Result (from the bundle) |
|---|---|---|
| Discriminator | `-parallel-testing-enabled **NO**` | 34 / 6, 0 failed, runner installed |
| **Control** | `-parallel-testing-enabled **YES**`, clones demonstrably in use | **34 / 6, 0 failed, runner installed** |

**The clone path is exonerated.** The asymmetry is real and is **not** the mechanism. It explained *why the two gates differ*, which was then mistaken for *why one of them failed*.

### What actually moved: the environment — a candidate, not a finding

```
08-25 09:30 local   first runner-install failure
08-26 19:00         last commit of the failing session
08-26 21:34         macOS update      ← 2h34m later
09-03 22:28         reboot
09-03 22:29         macOS update
```

macOS `26A5388g` → **`26A5425a`** (the archives on record carry the former). **This is not attributable**, because the failure no longer reproduces and there is nothing to run a control against. It is recorded as a candidate and nothing more.

### Two of the three inherited eliminations did not eliminate

True independent of how the clone question resolved:

- *"not stale device state — an in-place erase of both halves didn't help"* — erasing the **pinned** devices cannot affect **clones**, which are minted fresh every run.
- *"a watch simulator boots and survives fine alone"* — booting a device directly never creates a clone.

Both statements were accurate about what they did; **neither reached the hypothesis it was taken to close.** Only *not disk* and *not the code* survive.

### The honest close

**Restored, cause unestablished. Intermittent-and-currently-absent is not fixed.** If it returns it is the same unexplained thing, not a regression, and `CoreSimulator.log` is where it gets read first — the log persists for weeks and will still hold the window.

Two further facts from that log, worth inheriting: **`installApplication` appears 0 times in it** (the failing call is not recorded there), and the **crash reports for 08-25 have aged out** — `DiagnosticReports` now retains only Sep 8–10 — so the process that "died" cannot be named retrospectively.

---

## GOVERNANCE — a single-variable intervention needs its control (`c04061c`)

Added to `CLAUDE.md` as a Mandatory section, sibling to *Don't Go Looking for Zebras*: that rule governs **where to look first**; this one governs **how to confirm what you found**.

> **Changing one variable and seeing the symptom go is not evidence that the variable was the cause. It is evidence that the symptom is gone.** Before naming a variable as the cause, run the control: put the variable back and see whether the symptom returns.

- **The confound is usually TIME, and it is invisible because nothing in the report names it.** State the gap's length and its contents next to the result.
- **A green run answers "does it pass now?", never "was my hypothesis right?"** — the fifth measurement class, one turn after it was written up.
- **Where the control is cheap, it is not optional.** One extra invocation is the whole cost.

### The counterfactual is why it is a rule

Without the control, **`-parallel-testing-enabled NO` would have shipped.** It would have **passed forever**, **taken credit for the repair**, **silently slowed every watch gate**, and **carried a fabricated origin story in its commit message** — while the real cause stayed unnamed and free to return. *A fix that works for the wrong reason is indistinguishable from a fix that works, until the real cause returns.*

Finding a true difference between a working case and a failing one is not the same as finding the cause, and the distance between those two is one invocation.

### Secondary shape, recorded in its literal form

**An experiment that cannot reach the thing it exonerates.** Per the two eliminations above: **state an elimination's REACH, not just its result** — *what would this experiment have done if the hypothesis were true?* An elimination that could not have failed has eliminated nothing.

---

## THE PATTERN IN CC'S OWN WORK THIS SESSION — three mechanisms, two wrong

Each time: a mechanism was formed, **real supporting structure was found**, and the mechanism was then tested rather than believed.

| # | Mechanism | Supporting structure (all real) | Outcome |
|---|---|---|---|
| 1 | Clones cause the runner-install failure | The scheme asymmetry; `-308`s on clones; `Clone N of iPhone 17 Pro` zero times ever | **WRONG** — killed by the control |
| 2 | Stale DerivedData causes `Unable to resolve module dependency` | A `build` then `test` across a pbxproj change in one tree | **WRONG** — reproduced identically in a fresh tree |
| 3 | The watcher's scope excludes the files (B29) | SDK header defining the two scopes as complements; `documentsRoot` = `container/Documents` | **SURVIVED** |

**(2) is the sharper lesson.** The theory was formed *before reading the error text*. The text named the real cause immediately: the module is **`HiMem`**, not `MemoryStream` — 208 test files say so and exactly one said otherwise, and that one was CC's, written from memory instead of copied from its neighbours. Same shape as `AuthService.updateUserName` on 08-26. Cost two invocations.

**(3) is stronger than (1) was, and for a nameable reason:** clones were *a real difference mistaken for a cause*; the scope is *a mismatch between where files provably are and where the query provably looks*, read from the SDK header rather than recalled. **The control discipline was applied to it anyway** — it explains the symptom, and the control is unrunnable — which is the right posture even when the evidence is better.

---

## The work

### `ef41a91` · `CloudKitArcLog` — the instrument must outlive the latch

Reading #2 has been void three times, and **two of the three reasons were `FirstImportState` owning the only observer.** It is one observer lifetime serving two jobs whose deadlines point in opposite directions:

| | Job | Correct deadline |
|---|---|---|
| `FirstImportState` | decide when a surface may claim to be empty | **as early as honestly possible** |
| the arc | make the ~17–21s per-zone setup floor visible | **after the quantity elapses** |

`markComplete` calls `removeObserver` — right for its own job. But its 3s fallback fired at **+3149ms** on 08-25, took the observer with it ~15s before CloudKit's setup event, and the archive carried **zero** `ck event` lines. Silence-because-we-stopped-listening is byte-identical to silence-because-no-import-started.

**The conflict is structural, not a tuning problem.** Lengthening the timeout would damage the guarantee the timeout exists to provide (`FirstImportState`: *"The fallback is not optional"*). One lifetime cannot satisfy both deadlines, so there are two.

By construction the arc **never removes its observer** (no teardown path exists), **never latches**, and **never reads `FirstImportState`** — in particular it does not inherit `guard phase == .importing`, so it speaks on the **relaunch** branch, which is reading #2's second void and the branch a populated account actually takes.

**No settle flag, deliberately** — the arc ends when events stop, and a reader can see that.

### `ebaa10b` · One owner for a memory's part order

A memory's part order is owned by `MemoryClipEdge.orderInMemory`: `edgesArray` sorts by it, `mediaReferencesArray` inherits, `EntryMapper` carries it into `mediaItems`, and `EvidenceEdgeReadWriteTests` pins that reads *"respect each memory's per-edge `orderInMemory` — **not** `ref.createdAt`"*.

**Both renderers then threw it away and re-sorted by `createdAt`** — `compactItems` (Compact index) and `panels` (Full stream). Twin sites, one of them `private`, and only one had a test suite.

**Live consequence:** the write side appends, so adding an older clip to a memory puts it last — and the renderer moved it to the *top* by capture date. **"Append" was unobservable.**

Fixed with an owner, `orderedItems(from:)`, not by deleting two `sorted` calls: two call sites each deciding order independently is how they diverged.

**Reverses `sortsByCreatedAtAscending`, and that is stated rather than implied.** Ruled a coherence fix on the evidence that `Memory Detail · long-memory navigation.md` describes Compact as a table of contents and is **silent on ordering** — so the sort was implementation, not a decided *what*. **Both renderers moved together** (Tom, approved): fixing only `panels` would leave Full and Compact describing one memory in two orders, which is the class the change closes.

**Risk checked, not assumed:** the attribute, the single edge-creation site, and the line that sets it all landed in `7694361` (2026-07-11), and that site is the **only** writer — so there is **no legacy `orderInMemory = 0` population**.

### `cdf7378` · B29 — the watcher was scanning the container's complement

From the SDK header, read rather than recalled:

```
NSMetadataQueryUbiquitousDocumentsScope  "The Documents subdirectory in the
                                          application's Ubiquity container."
NSMetadataQueryUbiquitousDataScope       "The application's Ubiquity container,
                                          EXCLUDING the Documents subdirectory."
```

`awaitDownloads` armed its `NSMetadataQuery` on the **Data** scope while `UbiquityStore.documentsRoot` is `container/Documents` and the audio waits at `Documents/Inbox/`. **The two scopes are complements**, so the query was pointed at the one part of the container that by definition contains none of our files. It could never match ⇒ `NSMetadataQueryDidUpdate` could never fire ⇒ B15's *"a file's arrival is an EVENT, not a poll"* had no event. The clips rode on unrelated captures because an unrelated capture was the only thing left that re-entered the sweep.

**The fix is an owner, not a constant.** `UbiquityStore.metadataSearchScope` sits beside `documentsRoot`, because the scope is a fact *about* the layout. The guard asserts the **correspondence** — the scope must be the Documents scope **and** `documentsRoot` must end in `"Documents"` — so moving the layout fails the test.

**Why a config-invariant test:** exercising the resumption needs a real iCloud download on hardware; B15 recorded that as unreachable from the simulator suite and it still is. Same trade as `WatchAudioSessionConfigTests`.

---

## Decisions and rulings (all Tom unless stated)

1. **Run the discriminator** — one bounded invocation with a changed variable, read from the result bundle. Either outcome worth the command.
2. **Record both governance shapes, today's as primary**, with the counterfactual; the erase instance keeps its literal form as secondary.
3. **Build the second observer** — log-only, never latches, never removes itself.
4. **Rule 4 of the memory canvas supersedes "derived content never demotes primary media" — on that surface only.** The lock protects a *consumption* surface where the recording is the artifact; the canvas is an *authoring* surface where dictation is a way of writing, the words are the product, and the audio is provenance. It stays playable and never disappears. **Memory Detail's read view keeps the original rule.** Written into `HiMem · Memory canvas.html`.
5. **Take the `orderInMemory` renderer defect now, separately** — worth fixing whether or not the canvas is ever scheduled. Both renderer moves **approved, not vetoed**.
6. **Canvas sequencing: not now.** C-family scale on the same file that is already the `f8 → main` conflict-watch surface at 78 commits apart. It waits behind the gate, the observer, and B29.
7. **Ship B29 with the config-invariant guard**, device gap stated. **B29 stays open** until the hardware reading.
8. **`ChronologicalCaptureStream` is a misnomer — logged at the owner, not renamed.** Renaming touches explicit `project.pbxproj` references (the F18 `git mv` lesson); same trade as the `BenchSiblingStackBus` file-name residue.

**Options closed (do not re-litigate):**

- **`-parallel-testing-enabled NO` as a fix — rejected on evidence.** The control disconfirmed the hypothesis it rested on. Re-applying it would slow every watch gate for nothing.
- **Lengthening `FirstImportState`'s 3s timeout to serve the instrument — rejected on mechanism.** It damages the guarantee the timeout exists to provide.
- **Deleting the two `sorted` calls without an owner — rejected.** Two call sites deciding order independently is the cause, not the symptom.

---

## The memory canvas — scope reported, nothing built

Read and costed against the code (Tom's instruction: report, build nothing).

**What it locks:** a memory is something you keep adding to; four always-visible tools (pen · camera · mic · paperclip), no `+`, no declared object types; the paperclip surfaces a queued Watch recording as *"From your Watch · 6:58 PM"*, never as a Clip; a dictated passage **is** writing with the audio underneath; no time gutter, no placeholder; a memory may stay tiny.

**The cost, measured rather than estimated:**

1. **The ordering already exists** — `orderInMemory` is shipped, CloudKit-synced, per-memory. **Insert-at-caret needs no schema change and no Production deploy.** (The renderer defect that blocked it was fixed this session; insertion still needs a renumber, since writers append only.)
2. **`ChronologicalCaptureStream` (672 lines) is replaced, not amended** — it is a block-list renderer, which Rule 7 names as the rejected v1. Downstream: the Compact accordion and `Memory Detail · long-memory navigation.md`.
3. **`EntryExpandedView` (1,844 lines) keeps its frame, loses its middle** — `bodyContent` is one branch. But the canvas's *Done* + "Saved" bar implies an always-editable document, where the locked model is *text = tap to edit, media = tap to consume*. A real interaction question, not plumbing.
4. **The append composer barely moves** — `AppendFAB` (285) + `CaptureFlowHost` (243) + `EntryAppendCoordinator` (114) already drive `CaptureModality.stackOrder`, which owns `sfSymbol` and `color`. Per B31, drive the bar off `stackOrder`, never off the canvas SVGs.
5. **The paperclip is the one genuinely new capability** — a picker over zero-edge `MediaReference`s, presented by origin.

---

## Retractions and corrections

1. **"The clone path is the cause of the watch-gate failure."** Disconfirmed by the control run in the same session, before anything rested on it. **Propagation: none** — no commit, file, or ruling carried it; `c04061c` records the disconfirmation as its subject.
2. **"Stale DerivedData causes the module-resolution error."** False — reproduced identically in a fresh tree. The cause was CC's own `@testable import MemoryStream` (the target name) where the module is **`HiMem`**. Theory formed **before reading the error text**.
3. **"Five of the twelve observer tests are contract tests."** **Wrong in both numerator and denominator, and it was repeated back in the close instruction — correcting it here.** The observer suite is **13 cases**: **one** genuine red (`theLaunchPathArmsTheArc`, verified failing on shipped source at the named assertion with `sites → []`) and **twelve** contract tests. The B29 suite is **4 cases**: one genuine red (`theDownloadWatcherUsesTheOwnedScope`), three contract. Corrected figures are in *What was NOT verified* below.
4. **A Swift Testing expression tree rendered a negated `contains` confusingly** during B29's red — `!code.contains(…) → true` printed beneath an "Expectation failed" header. Settled by the artifact (`grep` confirming the literal at `WatchSessionDelegate:557`), not by the rendering. No conclusion rested on the misread.

---

## What was NOT verified

**This is an absence section. It is the part most expensive to inherit wrong.**

- **NOTHING FROM THIS SESSION IS DEVICE-VERIFIED.** Four items were *found* on hardware — the watch-gate failure, reading #2's void, the ordering defect's consequence, B29's stranded clips — and **all four fixes are simulator-only**.
- **B29 is fixed in scope and OPEN in fact.** The guard proves the query is pointed at the right scope. It does **not** prove the resumption fires. **Close condition: `ubiquity update — re-entering sweep` observed on hardware** — unobtainable from a simulator by B15's own recorded finding.
- **The arc has never logged a real CloudKit event.** Every test drives `record(...)` directly, because `NSPersistentCloudKitContainer.Event` has no public initialiser and the notification payload cannot be synthesised. **The three-line notification adapter is the one part outside the seam**; `theLaunchPathArmsTheArc` guards that `begin` is called, not that an event arrives.
- **The floor itself has still never been measured on this device.** The observer exists to make it visible; it has not yet been read.
- **Contract-test ratio, corrected:** observer **12 of 13**; B29 **3 of 4**; ordering **5 of 7** (two were verified red — `preservesEdgeOrderWhenCaptureTimeDisagrees` and `fullAndCompactAgreeOnOrder`; the source guard `noRendererReSortsTheMemorysParts` was written **after** the fix and is mutation-verified only). **Mutation verification is a substitute for a red-first cycle, not a replacement for one.**
- **Mutation-verified this session (9, each with 0 compile errors and 0 launch denials, each biting only its named guard):** M1–M5 (observer: phase-guard re-coupling, teardown, elapsed origin, start/ended collapse, unknown-type rendering); M6–M7 (ordering: the **private** `panels` site, `compactItems` revert); M8–M9 (B29: caller reverts to the literal, owner holds the wrong scope). **M6 is the load-bearing one** — it proves the source guard reaches a private site no behavioural test can.
- **`theCouplingScannerDependsOnStrippingComments` was added because M2 exposed a gap**, not designed in: the coupling guard passes *only* because it strips comments, since the class doc names `removeObserver`/`markComplete`/`FirstImportState` in prose.
- **The watch-gate cause is unestablished, and the macOS candidate is untestable** — the failure does not reproduce, so no control can be run against it.
- **`-parallel-testing-enabled` was not left set anywhere.** Both runs were one-off invocations; the schemes are unmodified.
- **One run this session was discarded as NOT A RED** — exit 65, 0 compile errors, no `Test run with`, `SBMainWorkspace` "Busy (Application failed preflight checks)". It cleared after `simctl shutdown all` ⇒ busy state, device not spent.
- **Enumerations swept mechanically this session:** `SpeechAssetGate` membership (8 call sites / 6 files, re-derived, diffed byte-identical); the `MemoryClipEdge` creation sites (1) and `orderInMemory` writers (1), with their introduction dated via `git log -S`; the two ubiquity scope definitions, read from the iPhoneSimulator27.0 SDK header; clone-creation and `-308` events per day across all 28,951 CoreSimulator.log lines. **Trusted rather than re-counted:** C2 step 5's *"~59 source-scan assertions"*, still inherited from an earlier log and still not verified.
- **The Rule 4 supersession has not been read cold.** It is design copy written by CC under Tom's ruling, in Tom's directory, and has had no review pass.

---

## Open threads

- **ONE WIPED-INSTALL PASS NOW ANSWERS READING #2 AND B29 TOGETHER.** That was not true at this session's start: before the decoupled observer, the arc self-terminated at +3s and could not report the floor at all. Both now need the same thing — a device, a fresh install, and the persistent log store (**not** a console bridge, per 08-22). Watch for `[HiMem][CKArc] setup ended ok +…ms` and `ubiquity update — re-entering sweep`.
- **The watch gate may fail again.** If it does it is the same unexplained thing, not a regression. Read `~/Library/Logs/CoreSimulator/CoreSimulator.log` first — it reaches back weeks and is now a known artifact.
- **The memory canvas** — scoped, not sequenced. Waits behind the current queue; C-family scale.
- **④ out-of-range** — the delivered-awaiting-ack gate has never been exercised; no dedup branch has ever fired.
- Carried: **B26's reconcile** (held, survivor policy complete) · **B27's partition axis** (post-tag, blocked on the field decision) · **B30** · the layout flip (a *what*, unruled) · **C2 step 5** · **C1/C8** · **D1** (App Store submission still needs a real Xcode RC — no beta solves it) · D3 · D4 · D7 · D9b · F34/C15 · B19 · C1–C15.

## Risks

- **`main` and `f8` are 78 apart.** Pushed, so the exposure is integration, not loss. `ClipsTabView.swift` and `EntryExpandedView.swift` remain the conflict-watch files; **`ChronologicalCaptureStream.swift` joins them** as of this session.
- **The watch gate's health is not understood**, only currently good.
- **B24 may recur.** If it does, it is a second mechanism, not that fix failing.
- **The 8 red legs still read as a regression** to anyone who skips the qualification.
- Disk fell to **14 Gi** mid-session (exit-73 range) and was cleared back up; result bundles and all isolated DerivedData removed at close, simulators shut down.
