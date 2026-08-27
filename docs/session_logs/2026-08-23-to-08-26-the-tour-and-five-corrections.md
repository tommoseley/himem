# Session log · 2026-08-23 → 08-26 · the intro tour, and five corrections

Facts only. Immutable. **Written for a context-free reader.** Covers `b76a8f1..b9dea45` (13 commits). Build session with a device pass running through it.

---

## Repo position

- Branch **`f8-overlay-and-wiring`** @ **`b9dea45`**, **73 ahead of `main`**, **0 unpushed** at close.
- **`main` @ `36ce159`** — deliberately behind.
- Code tree **clean**. `docs/design/` is Tom's (14 entries modified/untracked); CC wrote to exactly one file there, appending rows **B29–B32** to the action-items inventory at Tom's explicit instruction ("the design directory being mine shouldn't mean findings queue behind me").
- **One deliberate tracked artefact, unchanged:** `MemoryStreamTests/DuplicateEdgeConvergenceTests.swift.held` — B26's deferred reconcile, `.held` so it never compiles. Not a pending red.

### Gates — the baseline moved twice

| When | `MemoryStream` | `Himem Watch Watch App` |
|---|---|---|
| Session open | **1507 / 213** — 8 deliberate, 0 crash lines | 34 / 6 |
| After the intro-tour suites | **1515 / 214** | 34 / 6 |
| After the scanner self-tests | **1517 / 214** — 1506 passed, 3 skipped, 8 deliberate, 0 crash lines | **NOT RUN — see absences** |

Toolchain throughout: **Xcode 27.0 / `27A5237l`**, simulator SDK 27.0, runtimes **iOS 26.4.1 (`23E254a`)** and **watchOS 26.5 (`23T570`)**, pinned and unmoved. Any future citation must carry those.

The **8 deliberate** are `SpeechAssetGate`; membership was re-derived mechanically from source at session open and diffed byte-identical against the bundle. **The gate is a count, not a coverage claim** — those 8 legs are the only end-to-end record → compress → transcribe coverage and none ran.

---

## ④ out-of-range — RAN FOR THE FIRST TIME, and its own terms are answered

Carried since the F6 stretch; never executed on any surface.

**The instrument was the whole problem, twice.** The 2026-08-22 attempt failed because a foreground console bridge cannot observe a phone that must sit unattended. This session's first attempt failed for a *different* reason, caught by a pre-flight check **before the window was spent**: iOS elides a third-party app's log message bodies to `<private>` **at write time**, so an `NSLog` line is not hidden in a collected archive — it was never recorded. Measured: 21 bare `(Foundation) <private>` entries from HiMem, zero readable, including the build stamp.

**Fix (`b88ddc7`):** the WC/Inbox diagnostic lines route through a `DeviceLog` helper logging at `.notice` with explicit `.public` privacy. A logging *profile* also unredacts and was rejected — device-wide, must precede the events, and the next person hits the same wall.

- **Level matters as much as privacy.** `Logger.debug` is never persisted and `.info` lives only in memory; neither survives `log collect`. Swapping `NSLog` for `.info` would have produced lines readable in a live stream and absent from the archive — the same fault in new clothes.
- **Publicness decided per call site.** All 60 sites in `WatchSessionDelegate` enumerated and each payload read: ids, counts, booleans, durations, formats, error text. None carries user content (`outcomeLabel` already reduces a transcript to `textLen=`). Three sites taken in `InboxManifest`; its other six left alone.

**RESULT — no duplicate delivery.** 46 reachability transitions (23 up / 23 down), 4 clips, perfect 1:1: each pre-announced once, accepted once, confirmed once, transcribed once.

**THE LIMIT, AND IT IS THE POINT: zero dedup branches fired.** `already in manifest`, `manifest tombstone`, `duplicate master ignored`, `race avoided` — none. So the provocation did not produce the condition. **This validates the instrument and the accounting, NOT the A1 dedup logic.** Exercising the guard still needs an actual redelivery.

**Privacy audit held under real data:** the watch does send a `transcript` key in file metadata, and the received-file line logs `metadata.keys` only.

**Filed as B29:** three clips (`40D421BB`, `DDA80712`, `48D2EF6E`) sat in `awaitingBytes` byte-identical across all four sweeps of an 8.5-minute run. **Every sweep was `trigger=arrival`** — never `ubiquity`, never `retry`. The only thing that ever re-examined them was an unrelated new capture. *Quieting a Busy Path* inverted: the passenger is the stranded clip, the busy path is the user's own capture rate. **Not diagnosed; own cycle.**

---

## The intro tour — built, and verified on device

Seven pages, straight 1→7, shown after onboarding and replayable from the `?` on any screen and Settings → Learn. Exists because a second dogfooder said *"I wasn't sure what was going on, so I used it less."*

**Scope was reported before any code, and five seam questions were ruled** — the double offer, Skip's semantics, which coachmarks retire, F13, and where the tour sits relative to onboarding.

### Onboarding: 9 steps → 4

`apple · name · mic · speech`. Photos, camera, location and notifications deferred to first use.

**Not a new policy.** This file's own restore branch already bypasses the cascade for returning users, and `JournalView` adopted the same deferral for speech and photos on 2026-06-02. Every deferred permission already had an in-context requester. **Deferring removed duplicate asks rather than creating gaps** — a guard-the-caller audit went looking for a hole and found none.

**THE COVER AND THE WAIT WERE ON OPPOSITE BRANCHES.** The wizard's pacing was justified as cover for CloudKit's ~17–21s per-zone setup. That floor is O(1) in record count and hits **populated** accounts; the spike measured ~1.5s against an empty container. A genuinely new user has an empty zone and needs no cover — while returning users, who do, **already bypassed the cascade** for the honest live-count restore screen. Seven permission pages were protecting nobody.

**No branch on a prediction (ruled).** The predicate is unavailable when needed: a local count is always 0 on a fresh install, and a remote check queues behind the very sync it would predict. *You cannot learn "this will take 21 seconds" in materially less than 21 seconds.* `.restoring` predicts nothing — it observes, settles on silence plus count stability, ceilings at 18s.

### The build

- **Page 2 is driven off `CaptureModality.stackOrder.reversed() → sfSymbol`**, never hand-drawn glyphs, so it cannot drift from the FAB. (`.reversed()` because `stackOrder` is the FAB's bottom-up column — voice sits nearest the thumb — while a read-top-down list leads with Voice.)
- **Truncation pinned at `TourScaffold`/`TourPointRow`**, not per site. Text clipping in a container with room had cost three times — F7a, the step label, the row spans — and **F7a's per-site fix is what did not hold**.
- **`.land` and "capture is the invitation" retired BY RULING, not by side-effect.** The lock still holds — FAB on every screen, walkthrough beat 1 is Record. Pre-arming a live mic for someone who just chose "let me look around" deliberately **not** reimplemented on page 7.
- **`OnboardingView` deleted (635 lines)** — see corrections.

### Verified on device (2026-08-26)

Rail reads **"of 3"** · tour runs **1→7** · page 2's sheets **return without advancing the spine** · page 7 **lands on Record rather than re-asking**. **The four unseen items are seen and passed.**

---

## Two device defects, found and fixed

**1 · The double offer (`e3d569e`).** Page 7 presented `.offer` — the question she had just answered. **Both pieces were correct in isolation**, which is why no suite saw it: the tab shell mounts *behind* the tour, its `.onAppear` armed `.offer` while `IntroTourStore.hasSeen` was still false, and `startAtFirstBeat()` — guarded on `activeBeat == nil` — silently no-opped. **A wider guard would have been the wrong fix:** under the ruling `offerIfFirstRun()` can never legitimately fire. Retired with its call site; `.offer` kept for "Show me around". Money tests assert the **caller ordering**.

**2 · The tap target (`f89357c`).** Page 7's primary tapped only on its words. **The guard existed, ran, and cleared it by design** — `isOffending` treats any fill as exoneration (F17 verified that shape), and the F29 scanner requires a String label. The **closure-label-with-outside-decoration** case fell between two guards, each with a reason to pass it; `tourCard` had shipped with it. Fixed, guard extended, mutation-verified.

**The `.buttonStyle(.plain)` theory was deliberately NOT encoded** — `contentShape` is correct regardless of why, and a guard built on an unmeasured mechanism would be a rule pretending to be one.

---

## THE FIFTH MEASUREMENT CLASS — a well-formed reading of the wrong quantity

Recorded in `CLAUDE.md`. The other four are properties of the artifact: unread, truncated, never-executed, altered-by-measuring. **This one yields a clean number, in the clear, from the instrument you asked for**, and answers a different question than the one posed. No error to notice, no `<private>`, no exit code, no absent line.

**Three instances, all this session, all correct about the wrong thing:**

1. **`storageReady` instead of the import.** Converted to the persistent store *specifically* so a cold-launch reading could be taken — and it was: 40ms. Against the ~17–21s floor that looks like a triumph. `storageReady` fires when the **local Core Data stack opens**; the floor is CloudKit's per-zone **setup**. Caught by Tom asking *"does `storageReady` measure what the ~21s figure measures?"* — a question about the **quantity**. Every check CC had made asked whether the instrument *worked*.
2. **The contaminated-tree gate.** A paired gate read as a verdict on new instrumentation while a `#if DEBUG` probe from an earlier isolation test sat in the working tree, popped back and unaccounted for. **`198 crash lines` was a correct measurement of a tree nobody meant to test.**
3. **The observer that self-terminates before the quantity elapses.** `markComplete` removes the CloudKit observer, and the 3s fallback fired it at **+3149ms** — roughly 15 seconds before CloudKit's setup would have had anything to say. So `3s fallback — no import event arrived` does **not** mean the account is empty, and zero `ck event` lines does **not** mean no import started. **The instrument built to make the floor visible tears itself down before the floor elapses.**

**Corollaries, both Tom's:** *the wrong-subject failures are self-inflicted in a way the unread-artifact ones are not* — both came from our own state. And **`git status` before reading a gate** is the whole check for instance 2.

**Also recorded:** *the code often already says so.* `LaunchScreenView` defers `FragmentMigration` two lines above the `storageReady` callback **precisely because CloudKit's import has not settled there**.

---

## Five self-corrections

1. **`OnboardingView` was dead code, and it redirected a ruling.** 635 lines, zero references, superseded by `PermissionWizardView` (whose own header says so). A scope report described first launch as its four screens; the live flow was **nine steps**, and the file even made a correct claim of Tom's ("Topics is retired") look wrong. **Deleted.** *Dead code that plausibly describes a flow it no longer implements is worse than no documentation.*
2. **"Deterministic, not load flake" from n=2.** `DebouncedTriggerTests` failed twice consecutively with the Projects diff and once clean at HEAD; reported as caused by the diff. A third run on the same tree came back clean. **Two consecutive failures of an intermittent test is an unremarkable outcome, not a determinism proof.**
3. **"A `#if DEBUG` view that no test constructs is taking down the host."** True and irrelevant, and it sent the cycle at the wrong subject for a day. The cause was **CC's own scanner** trapping on the probe's source text. **A scanner's input is not what runs; it is what exists.**
4. **"Three scanners" was a count inside one file.** The real figure is **40 source-walking test files, 30 slice sites**. Getting it wrong in the direction of fewer would have left the class unexamined. All 30 checked individually; **exactly one trap-capable** — CC's.
5. **"Three unused runtimes," caught before acting.** Only one was safe. `watchOS 26.4` has a device bound to it that is **paired with the phone-gate simulator**; the two `iOS 26.4` runtimes **share an identifier**, so nothing proves which backs the pinned device. A confident deletion would have taken a pinned dependency with it.

**And a sixth, smaller:** `AuthService.updateUserName(_:)` was written from memory into a rewritten screen. It does not exist. Caught by diffing against `git show HEAD:` rather than waiting for the compiler.

**Two over-reports of CC's own scanner, in one sitting:** 5 shipped views convicted (inner `HStack`'s brace read as the label's close), then SearchView's "When" chip (one-line `Button { } label: {` form starting the depth two high). **16→7, 11→2, 5→1→0** — three scanners, three over-reports, all container attribution. Both false-positive shapes now carry self-tests.

---

## Governance added to `CLAUDE.md`

- **The fifth measurement class**, with all three instances and both corollaries.
- **A source scanner's self-tests must include a malformed input**, alongside the offender and the clean case. Its input is every file the walk reaches; a mis-read under-reports, but **a trap kills the test host**. Plus: **classify a slice by what its bound guarantees, not by whether it has one** — `lines[start..<min(i + 20, count)]` traps just as readily if `start > i + 20`.

---

## Other work

- **Modality colours (`ac067e4`).** The Append spec maps every modality onto an **existing** Crucible token and authorises no new colour. The implementation had replaced those references with hand-picked hex; **not one shipped value matched its spec**, and two tokens the spec names (`--topic-forest`, `--topic-ocean`) **have never existed**. Ruled: voice→`accent`, photo→`pine`, video→`plum`, note→`tide`, attach→`slate`. Verified byte-for-byte against `crucible.css` in both columns before landing. One file, 29 sites inherit.
- **`DebouncedTrigger` tests (`592848d`).** `waitUntil` returned **silently** on timeout, so the visible red was a bare `callCount == 3` — what was wrong, hiding why. Now fails loudly naming the expiry; the spaced test waits on **the action itself** via a one-shot latch whose watchdog resolves the same latch (single resume, no leak).
- **Projects `?` (`8bfee42`).** Projects was the only browsing tab with no help affordance. Now opens the Learn hub like Clips and Memories, with `HelpTopic.projectsConcept` leading.
- **120 GB reclaimed.** 24 stale Device Support bundles; 12 → 136 Gi. No runtime deleted; the two live bundles kept deliberately.

---

## Open threads

- **The watch test-runner install failure — blocks every paired gate.** Five attempts, none reaching a test: `Failed to install or launch the test runner (Invalid device state)` with `Mach error -308 — (ipc/mig) server died` from `installApplication`. **Three causes eliminated, none found:** disk (failed identically at 12 Gi *and* 136 Gi), stale device state (in-place `erase` of both halves on the pinned runtimes), the code (0 compile errors; the change is in an iOS-only Sources phase). **A simulator boots and survives 30s unattended in isolation** — it dies specifically during the runner install, at the `Testing started` boundary, and the phone gate installs its own runner fine. **Watch-specific, in the install path. Own cycle, next session.**
- **Reading #2 — void three times over.** Own cycle.
- **The 3s fallback vs the 17–21s floor.** On a populated account `FirstImportState` latches `.complete` ~15s before CloudKit delivers anything, so `mayAssertEmpty` starts asserting emptiness early. F22 territory and a *what*.
- **`.plain` isolation** — probe committed (`d8eb1a7`) and present in the build on the phone; unmeasured.
- **B29** stranded clips · **B30** `kind=unknown` · **B26** reconcile (held) · **B27** partition axis · the layout flip · C2 step 5 · C1/C8.
- **`--m-*` in `crucible.css`** — Tom's; the mapping lives only in `Himem · Append.html`'s local `:root`.
- **D1 — App Store submission still needs a real RC.** No beta solves it.

---

## What was NOT verified

**This is an absence section. It is the part most expensive to inherit wrong, and this session it is unusually load-bearing.**

- **READING #2 IS STILL VOID, after three separate reasons in three attempts.** (1) The instrument measured `storageReady`, the wrong quantity. (2) The arc never armed — `himem.firstImportComplete` was true, so `begin()` returned at its guard, and **both log lines sat behind that guard**, making the archive silent on the branch that actually happened. (3) On the genuinely fresh path the 3s fallback fired at +3149ms and **removed the observer**, so no `ck event` line could be logged thereafter. **The floor has never been measured on this device.**
- **The watch half of `b9dea45` was NEVER GATED.** Stated as blocked in its own commit message, not green. The argument that an iOS-only Sources-phase file cannot affect the watch target is **reasoning, not a reading**, and is recorded as such.
- **`.plain` remains unmeasured.** The probe is committed and installed and has not been run. If `.plain` is the mechanism, every filled `.plain` button in the app is suspect — the last genuinely wide unknown from this stretch.
- **No colour change has been seen rendered.** Five browsing surfaces changed tint in both modes; `pine` on dark is the swatch most likely to read differently than intended, and none has been looked at.
- **The `DebouncedTrigger` intermittent is not proven gone.** One clean run establishes absence no better than two reds established determinism. What changed is that it can no longer fail silently or misleadingly.
- **Whether the bench regroups often (B23) is unmeasured, not disproven.**
- **The wiped-install pass answered readings #1 and #3 not at all.** #1 needs a spare Apple ID (an empty CloudKit zone); a delete-and-reinstall gives the populated-zone path. #3 — the zero-topic surfaces, live since `be0dc2f` — was not reported on.
- **Per-commit gating:** `e3d569e` was gated over the combined tree with `f89357c`, stated in its message rather than implied.
- **Enumerations swept mechanically this session:** `SpeechAssetGate` membership; all 60 `WatchSessionDelegate` log sites; every mention of the five removed `WizardStep` cases; all 30 source-slice sites; the modality token contract in both columns; `himem.firstImportComplete`'s writers. **Trusted rather than re-counted:** C2 step 5's *"~59 source-scan assertions"*, still inherited.
- **Mutation-verified this session:** the extended hit-region guard only (stripping `tourCard`'s shape failed it naming `TutorialsHubView.swift:144`, and only that).

## Risks

- **`main` and `f8` are 73 apart.** Pushed, so the exposure is integration, not loss.
- **The watch gate is down.** Until the runner-install failure is understood, no paired gate can be run — every future commit inherits a half-stated gate.
- **The tour has been seen once, by CC's operator, on one device.** It has never been in front of the dogfooder it was built for.
- **Git identity on all 13 commits is `tom@Toms-MacBook-Air.local`**, auto-derived rather than Tom's address.
