# Session log · 2026-08-22 · the memo closed, our own root cause disconfirmed, and a phantom over a live defect

Facts only. Immutable. **Written for a context-free reader.** Covers `af94d66..a0fbdb8` (2 commits).

---

## Repo position

- Branch **`f8-overlay-and-wiring`** @ **`a0fbdb8`**, **55 ahead of `main`**, **0 unpushed**.
- **`main` @ `36ce159`** — deliberately behind; every C2 rebuild commit lives on `f8` only.
- Code tree **clean**. `docs/design/` holds Tom's uncommitted work and was not touched.
- **One deliberate tracked artefact, unchanged:** `MemoryStreamTests/DuplicateEdgeConvergenceTests.swift.held` — B26's deferred reconcile, survivor policy complete including the nil-`linkedAt` ruling. Not a pending red.
- **Inherited discrepancy, flagged not acted on:** `docs/session_logs/2026-08-15-to-08-19-the-instrument-and-the-sentinel.md` is **untracked** while the three logs after it are tracked. It has now survived four sessions uncommitted; a `git clean -fd` would take it.

### Gate — both read from result bundles via `scripts/gate-report.sh`, isolated `-derivedDataPath`, `DEVELOPER_DIR` on Xcode-beta, run **sequentially** with the watch pair booted immediately before

| Scheme | Result | Destination |
|---|---|---|
| `MemoryStream` | **1507 cases / 213 suites** — 1496 passed, 3 skips, **8 deliberate failures**, **0 crash lines** | sim `E3C0710E` (**iOS 26.4.1**) |
| `Himem Watch Watch App` | **34 cases / 6 suites, 0 failed, 0 crash lines** | watch `B17233F6` + paired `74EED5FE` (**watchOS 26.5**) |

The 8 are `SpeechAssetGate`, membership **byte-identical by `diff`** against a set **re-derived mechanically this session** from the 8 call sites across 6 files, using top-level type declarations per the 08-19 `DummyError` correction. **The gate is a count, not a coverage claim:** those 8 legs are the only end-to-end coverage of record → compress → transcribe and none ran; this machine reports en_US as `unsupported`.

Session-open gate matched the inherited baseline exactly (**1497/211**, 1486 passed). Counts moved **1497/211 → 1507/213**, and the delta reconciles exactly: 4 `NilAttributeScanTests` + 2 `InaccessibleFaultProbeTests` + 4 new dispatcher tests = **+10 cases, +2 suites**. Runtimes held; **no rotation**.

---

## Scope and rulings (all Tom unless stated)

1. **The declaration fix wins over the call-site fix.** `id`, `mediaType`, `osIdentifier` become optional in Swift to match the `optional="YES"` cells; handle nil at each use. Per *invariants need owners, not conventions* — a call-site fix must be repeated at every site anyone ever adds.
2. **Run the one-shot `id == nil` read**, treating the `isDeleted` half as the load-bearing assumption and verifying it against a running context first.
3. **A recording that found no speech is still her recording and must stay on the bench.** An empty transcript is a fact about the audio, not a reason to drop the clip. `.heardNothing` / *"No words in this recording"* is the honest surface and already exists.
4. **Extended the same principle one step on:** an empty transcript is also not a reason to claim we are still working on it.
5. **The declaration fix is reprioritised to prophylactic, deferred past Judi's build** — after both routes came back unsupported.
6. **Keep the probe committed**, not scratch: a read-only, self-tested, non-trapping scanner is reusable the next time this class surfaces.
7. **`transcriptionAttempted` before Judi's build** — the last item blocking it.

**Options closed (do not re-litigate):**

- **A blanket sweep of the 44 non-optional-over-optional attributes — still rejected.** Unchanged from 2026-08-21.
- **Fixing `syntheticClip` at the call site — superseded** by ruling 1.
- **Treating the empty-transcript disappearance as a defect — withdrawn**, it did not reproduce.

---

## THE HEADLINE — our own 08-21 root cause, disconfirmed by measurement (`09eee1e`)

The 2026-08-21 SIGTRAP commit named the mechanism that made a nil cell reachable:

> `StorageService:165` sets `viewContext.shouldDeleteInaccessibleFaults = true` … **what the flag actually does is mark the object deleted and NIL OUT EVERY PROPERTY.**

That claim rested on Apple's documentation plus one commit message. **No test had ever observed it.** `InaccessibleFaultProbeTests` measures it, on a real SQLite store, in two configurations:

| Scenario | Config | Result |
|---|---|---|
| **A** | flag alone | **Claim holds exactly.** `isDeleted == true`, every property nil |
| **B** | flag **+** `setQueryGenerationFrom(.current)` — *production* | **Claim fails.** `isDeleted == false`, `id` reads back intact |

**`StorageService:165` sets the flag; `:169` pins the query generation four lines later.** With the generation pinned, a row deleted afterwards stays fully readable from the snapshot — the fault never becomes inaccessible, the flag never fires, and no nil-valued object arises. **On the very context that sets the flag, the next line suppresses it.**

**Scenario B's assertion was written to match scenario A and failed. It was not flipped to go green.** The expectation was a hypothesis and the hypothesis was wrong; it now asserts the measured behaviour with the reasoning attached, so a future Apple change is visible rather than silent.

**Substrate was chosen, not defaulted.** `StorageService.init(inMemory:)` sets *neither* flag, and the in-memory store evaluates predicates through Foundation rather than SQL. Faulting is store-level behaviour; an in-memory store cannot answer this.

### THE CAVEAT IS LOAD-BEARING — B IS NARROWED, NOT DEAD

The probe deletes through a **sibling context over one coordinator**. Production deletion arrives by **CloudKit import** through `NSPersistentCloudKitContainer` with `automaticallyMergesChangesFromParent = true`, and **a merge may advance the pinned generation**, restoring exactly the behaviour scenario A shows. **That path was never exercised.** This narrows the question; it does not close it. Written into the test, not only here.

---

## CLEAN IS THE SUBSTANTIVE RESULT — Route A is absent too

`NilAttributeScan` (in `StorageService.swift`) + a `Settings → Debug` button, run on Tom's iPhone against the real store:

```
[HiMem][NilScan] BEGIN · MediaReference=323 MemoryClipEdge=406
[HiMem][NilScan] CLEAN — no nil cell in any scanned attribute.
[HiMem][NilScan] END
```

**Four runs, byte-identical, zero `FETCH-FAILED`.** 323 refs against a ~35-clip bench — a genuine whole-store enumeration, not a bench-scoped one. Six attributes: `MediaReference.{id, mediaType, osIdentifier}` (the declaration-fix targets) plus `MemoryClipEdge.{id, clipId, memoryId}` (read at `EntryLifecycleService:849` and `:1136` through relationship traversal, which no predicate protects).

**Three properties that make the reading mean something:**

- **It cannot trap while asking.** Every read goes through `value(forKey:)`, never a generated accessor — the generated accessor *is* the trap.
- **Fresh background context**, carrying no pinned generation, so it reports what the store holds *now* rather than what `viewContext`'s snapshot held. That distinction is the subject of the probe above.
- **A failed fetch writes `<entity>.<attribute> FETCH-FAILED` into the totals** rather than skipping, so *"could not look"* and *"looked and found nothing"* cannot render identically. None appeared, which is the coverage proof.

**Self-tested, because CLEAN was the likely answer.** A scanner reporting CLEAN by failing to look is the `head -8` shape twice over. Four guards: plant the exact offender and assert it is found **with the Route A signature** (nil in one attribute, neighbours intact, `isDeleted == false`); a control proving a well-formed store reads CLEAN so a hit carries information; the other two attributes covered; and a coverage assertion that fails if a target is dropped. All against the **SQLite** container — `id == nil` is a NULL predicate and the in-memory store's NULL semantics differ, so a green there would have proven nothing.

**A gap closed after the reading:** `BEGIN` now names the scanned attributes, so a CLEAN verdict is auditable from the artifact instead of from trust in a constant.

### WHERE THIS LEAVES THE TRAP

**Observed, mechanically unexplained.** Route B disconfirmed by the query-generation pin; Route A absent by whole-store enumeration. **The declaration fix becomes hardening rather than closing**, and is deferred past Judi's build. Measured blast radius, for whoever picks it up: **53 compiler diagnostics across 15 files** in the app target with the test target not yet reached — **~44 of them `id`**, which has no possible default, and ~10 `mediaType`/`osIdentifier`, whose model defaults (`"image"`, `""`) define the answer.

---

## THE PHANTOM OVER A LIVE DEFECT (`a0fbdb8`)

`PhoneCaptureBenchDispatcher` derived two fields from the transcript at **both** voice sites (`:57`/`:59` and `:89`/`:91`):

```swift
transcriptionAttempted: !transcript.isEmpty,
status: transcript.isEmpty ? .received : .transcribed
```

`InboxClip.transcriptionAttempted`'s own doc, four files away:

> *True after the iPhone-side speech recognizer has run for this clip, **even if it returned no text**. Combined with `transcript.isEmpty` this distinguishes "still in flight" from "ran, found no speech".*

**Both sites wrote `false` in exactly the case the field exists to record as `true`** — a phantom comment stating the invariant directly above code doing the reverse, the F23 class.

**Not cosmetic.** `ClipGroup.accidentalClips` requires `transcript.isEmpty && transcriptionAttempted`, so a no-speech phone clip could **never** be accidental: it never reached `.allAccidental`, never rendered *"N clips auto-excluded · no speech"*, and `collapsedBodyVariant` reported **`.transcribing`**. A finished recording presented as one still being worked on, indefinitely.

**The inference behind the fix is a precondition, not a guess.** `SpeechService.startRecording` returns early — no recording, no file — unless `isAuthorized` **and** the analyzer, transcriber and format are prepared, and phone capture transcribes live. So a `.voice`/`.voiceSession` item reaching the dispatcher has always been through the recogniser. Guarded by `theDispatcherOnlyReceivesPostRecognizerItems`, a source walk that fails if a dispatch appears outside the two post-recording call sites and **throws if the walk reaches no source** rather than passing by matching nothing.

**Red identified, not assumed.** Exit 65 with **0** on the format-independent compile detector and **0** crash lines: three named assertion failures at the expected assertions with the expected values — `transcriptionAttempted → false`, `status → .received`, `collapsedBodyVariant → .transcribing`, `accidentalClips.count → 0`.

**Twin-site mutation coverage is what makes the F6a failure impossible here:**

| Mutation | Result |
|---|---|
| M1 · restore the `.voice` derivation | the two `.voice` tests fail; the roll test does **not** |
| M2 · restore the `.voiceSession` derivation | **only** the roll test fails |

Each site independently covered, so fixing one and leaving its twin cannot pass a green gate.

**It was found while reproducing something else** — the empty-transcript bench reproduction, which did not reproduce.

---

## The device work

Build `v1.0 (28)`, stamps `2026-08-22 09:31:40` then `20:17:10`, both **read off the device** and matched against the Mac-side executable mtime.

### ① The memo invalidation — CLOSED, three independent times

The 08-21 log recorded this as the last unexercised path in B23: *"a memo that never invalidates would produce a trace identical to tonight's."*

| Capture | Dispatcher → next regroup | Result |
|---|---|---|
| `BB1BE7EE` (silent) | 27 ms | `lens` 2→3, `memo=miss · propose=0.6ms` |
| `59997C5C` (silent) | 22 ms | `lens` 2→3, `memo=miss · propose=0.6ms` |
| `70D94995` (**healthy**, `in_peak 0.052`, 45.9× compression, real transcript) | 23 ms | `lens` 3→4, `memo=miss · propose=1.0ms`, after **six consecutive `memo=hit`** on an unchanged bench |
| `00258847` (room tone, no words) | 26 ms | `lens` 5→6, `memo=miss · propose=1.1ms` |

**The six-hits-then-miss sequence is the discriminating reading:** a memo wired to nothing could not hit six times; a memo that never invalidates could not miss on the seventh.

**The silent captures remain valid for this question and only this one.** The memo's key is `[ClipGroup]` membership — a silent clip still changes it. They are worthless for any audio claim.

### The empty-transcript reproduction — NOT REPRODUCED

`00258847`, ~21 s, room tone, no words. `lens` 5→6 and `clips` 34→35, **still up at `body #175`, 78 seconds later**, zero manifest removals beyond the one at launch, and confirmed on screen showing *(no transcript)*. **The shipped behaviour already satisfies ruling 3.**

Ruling 3 also turned out **not** to reverse an existing *what*: `accidentalClips` classifies such a clip as *accidental*, but every caller is display or default-selection (`SessionListView:1744` renders the auto-excluded line, `:1836` drops it from the default selection, `:1402` notes *"user can opt them in by tapping"*) — **never membership**. A hypothesis that it removed the clip from the bench was formed and killed by reading the callers before acting on it.

### Run 1's disappearing clips — observed, unexplained, not contradicted

Three captures in ~40 s produced `clips` 31 → 32 → 31 → 32: net **+1 from three captures**. Manifest removal **is** instrumented (`[Inbox] remove(clipId:)` / `removeBatch`) and **no such line fired**. Tom took no action on those clips. **Two clean runs since have not repeated it**, and three variables moved at once in run 1 (silence, rapid succession, Device Hub churn — 20 ubiquity sweep re-entries vs 6). **No fix on a hypothesis.**

### ④ out-of-range — STILL NEVER RUN, and the instrument choice is the finding

Tom walked the watch out of range. The console captured nothing: `scenePhase → inactive` at 10:20:37, `→ background` at 10:20:38, then silence, and the phone disconnected.

**A foreground console bridge cannot observe a test that requires the phone to sit unattended, because that is exactly when iOS stops the app logging.** The instrument was chosen for the wrong test. Next attempt: the device's **persistent log store** (`sysdiagnose`), plus the bench state, not a live stream. Carried since the F6 stretch; still the one hardware-only check never exercised.

---

## Retractions and instrument faults — seven, all mine

**Six caught before a conclusion rested on them; one cost real time.**

1. **A by-file error table** from a pattern matching a compiler command line that starts with `/` and ends in `.swift`. Produced a clean, plausible, fictitious distribution naming files that do not touch `MediaReference`.
2. **`size=18`** read off a `cut -c1-200` truncation of my own command; the real value was `size=1808896`.
3. **`inbox=false` read as "ref-backed."** It is a `fileExists` check on the Inbox directory path. Reading the emitter showed phone voice goes to `inbox.acceptClip` — **manifest-backed** — which *strengthened* the run-1 evidence rather than weakening it, since manifest removal is instrumented.
4. **"9 errors"** from `grep -cE ': error: '` that counted **CoreData runtime log lines**. There were zero compile errors and the tests had run.
5. **"`--console` attaches to an already-running app."** It does not — `CoreDeviceError 10002 / EINVAL`. Inferred from the help text's *"If the app is not already running…"*. **The fallback to `--terminate-existing` killed the running HiMem mid-test**, and it could not relaunch because the phone had auto-locked. **This one cost time and an in-progress capture.**
6. **`timeout 45 xcodebuild …`** — `timeout` is not installed on this machine, so the check never executed and `rc=0` was the echo's. **08-21 fault #8 reproduced verbatim, by me, one day later.**
7. **`Invalid argument` read as a device fault.** 114 launch retries in a few minutes wedged CoreDevice and **degraded Apple's own error from a precise `Locked` to a bare `EINVAL`**. Three rounds went to treating it as the device's problem while the retry loop I had armed was the nearest antecedent. Stopping and waiting ten seconds fixed it. *The enumerate-your-own-actions procedure exists for exactly this and was not run.*

**Same family as 08-21's taxonomy: a check against an artifact I had not read, returning a well-formed answer.** #7 adds a new sub-shape worth naming: **a diagnostic can be degraded by the volume of your own retries**, so the first error in a retry series is the informative one and the rest are noise wearing its clothes.

---

## What was NOT verified

**This is an absence section. It is the part most expensive to inherit wrong.**

- **Both commits were gated over the COMBINED tree, not per commit** — the same gap the 2026-08-21 log recorded for `e5f52be`…`94f5dc8`. Both changes are additive and independent, and M1/M2 exercised the dispatcher fix in isolation, but the gate itself did not.
- **The CloudKit-merge path was never exercised.** Route B is narrowed, not dead.
- **④ has never run** on any surface and cannot run on a simulator.
- **Run 1's `clips` 32→31 is undiagnosed.**
- **The live-analyzer premise under the `transcriptionAttempted` fix is a code read, not a measurement** — no `[Transcri…]` / `done segments` line appeared anywhere this session. The source walk guards the call sites; it does not observe the recogniser.
- **The declaration fix's 53-diagnostic count is a floor** — the test target never compiled during that probe.
- **`NilAttributeScan`'s CLEAN is one device, one store, one moment.** It says nothing about Judi's device or about a store that has since imported from CloudKit.
- **The corrected `NilScan` BEGIN line has not been run on device** — the scope-naming change landed after the four readings.
- **Enumerations trusted rather than re-counted:** none inherited. The `SpeechAssetGate` membership, the 9 `MediaReference` insertion sites, the dispatcher call sites and the six scan targets were each swept mechanically this session.

---

## Open threads

- **④ out-of-range** — persistent log store, not a bridge.
- **The declaration fix** — hardening, post-Judi. 53+ diagnostics, 15 files, ~44 of them `id` with no possible default.
- **Run 1's disappearing clips** — observed, unexplained.
- **B26's reconcile** (C-family), survivor policy complete including nil-`linkedAt`.
- **B27's partition axis** — post-tag, blocked on the field decision.
- **The layout flip** — a *what*, unruled.
- **C2 step 5** — retires ~59 source-scan assertions; **that figure is still inherited and not re-counted.**
- Carried: B19, B22 ⊘ retired, D1 · D3 · D4 · D7 · F34/C15 · D9b · C1–C15.

## Risks

- **`main` and `f8` are 55 apart.** Pushed, so the exposure is integration, not loss.
- **The 08-21 trap has no demonstrated mechanism.** It happened twice on hardware and both named routes are now unsupported. Something produced that nil.
- **B24 may recur.** If it does, it is a second mechanism, not that fix failing.
- **The 08-15→08-19 session log is still untracked** and would be lost to `git clean -fd`.
- Disk 17 Gi free at close; simulators shut down, bundles and DerivedData cleared, console bridge terminated.
