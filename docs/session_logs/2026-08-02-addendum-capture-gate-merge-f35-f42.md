# Session log · 2026-08-02 (addendum) · capture gate · f8→main merge · F35–F42

Facts only. Immutable. **Written for a context-free reader.** Covers `2f4d690..89e77df` — everything after the 2026-08-02 device-pass log, which closed at `2d7e834` (its own log commit is `2f4d690`).

**This is an addendum, not a revision.** `2026-08-02-device-pass-b10-f24-f25.md` stands as written and contains none of the below.

---

## Repo position

- **`main` and `f8-overlay-and-wiring` are both at `89e77df`**, pushed, 0 ahead / 0 behind. They are level for the first time since the branch was cut.
- Tag: **`integration-2026-08-02`** → `de67dd5`. **`v1.0-b27` deleted** (local + origin).
- Working tree clean of tracked code. `docs/design/` holds Tom's uncommitted work plus this session's F34 / F37 / C15 / D6 edits.

### Gate

| Scheme | Result | Destination |
|---|---|---|
| `MemoryStream` | **1350 cases / 189 suites** — 1339 passed, 3 documented skips, **8 deliberate failures** | sim iPhone 17 Pro `E3C0710E` (**iOS 26.4**) |
| `Himem Watch Watch App` | **34 cases / 6 suites, 0 failed** | watch `B17233F6` (**boot its paired iPhone `74EED5FE` too**) |

The 8 are `SpeechAssetGate`; membership byte-identical every run. **A green phone run here is impossible** — those 8 legs *are* the end-to-end record→compress→transcribe coverage, so the number is a count, not a coverage claim. Counts moved 1294/184 → **1350/189**.

**From `c6fdfbf` on, gates use an isolated `-derivedDataPath` in the scratchpad** (see the governance section). The final gate was cold — the cache started empty — and returned the same numbers as the shared-cache run.

---

## THE MERGE — D5 closed

`f8-overlay-and-wiring` → `main`, **96 commits**, `de67dd5`, `--no-ff`.

**One conflicted file**, `SessionListView.swift`, two hunks, both the same sentence. `ClipsTabView.swift`, `InboxManifest.swift`, `LaunchScreenView.swift` auto-merged; **`EntryExpandedView.swift` was never touched by main** — the file the punch list flagged as hardest was a non-issue.

**Both branches had fixed "when may we say *Nothing new*?" from different directions**, and the resolution is the conjunction:

```
showsEmptyState(sessionsEmpty:hasSiblingContent:mayAssertEmpty:)
```

- `main` (`5eec4ec`): not while a **sibling stack** has content; also moved the gate off `inbox.isEmpty` onto the visible sessions.
- `f8` (F22): not while the **first CloudKit import** is still looking.

Neither supersedes the other; dropping either reopens a shipped defect. **Taking either side verbatim was not available** — main's hunk opens an `else` that the auto-merged lines below close with f8's `else if firstImport.mayAssertEmpty`, so a naive pick produced broken syntax. The interleaving is the merge reporting that both edits are about the same three lines.

**The guard a careless resolution would have defeated:** `mayAssertEmpty` is passed as an **argument**, keeping the call site a real production read — `FirstImportStateTests` counts production readers and explicitly rejects a comment as a read. Reading it *inside* the predicate would have compiled and silently moved the only read out of the view.

`--no-ff` bought `git revert -m 1` on the 96-commit integration and cost linear catch-up afterwards. Stated because it made the next merge a non-fast-forward; once `f8` was levelled up to `main`, subsequent merges fast-forwarded again.

---

## D6 — resolved, and the model was wrong

**`v1.0-b27` deleted.** It named a build that never shipped and sat 70 commits back; the commit stays reachable from `main`, so only the annotation was lost (preserved in the session transcript). Replaced by **`integration-2026-08-02`** on `de67dd5` — deliberately **not** a version tag.

**THE CORRECTION THAT MATTERS (Tom, 2026-08-02): we do not manage build numbers. ASC assigns them; we set `MARKETING_VERSION`.**

The prior model — "check TestFlight, then bump all 12 `CURRENT_PROJECT_VERSION` entries in lockstep" — is retired. Under the correct model the historical "drift" (repo 18 / TF 25; tag b27 / TF 28) was never drift: **it was tracking a number that was never ours to set.** A repo value disagreeing with TestFlight is the expected state.

Consequence: **the version tag takes the number ASC assigned, read back after upload** — archive → upload → read → tag that commit. This settles D6's naming problem outright: *a tag cannot be wrong about a number we do not choose.*

Corrected in four places, of which **the stored memory was the dangerous one** — `project_build_number_drift` instructed the retired behaviour and would have re-taught it at the start of every future session, independent of the repo. Deleted; replaced by `project_build_number_is_asc_assigned`, which also records the mechanism that makes the model true (Xcode's **Manage Version and Build Number** option — if it is ever unchecked the old failure returns).

---

## The work

### `19803ae` · The `in_peak == 0` capture gate
A recording landing at peak 0.0000 now says so. Copy: *"We didn't hear anything. Check that HiMem can use the microphone, and try again."* **The recording is always kept.**

Five rulings: **exactly zero, no tolerance** (any floor is a judgment about loud-enough, which J5 forbids — so the `.measurement`-era under-gained population correctly does not trip it); **the shell owns the signal**, consulted before `switch landing` so all three landings are covered; **banner suppressed under a debugger via `P_TRACED`, never `#if DEBUG`** (an untethered TestFlight build still speaks) with the suppression announced so it is not a silent skip; **measures every buffer and every channel** (`[Amp]` is sampled — an instrument, not a gate); **phone only**, watch logged.

Caught inside its own fix: the first wiring set the message conditionally, so a banner would have outlived the recording it described — the frozen-snapshot class (F24 D2, F25) reproducing a third time. `bannerMessage(for:)` returns nil meaning *show nothing*, and the caller assigns unconditionally.

### `c6fdfbf` · `[Meter]` — D10 instrumentation, then D10 closed
Logs `ch0_peak` / `all_peak` / `db` / `level` at 2 Hz. **Tom's normalization hypothesis was ruled out with evidence:** there is no running max, no AGC, no rescale anywhere in the five-step chain (peak → `normalisedLevel` → FIFO → `level × 56pt`).

Measurement then closed D10 as **environmental** — two recordings in two rooms, the first beside an AC unit. **No mapping change was made.** The device data is preserved in the F34 punch-list entry, including that the engine delivers **4800 frames at 48 kHz (~10 Hz), not the ~45 Hz at 1024 frames the phone's comment claims**, with a measured publish rate of ~6.4 Hz.

### `ead61c1` · F35 — the New lens described one set and rendered another
(a) Header counted/ranged over unfiltered `benchClips` while its session count came from filtered `sessions` → *"19 new clips · 1 session · Apr 28 – today"* above one clip. **The grouper was not at fault** — it never saw the reviewed clips. `BenchLensClips.forLens` is now the single definition the header and grouper both read. "new" was lying independently of the arithmetic.
(b) `SessionListView` and `ClipsTabView.loadUnplaced` fetched the same zero-edge voice ref independently → one transcript rendered twice, three times expanded. P0-3's risk-1 across ref-vs-ref. **Scope confirmed before shipping:** `unplacedRefs` has one consumer, so excluding voice cannot hide anything from the Unconnected lens.

### `9f50440` · F36 — a clip stays New while it could still join a session
New admits `!reviewed || stillInPlay`. **Session-relative, not clip-relative** — a clip-relative window splits a real session (A at T, B at T+9, at T+11 A ages out) which *is* the reported symptom. Reads `ClipSessionGrouper.sessionTimeWindowSeconds`; the coupling is noted **at the constant**.

**A lens-level fix, which is why it covers every trigger.** Four sites write review state — the clip editor on open, the per-session bulk mark, the backfill migration, the materializer mirroring into the ref store — all landing in `benchClips[].reviewed`. No separate trigger-level change was made; a redundant one was expected and declined.

### `7d84e23` · F38 + F39
F38: header summed `absorbedMediaBySessionId.values` while cards *look up* `[session.id]`, so media keyed to a non-rendered session was counted and undrawable. Also: **four of five sites that set `sessions` refreshed the absorbed map and one did not** — now one owner, `regroupSessions()`, with a guard asserting exactly one assignment site.
F39: eyebrow **"Might go together"** + subtitle **"N clips from M sittings · X minutes apart"**. *"belong"* rejected — J5's interpretive verb.

### `89e77df` · F40 + F41 + F42
**F40's ruled fix was NOT built.** Root-causing showed `makeTimePlaceProposal(sessions:)` flatMaps whole sessions — **a proposal always consumes entire sessions**, so partially-clustered sessions are unreachable and the ruled (b) addressed a case the proposer cannot produce. The real defect: absorbed media rendered only inside session cards, so when a cluster took every session its photos appeared nowhere. Built instead: `mediaFor`, mirroring `clipsFor`.
**F41:** `pruneDeadDismissedClusters` judged liveness from the manifest and ran on every mutation, so dismissing a cluster containing a ref-backed clip wrote the record and deleted it on the next write. Its own comment was the phantom — true when the bench read one store, false since P0-3 made it read two.
**F42:** the section heading still said *"seem to belong together"* — F39 guarded the eyebrow constant and missed the louder caller line.

---

## Governance earned this stretch

Three amendments, all committed (`4da2c76`, merged `df93ef9`).

1. **A green `xcodebuild` gate does not predict a green Build button.** Demonstrated independently of cause: Xcode failed on a missing build input while the tree was provably correct, and a CLI build nine minutes later passed against the same cache. **REMEDY (a mechanism, not a rule): CLI runs get their own `-derivedDataPath`.** `xcodebuild clean` is not enough — 610 stale files → 61, all survivors in `Index.noindex/Build`. Broken SourceKit diagnostics are a **symptom, not lag** (dismissed five times that session while reporting this defect).
   **The cause is recorded as UNKNOWN.** Three of our own actions wrote to a DerivedData a running Xcode owned; the discriminating evidence was the index build description's timestamps and **deleting DerivedData to fix the symptom destroyed it**. *Fix the symptom second; date the artifact first.*
2. **Don't Go Looking for Zebras now carries an ENFORCEMENT PROCEDURE**, because it failed three times in one day *while being cited*. Before proposing any cause: **enumerate your own actions in the last hour as a literal ordered list with times, in the report** — reflog (incl. bisects), mtimes of your own build logs, and the commands run *including flags*. Every hypothesis reaching outside that list must name which listed action it rules out. The nearest antecedent in time is the first candidate.
3. **New non-negotiable: where a rule can be replaced by a mechanism, replace it.** Distinct from inventing ceremony — ceremony adds a step to every future task, a mechanism deletes a failure mode. **When a rule has failed while being cited, it cannot be carried by memory.**

---

## THE RECURRING SHAPE — three-numbers-two-sets, four instances

| | Surface | Counted | Rendered |
|---|---|---|---|
| **F35(a)** | New header | unfiltered `benchClips` | filtered `sessions` |
| **F37** *(logged, unruled)* | New count vs opened session | lens set | `computeSessions(applyFilter: false)` |
| **F38** | absorbed-media count | `.values`, any key | `[session.id]` lookup |
| **F40** | absorbed-media count | `sessions` | `looseSessions` + cluster |

**Two of the four were caused while fixing the previous one.** F35(a) filtered the `benchClips` term and left the absorbed term; F38 scoped the absorbed term to `sessions` rather than to what renders. In both cases the guard passed because **it tested the symptom, not the invariant** — F38's forbade `.values` and never checked the scope was the rendered set.

---

## Self-reproductions inside their own fixes

- **The capture gate** set its banner conditionally → a message outliving the recording it described (frozen-snapshot class, third instance).
- **F42** — F39 guarded the eyebrow constant and missed the section heading above it: guard-the-caller, committed inside the fix for the rule it violates. **Fourth instance on this branch.**
- **F40's guard accepted the mere declaration of `mediaFor`** — an unused parameter would have satisfied it, i.e. guard-the-caller *inside the guard*. Found only because a mutation produced compile errors, proved nothing, and had to be redone compiling; the redone mutation left the suite **green**, exposing the weakness. Without the failed mutation forcing a retry, a guard that could not fail would have shipped.

---

## What was NOT verified

**This is an absence section. It is the part most expensive to inherit wrong.**

- **Six device-found fixes are simulator-only:** the capture gate, the merge's three-condition empty state, F35, F36, F38+F39, F40+F41+F42. Every one was *found* on hardware. The last device evidence predates F35 entirely.
- **The F41 sequence has not been run.** It needs a specific order — cluster containing a **ref-backed** clip → dismiss → **record something** (the manifest write that used to prune it) → confirm it stays dismissed — plus the background-and-reopen path (`materializeAll` on appear). A glance cannot test it.
- **The capture gate's banner has never rendered.** Provoking a real `in_peak == 0` means recreating B10's held-device state, ruled out as not worth the wedge. `DebuggerAttachment.isAttached` under a real debugger is **untested** — the device pass launched from the home screen, so only the untethered branch (`P_TRACED == false`) was exercised.
- **F36's window has never been watched elapse** — every test injects `now`. The view has no timer, so a clip leaves New on the next render, not on a tick. Deliberate (nothing vanishes while being looked at); the transition itself is unobserved.
- **F38's accepted consequence has not been observed** — a count that drops when media is absorbed by a session outside the lens. Reasoned, not seen.
- **F40's media row has never rendered.** Its glyph vocabulary mirrors the session card; placement and weight are unknown.
- **F39/F42 copy has been seen; the eyebrow reads well and distinguishes the card** (confirmed on device). The new section heading has not.
- **The archive is development-signed.** `ARCHIVE SUCCEEDED`, `ValidateEmbeddedBinary` passed on both nestings, dSYMs present — but it cannot be exported for TestFlight. The keychain holds only `Apple Development`; the distribution leg and the ASC upload are Tom's.
- **`main` now carries more unverified-on-hardware surface than at session start**, and Clips/New has been modified in four consecutive cycles — the area with the most fixes is also the area generating the most findings.

---

## Open threads

- **F37** — the New count and the opened session describe different sets. `openedSessionContent:854` uses `computeSessions(applyFilter: false)` **deliberately**, per the July 19 ruling recorded at `:866` ("open the container → its contents are seen"). Defensible intent that collides with the count; reconciling them changes a *what*. **Logged, needs a ruling.** F36 narrowed it, did not close it.
- **F34 / C15** — `SpeechService.normalisedLevel` and `WatchRecordingService.normalisedLevel` are byte-identical (−50/−18) under a watch-side comment asserting parity, **and they do not match** (watch takes a running peak across the window; phone publishes one buffer in ~1.6 and drops ~36%). Post-tag.
- **The note-path collapsed/expanded repeat** — unreachable for voice after F35(b), latent for notes via `CompactClipRow`.
- **D9b** — how common is *"No words in this recording."* on real history.
- **The distribution archive + upload (D1 remains the only true submit blocker).**
- Carried: D3 iPad screenshots · D4 Beta App Review · D7 (J1–J5) · D8 deployment targets (**downgraded** — see risks) · post-tag rebuilds C1–C15.

## Risks

- **D8 is smaller than written.** Enumerated from the pbxproj: **17.0** is a project-level default no target inherits; **26.0** is every *shipping* target (app, watch app, widgets); **26.4** is **test bundles only**, never embedded in a distributed archive. The feared "26.0 app embedding a 26.4 extension" does not exist. Acting on D8 as written would have raised the shipping minimum and cut off 26.0–26.3 users for nothing.
- **Guard-the-caller is past nine instances**, now including two inside guards themselves. C2/C3 should not slip far past the tag.
- **C2 is directly implicated twice this stretch** — F35(b) (two views fetching one row) and F41 (a prune reading one of the bench's two stores). Both were patched at the instance; the clip-storage seam is the class.
- **Simulator and disk remain the binding constraints.** Free space drifted 41Gi → 34Gi; three isolated derived-data trees cleared at close, the archive kept.
- The 8 red legs still read as a regression to anyone who skips the qualification.
