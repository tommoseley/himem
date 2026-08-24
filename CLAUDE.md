# CLAUDE.md - himem

## Purpose

himem is a new project. This file establishes development governance — the engineering discipline that applies regardless of what himem becomes.

These rules are derived from battle-tested governance in The Combine (`~/dev/TheCombine/`).

---

## Design Authority (read first)

**The designs and specs in `docs/design/` are decisions, not suggestions.** You build what they specify. Your latitude is *how*, never *what*: view structure, state plumbing, file organization, internal naming, the mechanics of making the specified behavior work. Behavior, copy, verbs, ontology, layout intent, and interaction model are already decided.

- **Raise concerns, don't deviate.** If a spec looks wrong, impossible, contradictory, or costly, stop and say so with reasoning, and wait for a ruling — that's wanted. Quietly building something different, "improving" a design in passing, or resolving an ambiguity by inventing a new *what* is not. A raised concern is cheap; a silent deviation gets caught in review three screens later and costs a day.
- **Escalation chain: Agent → CC → Tom.** Sub-agents escalate to you. You resolve *implementation* questions inside the locked architecture (coherence fixes — wording/mechanics that make the build match an existing decision). Anything that changes a *what* — vocabulary, architecture, principle, ontology — goes to Tom.
- **Two classes of edit:** a *coherence fix* (build matches an existing decision) is fine to apply; a *vocabulary / architecture / principle change* requires explicit approval, even when it seems obviously better.
- **Definition of done:** first *"does this express the design as specified?"*, then *"does it work?"* A green build that deviates from the design is a regression, not done.

Source of truth: `docs/design/CLAUDE.md` PART 0 and `docs/design/HiMem · Locked Decisions.html` (Architectural Invariants). Multi-agent execution is orchestrated per `AGENTS.md` (repo root).

---

## Development Governance

### Bug-First Testing Rule (Mandatory)

When a runtime error, exception, or incorrect behavior is observed, the following sequence **MUST** be followed:

1. **Reproduce First** -- A failing automated test MUST be written that reproduces the observed behavior. The test must fail for the same reason the runtime behavior failed.
2. **Verify Failure** -- The test MUST be executed and verified to fail before any code changes are made.
3. **Identify the Red** -- The failure MUST be confirmed to be an *assertion* failure, at the expected assertion, with the expected values. Neither a build failure nor a launch failure is a red.
4. **Fix the Code** -- Only after the failure is verified may code be modified to correct the issue.
5. **Verify Resolution** -- The test MUST pass after the fix. No fix is considered complete unless the reproducing test passes.

#### Constraints

- Tests MUST NOT be written after the fix to prove correctness.
- Code MUST NOT be changed before a reproducing test exists.
- If a bug cannot be reliably reproduced in a test, the issue MUST be escalated rather than patched heuristically.
- Vibe-based fixes are explicitly disallowed.
- **"I saw red" is meaningless without naming *which* red.** `xcodebuild` exits **65** for at least three unrelated conditions — identical signal, completely different meanings:
  1. **Compilation failure** — the test never ran. Detect: `grep -E "^/.*: error:"`.
  2. **Assertion failure** — the only real red. Detect: a named failing test plus its message, read from the `.xcresult` (`xcrun xcresulttool get test-results tests --path <bundle>`); the console does not always print it.
  3. **Launch/infrastructure failure** — e.g. `Testing failed: Simulator device failed to launch … denied by service delegate (SBMainWorkspace)`, or a run that wedges at 0% CPU with no simulator booted. **This is the sneakiest of the three: no compile error and no assertion, so it reads as a genuine test failure until you check the tail of the log.** Usually stale simulator state — `xcrun simctl shutdown all` and re-run.

  A test that didn't compile, or never launched, has proven nothing. Mistaking either for a reproduction silently invalidates the whole Bug-First method: you proceed to "fix" a defect you never observed. **Always identify which of the three you have; never trust the exit code alone.** *Origin: all three hit in one session, 2026-07-29/30 — a `@MainActor`-isolation compile error read as a passing red gate; a duplicate-declaration compile error likewise; and a full suite "failing" on a simulator launch denial that passed unchanged after a simulator reset.*

This rule applies to all runtime defects including: exceptions, incorrect outputs, state corruption, and boundary condition failures.

### A Debugger Attachment Can Hold the Capture Hardware (Mandatory)

**Any capture-path measurement taken over a Device Hub / debugger connection is suspect.** Xcode's Device Hub can hold the device's media services, which starves microphone and camera capture *for every app on the device* while leaving the app's own state perfectly plausible: the session activates, the engine starts, `isRecording` is true, the tap fires with correct frame counts, and the file is written at exactly the right size. The only visible difference is that the samples are zeros.

**Device-pass protocol for anything touching capture: install, DISCONNECT, then test.** A reading taken while attached measures the attachment, not the app.

- **Exact zeros are the signature.** Gain problems *attenuate* (`in_peak ≈ 0.01`); a held device gives `in_peak = 0.0000` on every buffer, indefinitely.
- **Cross-app breakage is the tell.** If another app (Voice Memos, Camera) is also silent, stop looking at our code entirely.
- **It survives a bisect.** An old build fails identically, because the cause is not in any build — which can read as "we never broke it, so it must be the device," and that is *almost* the right conclusion for the wrong reason.

*Origin: 2026-08-02. `in_peak = 0.0000` on iPhone across 300 buffers and two builds, while iPad ran identical code at 0.02–0.06. Disconnecting the phone from Device Hub restored capture. The bisect to `4a08423^` was correct and necessary — it cleared our diff — but the diff being clear is not the same as the app being at fault, and the next hypothesis after "not our code" must be the measuring apparatus before it is the hardware. Cost the better part of a pass.*

### Don't Go Looking for Zebras (Mandatory)

**When something that used to work fails, our own recent changes are the FIRST suspects, not the last.** Open by checking the diff. Environmental theories, Apple-behaviour theories, device-state theories and user-error theories are **last resorts, reached only after the diff is cleared** — and "it worked before" is the strongest possible signal that the cause is in what we just touched.

- **Bisect the surface first.** Name the commits that touched the failing path since it last worked, and read each diff before forming any other hypothesis.
- **A change's side effects count as the change.** A fix aimed at one property can move another: `.measurement` → `.default` was a *gain* fix, and it also changed the **input node's format**, which changed the master file's format, which changed what every downstream consumer receives. The blast radius of a config change is every value derived from it.
- **Re-check your own exonerations.** Evidence that a component "worked" must come from the *current* build on the *current* path — a log line showing an old file being read proves nothing about the code that wrote it.
- **Then write the test that would have caught it.** Every one of these failures reached a device through a suite that was green.

**ENFORCEMENT — this rule has now failed three times in one day *while being cited*, so it carries a procedure rather than an exhortation. A rule you can quote and still violate is a rule that needs a mechanism attached.**

1. **Before proposing ANY cause, enumerate your own actions in the last hour as a literal ordered list with times.** In the report, as a list — not as prose reasoning, which is what lets an action be skipped without anyone noticing. Three sources, each one command:
   - `git reflog --date=format:'%H:%M' -20` — checkouts, merges, commits, **bisects**
   - mtimes of your own build/test logs and result bundles — `stat -f '%Sm' -t '%H:%M:%S' <logs>`
   - the commands run this session, including flags (a `-configuration` or `-destination` the IDE never uses is an action)
2. **Every hypothesis that reaches outside that list must name which listed action it rules out, and why.** "It's environmental," "it's the toolchain," "it's the device" are not hypotheses until the list is on the page and each entry is addressed.
3. **The nearest antecedent in time is the first candidate**, not the most interesting one. Both wrong answers on 2026-08-02 reached for older and more distant causes while a half-hour-old action of our own sat unlisted.

*All three of that day's failures were visible in one command:* the `.orphans(` false premise, the Device Hub attachment (an *install* is an action), and the 16:53 CLI build.

*Origin: 2026-08-01/02 device pass. Silent recordings on the phone. CC opened with an audio-route/Bluetooth theory while the causing change sat two days deep in the diff, and separately exonerated the compressor using a transcription of a file recorded on an earlier build. Tom's correction: "this WORKED, 100%, before the troika changes — this is something we just broke."*

*Second instance, 2026-08-02 — **the rule was quoted while being broken.** Xcode's Build failed an hour after building fine. CC proposed a rename from two days earlier; when Tom asked "why fail now?", CC proposed a merge-driven mtime storm; when Tom said "and YOU ran builds an hour ago as well," the actual nearest antecedent turned out to be **CC's own CLI build, half an hour before the failure**, with a configuration and destination the IDE never uses, into the DerivedData Xcode owned. **Twice in one investigation the explanation reached past our own actions** — and both reaches were toward older, more distant, more environmental causes. **The tell is chronological: list what WE did, in time order, before proposing any mechanism.** `git reflog --date=format:'%H:%M'` and the mtimes of your own build logs answer "what changed in the last hour" in two commands, and both were available before the first wrong answer. Corollary, learned the same hour: **fixing the symptom can destroy the evidence** — deleting DerivedData cleared the fault and with it the timestamps that would have named the cause.*

### Per-Device State Keyed by Content Id Must Prune When Its Content Goes (Mandatory)

**A store keyed by a clip/entry id outlives the thing it describes unless something deletes it. Give every such store prune-on-write, or it will one day answer a question about a row that no longer exists.**

Four instances in this codebase, and the difference between them is the whole rule:

| Store | Prunes? | Outcome |
|---|---|---|
| `dismissedClusters` | **Yes** — drops records whose member clipIds are no longer in the inbox, from `replace(with:)` | Correct. A stale *Not together* can never suppress a future proposal. |
| `BenchClipReviewStore` | **No** | Leaked for three sessions. |
| `BenchClipDurationStore` | **No** | Latent — logged, not yet bitten. |
| `PreviouslyConnectedStore` | **No** — `record` only ever inserts | Latent. Added to this table 2026-08-19. |

**`PreviouslyConnectedStore` is the fourth instance, and it is worth naming
because of what would depend on it.** It is a `UserDefaults` `Set<String>` of
`MediaReference` ids, keyed by content id, written at exactly two sites (both in
`EntryLifecycleService.removeClipFromMemory`) and read at one
(`ClipsTabView:1828`, the *"was in a memory · now unconnected"* line). Nothing
deletes from it. A reused or reseeded id inherits *"was connected"* — verbatim
the `BenchClipReviewStore` defect that cost three sessions and was misread four
times as a resolve failure.

Today it drives one advisory line, so a stale entry is cosmetic. **It stops being
cosmetic the moment anything structural depends on it** — which was proposed and
declined the same day: re-partitioning the Clips bench on *new-vs-returned* would
have made this store decide which region a clip is drawn in. A store that cannot
forget would then be deciding layout from a fact that stopped being true.

*Second, separate weakness, recorded so it is not rediscovered:* it also does not
carry the signal its one reader implies. `record` is never called on the
memory-deletion path (`recycle(entryId:)`), so a clip returned to the bench by
deleting its memory — the largest producer of returned clips — is not marked as
previously connected at all. **Insert-only AND incomplete**, in opposite
directions.

*Origin: 2026-08-13/15.* QA fixture ids are deterministic by design, so a cleared-and-reseeded clip reuses its id. The review mark survived the clip it belonged to, and the replacement was **born reviewed** — present on **All**, absent from **New**, because All applies no review filter. That signature is diagnostic and was misread four times as a resolve failure in the cluster path.

**It surfaced on exactly one clip, and that is why it took so long.** Only the ref-backed fixture kept its mark, because its review state lives in the ref-keyed store under a stable id; its manifest-backed siblings were recreated each run with `reviewed: false` and could never have shown the fault. So the single misbehaving clip's one distinguishing property — being ref-backed — pointed straight at the wrong subsystem. **A coincidence of storage read as a causal signal.**

- **Ask of any id-keyed per-device store: what deletes this?** If the answer is "nothing", it is this defect waiting for a reused id.
- **`BenchClipDurationStore` is the live one.** Harmless only because every seeded clip is 2 s, so the stale value equals the fresh one — which is precisely why no test would catch it.
- **Present-on-All / absent-on-New is a review-state signature**, not a composition failure. Read the lens before blaming the pipeline.

*The general shape: state that outlives its subject is indistinguishable from state about a different subject.*

---

### Quieting a Busy Path Reveals What Was Riding On It (Mandatory)

**When you remove churn, expect latent work to stop happening — and expect it to look like a regression in the change that removed it.**

A noisy path carries passengers. Anything that re-ran "often enough" because something else was firing constantly now runs only when its own trigger fires — and if it never had a correct trigger, it stops. The defect was always there; the noise was paying for it.

*Origin: 2026-08-13. B15 replaced a 30-second retry sweep with an event. Within one build, **Select all went inert**: the selectable-id registry is cleared on a filter switch and re-populated only by data-change hooks, so on a quiet bench nothing repopulated it. The sweep had been republishing the manifest every 30 seconds, so a re-registration was never more than a few seconds away. Nothing about the registry changed; the thing accidentally driving it stopped.*

- **Do not attribute it to the quieting change.** The honest description is *"this never had a trigger of its own"*, not *"B15 broke selection."* Reverting the quieting hides it again — F6d's shape.
- **Fix the trigger, not the silence.** Whatever needs to be current must be refreshed **when it is about to be used**, not whenever the data happens to move.
- **Expect more of them.** One quieting change can strand several passengers, surfacing over days as unrelated-looking defects. When something breaks shortly after a path goes quiet, ask what it used to ride on **before** bisecting.

This is the constructive twin of *Don't Go Looking for Zebras*: the recent change **is** the first suspect, and here it is the correct suspect for the *timing* while being the wrong suspect for the *cause*.

---

### Assertions Need a Ceiling, Not Just a Floor (Mandatory)

**A one-sided bound exonerates the failure it was written to catch.** `AudioCompressorTests` asserted `ratio >= 10.0` under the message *"codec settings may be wrong"* — so a **780× ratio, which is what silence compresses to, passed**. The more completely the audio was destroyed, the more emphatically the test approved.

- **Bound both sides of any ratio, size, count or duration** whose *too-good* direction is also a defect. Compression that is far better than physically plausible is data loss.
- **Assert the property, not a proxy for it.** Size is a proxy for "the audio survived"; the property is signal. Where the real assertion needs an unavailable resource (a speech model, a device mic), say so — a suite whose only real guard is a leg that never runs on this machine is green as a *count*, not as coverage.
- **A static fixture only tests the format it happens to be.** When production's format is derived from device configuration, a fixture recorded once can stop resembling what ships without anything failing.

*Origin: 2026-08-02. Two independent silent captures reached a device under a fully green compressor suite.*

### Measurement Discipline (Mandatory)

**Name what a measurement actually is before building on it.** Every diagnostic failure in this project has been a signal that *looked* authoritative because it was well-formed, and was in fact truncated, aggregated, or overloaded. None looked like an error at the moment it was read — which is why care alone doesn't catch them.

- **Never let `head` (or any limit) bound a completeness claim.** "No callers exist" is a statement about the whole codebase; a `head -8` that filled with matches from one test file cannot support it. If the conclusion is *"there are none"*, the command must be able to show all of them — filter the noise out (`grep -v`), don't cap the output.
- **Count by the structure you mean.** Counting unique log *lines* is not counting test *cases*: interleaved timestamps split one result line in two, and the halves de-duplicate as distinct entries. Aggregate on the actual unit (per-suite tallies), not on incidental text.
- **Never treat one exit code as one meaning.** See the Bug-First constraint above: `xcodebuild` returns **65** for compile failure, assertion failure, *and* launch/infrastructure failure. **A fourth 65: `ValidateEmbeddedBinary` refusing a platform mismatch on the watch scheme** — *"This target is built for iOS but contains embedded content (Himem Watch Watch App.app) built for watchOS Simulator."* It is a **build** failure, so it shares the launch failure's signature (0 compile errors, no `Test run with` line, no `Failing tests:` block) and reads as a red. Cause: the watch simulator's **paired iPhone simulator was shut down**, so no simulator destination resolved for the container app and it built for `iphoneos` instead. Remedy: `xcrun simctl list pairs`, then boot **both halves of the pair** — the watch sim's partner is not necessarily the phone scheme's canonical destination. Detect: `grep ValidateEmbeddedBinary` in the log tail. *(Hit 2026-07-31 establishing the session baseline; the re-run with the pair booted was 34/6 green, unchanged.)* **It also exits 66 when the working directory contains no Xcode project** — same family as the 65 overload, and it reads as a test failure in a scripted loop because the only difference is one line near the top of the log (`error: The directory … does not contain an Xcode project`). Pass `-project <path>` explicitly rather than relying on the shell's current directory, which does not survive a `cd` in an earlier command. *(Hit 2026-07-31 mid-F23: a `git commit` run from the repo root moved the working directory, and the next test invocation "failed" without running.)*
- **Exit 73 is out of disk, not a test failure.** `ENOSPC`: 0 compile errors, no result bundle, and the tail carries a filesystem error rather than anything about tests. A full paired gate writes a `.xcresult` (~10MB), and repeatedly erasing simulators plus DerivedData compounds it — a long session can fill the volume and every subsequent command fails, including the ones that would clear space. **Delete result bundles between runs**, and prefer `simctl delete` over `erase` for devices that are done. *(Hit 2026-08-01 mid-F28.)*
- **Rotating a simulator must not change the runtime.** The phone gate is pinned to an **iOS 26.4** simulator, and the known-8 `SpeechAssetGate` failures exist *because* the en_US speech asset is `unsupported` there. A 26.5 runtime may resolve that asset differently and **silently move the failure count** — a run returning 5 failures, or 0, is not good news, it is an *incomparable* measurement that destroys the baseline while looking like a fix. Simulator attrition forces rotation often on this machine (four consumed in three days), and "grab any available iPhone" is exactly how the runtime drifts inside a routine step nobody thinks of as a decision. **Erase and recreate on the same runtime rather than moving runtime;** if the runtime genuinely must move, re-cut the baseline explicitly and say so. *(Pinned 2026-07-31.)*
- **A green `xcodebuild` gate does not predict a green Build button — and the gate cannot see the difference.** The command line writes its **own** build description into DerivedData; Xcode's IDE build and its *index* build keep separate ones. So the gate can route around the very cache that is broken. **The two can disagree, and only the IDE side reports it.**

  **REMEDY — do this rather than remember the rule: give CLI runs their own `-derivedDataPath`,** pointed at the session scratchpad and cleared between sessions (per exit-73, it is a disk consumer). A gate that shares no cache with the IDE cannot poison it and cannot be misled by it. This removes the class; everything below is what the class looks like when it is not removed.

  *Demonstrated 2026-08-02, independent of cause:* Xcode failed with `Build input file cannot be found: Shared/WatchAudioSessionConfig.swift` while the tree was provably correct — zero references across the whole `project.pbxproj`, the renamed file present in `Shared/`, the watch scheme green at 34/6 from the result bundle, a clean Release build for `generic/platform=iOS`. **A CLI build nine minutes after the IDE failure passed against the same cache.** That divergence is the finding, and it does not depend on how the cache got poisoned.

  **The cause is UNKNOWN and is recorded as unknown.** Three of our own actions wrote to a DerivedData that a running Xcode owned, inside three hours: a **bisect checkout** (`4a08423^`) that briefly restored a since-deleted file to disk; a **branch round-trip** for a merge that churned the mtimes of 130 tracked sources; and a **CLI build with a configuration and destination the IDE never uses** (`Release` / `generic/platform=iOS` / signing disabled). The discriminating evidence was the index build description's timestamps — and **deleting DerivedData to fix the symptom destroyed it.** Fix the symptom second; date the artifact first.
  - **`xcodebuild clean` is not enough.** It cleared 610 stale files down to 61 — and the survivors were all in **`Index.noindex/Build`**, which Clean Build Folder does not touch. Deleting the project's DerivedData directory is what actually clears it.
  - **Broken SourceKit diagnostics are a SYMPTOM, not lag.** *"Cannot find type X in scope"*, *"No such module Testing"*, and framework-unavailable-on-macOS errors on files that compile fine are the index build failing for a real reason. **Do not dismiss them repeatedly** — they were waved off five separate times that session as index noise while they were reporting this defect. A signal dismissed more than twice is a pattern, not an instance.
- **The observer can alter the observed — an apparatus is not just wrong, it can be MADE wrong by the act of measuring.** The other failures in this section are properties the artifact had before you looked: unread, moved, or never executed. This one you cause. **Two instances, and they are the same shape at opposite ends of the stack.** *(1)* **The Device Hub starved what it measured** — attaching to read the capture path held the device's media services, so `in_peak` was `0.0000` for every app on the phone; the reading measured the attachment (2026-08-02, and it has its own Mandatory section above). *(2)* **A retry loop degraded its own error channel** — 114 `devicectl` launch attempts in a few minutes wedged CoreDevice, and Apple's own diagnostic collapsed from a precise `Locked ("… the device was not, or could not be, unlocked")` into a bare `Invalid argument (NSPOSIXErrorDomain error 22)`. Three rounds went to blaming the device while the retry loop — my own action, the nearest antecedent — was the cause. Stopping and waiting ten seconds made the first clean attempt succeed (2026-08-22).
  - **THE PRACTICAL TELL, and it is the actionable half: the FIRST error in a retry series is the informative one; every one after it may be noise wearing its clothes.** `Locked` named the cause exactly and 113 `EINVAL`s buried it. **Read the first failure of a loop, not the last** — a `tail` on a retry log is a `head -8` in the time dimension.
  - **Bound every retry loop, and prefer waiting to hammering.** An unbounded poll is a load generator pointed at the thing you are trying to read. Where a loop must exist, cap it and log what it gave up on.
- **An empirical claim about a moving target must carry its coordinates INSIDE the claim, or it decays into a standing property.** A finding established by observation is true of the configuration it was measured in. Drop the configuration and it reads as a law — and it will be cited, confidently, after the thing it described has moved. **The remedy is the sentence, not the memory: write the seed and the date into the claim itself**, so a reader cannot quote it without quoting what it depended on.
  - **The tell is a claim about someone else's system stated with no version and no date.** *"TestFlight accepts beta-SDK builds"* has neither. *"TestFlight accepted iOS SDK 24A5390e on 2026-07-30, when that was the current seed"* has both, and the second sentence expires visibly.
  - **A sample of one taken from inside the accepted window cannot see the window.** The observation was correct and the generalisation was not available from it; nothing about the successful upload revealed that acceptance was conditional on being the *current* seed rather than *a* beta seed.
  - **Corollary: re-verify an inherited empirical claim before a release depends on it**, and treat the absence of a date on one as a defect in the claim.

*Origin: 2026-08-22. F6h recorded* **"TestFlight accepts Xcode 27-beta builds — established empirically"** *after build 28 uploaded and processed on 2026-07-30. On 2026-08-22 an upload of a* **byte-identical toolchain** *— `DTXcodeBuild 27A5228h`, `DTSDKBuild 24A5390e`, `BuildMachineOSBuild 26A5388g`, read from both archives side by side — was rejected by App Store Connect with* **"Unsupported SDK or Xcode version"** *(a post-processing email, no ITMS code). Nothing on our side had moved.* **Xcode 27 Beta 5 shipped 2026-08-10**, *twelve days earlier, advancing the accepted seed past ours. The rule never tightened; the window slid, and F6h had recorded a snapshot as a property.* **This session's own pre-flight repeated the stale version before the rejection arrived** — a claim with no expiry attached is not merely wrong later, it is *re-asserted* later, which is how it reaches a release decision.

- **A WELL-FORMED READING OF THE WRONG QUANTITY — the fifth class, and the most dangerous, because nothing about it looks like a failure.** The other four are properties of the artifact: unread, truncated, never-executed, or altered by the act of measuring. This one produces **a clean number, in the clear, from the instrument you asked for** — and answers a different question than the one you posed. There is no error to notice, no `<private>`, no exit code, no absent line. The reading is correct; the *mapping* from reading to claim is not.
  - **The tell is that the instrument was chosen because it was the obvious marker, not because anyone checked what it measures.** Say what the quantity IS, in its own terms, before attaching it to a conclusion — "the local Core Data stack finished opening" is a different sentence from "the first sync completed", and only the second answers a question about sync.
  - **Two quantities that gate different things are not interchangeable because they sit near each other in the log.** One gated the UI; the other gates the content. Adjacent in time, adjacent in the file, unrelated in meaning.
  - **THE WRONG-SUBJECT FAILURES ARE SELF-INFLICTED IN A WAY THE UNREAD-ARTIFACT ONES ARE NOT** (Tom, 2026-08-23). Both instances came from **our own state**, not an external artifact: the launch marker we had just converted, and — one turn after recording this very class — a paired gate read as a verdict on new instrumentation while a `#if DEBUG` probe sat in the working tree from an earlier isolation test, popped back and unaccounted for. `198 crash lines` was a correct measurement of a tree nobody meant to test. **Before reading a gate, state what is in the tree** — `git status` is the whole check, and neither instance would have survived it.
  - **Corollary: the code often already says so.** `LaunchScreenView` defers `FragmentMigration` two lines above the `storageReady` callback *precisely because CloudKit's import has not settled there* — the app knew, in a comment, what the reading was later taken to disprove.

*Origin: 2026-08-23, wiped-install pass. `[HiMem][LifeDx] storageReady` was converted to the persistent log store specifically so a cold-launch reading could be taken — and it was: scene-active → storage-ready in **40 ms**. Against the investigation note's **~17–21s** floor that number looks like a triumph, and it measures a different thing entirely: `storageReady` fires when the local store opens, while the floor is CloudKit's per-zone **setup**, measured as cold-launch-to-first-record-visible. **The instrument was present, readable, correctly implemented, and answered the wrong question.** Caught by Tom asking "does `storageReady` measure what the ~21s figure measures?" — a question about the quantity, not about the instrument. Remedy shipped with it: every CloudKit event now logs with its elapsed time, including `setup`, so the floor is visible rather than inferred.*

- **A conclusion inherits the weakness of its weakest input.** When a finding rests on a measurement, state the measurement alongside it, so a wrong reading is visible as a wrong reading rather than propagating as fact.

*Origin: three instances in one session (2026-07-29/30) — a truncated `grep` producing "P0-3 is unwired" when it was fully wired; a watch-suite count reported as 27 when it was 28; and exit 65 read as an assertion failure when it was twice a compile error and once a simulator launch denial.*

### A First Reading of an Unfamiliar Log Is a Hypothesis, Not a Measurement (Mandatory)

**The first time you parse an instrument's output, you are guessing at its grammar.** Treat that parse as provisional until you have read the code that emits it. Both failures below were *right artifact, wrong pattern* — and both were invisible precisely because the answer came back well-formed.

- **Confirm what an emitter does NOT emit.** A log that only fires on one branch cannot be read as an inventory of all of them. The absence of a line is evidence only once you know the line was possible.
- **A signature with several phrasings needs all of them, every time.** Matching one is not a partial check; it is a check that reports success by failing to look.
- **Where a pattern will be reused, put it in a file, not in a command you retype.** `scripts/gate-report.sh` is that for the crash signature.
- **NEVER RETYPE A PATH A TOOL GAVE YOU — CONSUME IT.** `find -print0` into `read -r -d ''`, or `-exec … {} +`. A path is data, not a label: reconstructing one by eye silently substitutes the character you *saw* for the character that is *there*, and the filesystem answers about a file that does not exist. **This is a mechanism, not a reminder** — a consumed path cannot be mistyped, so the failure mode is deleted rather than watched for.
  - **The signature is two tools disagreeing about one path.** `find` lists it; `ls`, `stat` and `test -d` all say *No such file or directory*. When traversal and interrogation disagree, the path string is wrong — do not reach for permissions, the sandbox, or a race.
  - **`ls` returning "No such file or directory" on a path you can see is not evidence of absence.** It is evidence about your string.

*Origin: 2026-08-22, and it nearly produced a fabricated finding.* Comparing the accepted and rejected `.xcarchive`s, `find` printed `…/MemoryStream 8-22-26, 9.03 PM.xcarchive/Products/Applications/HiMem.app` while every direct read of that same typed path failed. macOS date formatting puts **U+202F NARROW NO-BREAK SPACE** before `AM`/`PM`, so the retyped path — with an ordinary space — could never match. **The first explanation reached for was the sandbox, which was wrong**, and one step further would have reported *"the archives have no app payload"*: a confident claim of absence produced entirely by the apparatus. Caught only because `find` had already proved the file was there, i.e. by the contradiction, not by suspicion. **Fifth instrument fault of the stretch, and a new variant — the artifact was readable and correctly located, and the fault was in the address.**

- **Say "first parse" out loud** when reporting a conclusion drawn from an instrument you had not read before, so the weakness travels with the finding rather than being discovered later.

*Origin: two in one session, 2026-08-19, three hours apart.* **(1)** `[BinThumb]` was read as a manifest of Recently Deleted, and a ruling was reported as evidenced by it. It logs only tile-render **failures** — so the photo, the single item the ruling turned on, was structurally the item that could never appear in those lines. The conclusion was right; the evidence cited for it could not support it, and the real evidence (`lens 15 → 12 → 15`) was elsewhere. **(2)** A crash check grepped `crashed with signal abrt` alone and reported **"0 crashes in bundle"** on a run carrying **51** under `Crash: HiMem at <deduplicated_symbol>` — while § Test Concurrency, three lines long, already named both phrasings. A re-audit of every gate reported that session came back clean, but by the membership diff catching what the grep missed: **luck of construction, not the detector working.**

---

### Assert the Meaning, Not the Phrasing (Mandatory)

**A test that pins exact user-facing copy breaks on every approved rewording — which trains people to update tests reflexively, and a test updated reflexively has stopped guarding.**

- Assert the **clause that carries the invariant**, not the sentence it currently appears in. `#expect(body.contains("only what's in them"))` survives a rewrite that keeps the Honest-Label promise and still fails if the promise is dropped. `#expect(body == "<the whole line>")` fails on a comma.
- When copy is the *subject* of the rule (a locked label, a retired metaphor), pinning the literal is correct — e.g. asserting a destructive button says "Delete" and does **not** say "Let Go". State in the test which one it is and why, so the next reader knows whether a failure means "copy changed" or "promise broken".
- **A failing copy test is a question, not a chore.** Before updating it, decide which happened: the wording moved (update the assertion, keep the invariant) or the meaning moved (that is a design change and needs a ruling, per Design Authority).
- Prefer several small assertions naming each promise over one assertion pinning a paragraph — a paragraph-level match tells you *that* something changed, never *what*.

*Origin: 2026-07-30, F16. Rewording the organize beat to the plural ("only what's in **them**") broke `organizeBeat_isTierAware_honestLabel`, which had pinned the singular literal. The promise was intact; only the phrasing had moved. Rewritten to assert the limit-naming clause per tier, plus the new "Nothing happens until you ask" promise — so the requirement is pinned rather than incidental.*

### Guard the Caller, Not Just the Owner (Mandatory)

**A test that proves an owner is correct proves nothing about whether anyone still calls it.** Every guard MUST assert that *the caller reaches the decision*, not merely that the decision is right — and every guard MUST be verified to fail.

- **Test the wiring, not only the primitive.** "Does `isTransferReady` return false for raw PCM?" is a different question from "does the transfer path still ask?" Write the second one. Where the call site is private, unreachable, or bound to a system singleton, a **mechanical source-level assertion** is a legitimate guard — anchored on the real file, with a self-test proving the matcher recognizes the defect, and a walk that **throws if it reaches no source** (it must not pass by matching nothing).
- **Mutation-verify every guard.** Break the invariant on purpose, watch the guard fail, put it back. *A guard that has never failed is a guard nobody has tested.* Record in the commit what you broke and what failed.
- **A silent skip is not coverage.** A `print`-and-`return`, an environment-gated early exit, or a `#expect(true)` reports as **passed**. If a test cannot run, it must say so as a failure that names the cause and the remedy. Never add a local opt-out — an opt-out is how the gap hides.
- **State the gate honestly.** When a suite is green with legs that never executed, the green is a count, not a coverage claim. Say which is which.

*Origin: 2026-07-31, F23 Tier 2 — three instances in one pass, all the same failure. **T2.3**: `SessionListView` hand-rolled a second `AVAudioPlayer` while the correct `AudioPlayerService` sat unused. **T2.6**: deleting the `isTransferReady` guard from `enqueueReadyTransfer` left **all six** `WatchTransferAudioTranscoderTests` green — a suite CLAUDE.md names as the guard for "raw PCM never ships." **`:614`**: CC added `finishAppend`, tested it, and left the early `return` that bypassed it — reproducing the class one hour after closing it, with four green seam tests hiding it. Also that day: eight transcription legs silently skipped on the dev simulator, so every "1195 passed" gate that session contained zero end-to-end transcription coverage. A test style written against owners in isolation cannot see any of this.*

### Money Tests

Bug fixes MUST include a "money test" that reproduces the exact root-cause scenario:

- The money test MUST fail before the fix is applied.
- The money test MUST pass after the fix is applied.
- The money test serves as the regression guard for that specific defect.

---

### Reuse-First Rule

Before creating anything new (file, module, schema, service):

1. **Search** the codebase and existing docs.
2. **Prefer** extending or refactoring over creating.
3. **Create new** only when reuse is not viable.

- If you create something new, you MUST be able to justify why reuse was not appropriate.
- Creating something new when a suitable existing artifact exists is a defect.

---

### Complexity Management

#### CRAP Score Thresholds

Functions exceeding CRAP score > 30 are flagged as critical and require remediation.

| Score | Rating |
|-------|--------|
| < 5 | Clean |
| 5-15 | Acceptable |
| 15-30 | Smelly |
| > 30 | Critical -- must remediate |

Remediation path: decompose into focused sub-methods (cyclomatic complexity reduction), add test coverage (coverage increase), or both.

#### Structural Rules

- No god functions: business logic MUST be modular and testable.
- Mechanical/deterministic checks are preferred over heuristic validation wherever possible.
- Make every change as simple as possible. Find root causes, not symptoms.
- No temporary fixes. No "we'll clean this up later" without a tech debt entry.
- Changes should only touch what is necessary.
- If a fix feels hacky, pause and find the elegant solution.

---

### Code Style

- **Explicit dependencies:** All imports and dependencies MUST be declared.
- **Readability over cleverness:** Favor clarity and maintainability.
- **No silent failures:** Errors MUST be surfaced, not swallowed.
- **No speculative abstractions:** Don't design for hypothetical future requirements. Three similar lines of code is better than a premature abstraction.
- **No unnecessary error handling:** Don't add fallbacks for scenarios that can't happen. Trust internal code and framework guarantees. Only validate at system boundaries (user input, external APIs).

---

### Do No Harm

Before making changes to existing code:

1. **Verify assumptions** -- Read the code you're about to change. Understand what it does and why.
2. **Check for dependents** -- Understand what relies on the code you're modifying.
3. **If assumptions are wrong, STOP** -- Report mismatches before touching anything.

Do not infer intent from partial understanding. If something is unclear, ask rather than guess.

---

### Regression Protection

- Fixes MUST NOT reduce existing test coverage.
- Tests MUST be deterministic -- they MUST NOT depend on external services or non-deterministic inputs.
- Every bug fix MUST include the test name and root cause in its report.

---

### CloudKit Schema Changes

Any change to a CloudKit-synced Core Data entity (adding, renaming, or removing an attribute or relationship) requires a manual deploy to the Production CloudKit environment **before** the next TestFlight or App Store upload.

`StorageService` calls `initializeCloudKitSchema(options:)` only under `#if DEBUG`, which auto-publishes new fields to the **Development** CloudKit environment. Production schema is only updated via the CloudKit Dashboard.

**Symptom of skipping this step:** outbound sync silently breaks in TestFlight/Production. Local edits save and never propagate to other devices, even though inbound CloudKit-to-device sync still works (because incoming records use the existing schema). Dev builds remain unaffected.

**Required steps when adding/changing a synced attribute:**

1. Make the schema edit in `MemoryStream.xcdatamodel` and the matching `@NSManaged` property.
2. Run a Debug build on a real device — this triggers `initializeCloudKitSchema` against Development.
3. Open https://icloud.developer.apple.com/dashboard/, select container `iCloud.com.himem.app`.
4. Confirm the change is present in the **Development** environment.
5. Click **Deploy Schema Changes** in the dashboard top bar -- review the diff -- deploy to **Production**.
6. Only then archive and upload to TestFlight.

This step is non-negotiable. Skipping it is a regression that's invisible in code review and only surfaces after testers report broken sync.

---

### UIKit Pickers in SwiftUI

`UIViewControllerRepresentable` wrappers around system view controllers (`UIImagePickerController`, similar) MUST leave `updateUIViewController` empty unless there's a specific reason to push state changes.

Setting configuration properties like `cameraCaptureMode` or `mediaTypes` on a live picker tears down its underlying `AVCaptureSession`. SwiftUI calls `updateUIViewController` on every parent re-render — that's often enough to repeatedly destroy and rebuild the session, producing a black preview and `appleh16camerad: failed preProcessJasper jasper` errors in the device console.

**Symptom:** picker UI loads (zoom controls, shutter, dismiss all work) and the privacy indicator confirms the camera is active, but the preview is black.

**Rule:** configure the controller once in `makeUIViewController`. Leave `updateUIViewController` empty unless an external state value really needs to drive a property change.

---

### Audio Session Coordination

`SpeechService` (voice capture) and `UIImagePickerController` (camera capture) both compete for the singleton `AVAudioSession`. Voice sets `.record` mode and activates the session; camera's internal `AVCaptureSession` may fail to initialize if the existing session is in the wrong state.

**Required at every camera-trigger button:**

1. Stop any active speech recording before presenting the picker (`composer.stopRecording()` / `speechService.stopRecording()`). Don't rely on the picker to interrupt it.
2. Don't manually `setActive(false)` the audio session as a "release" step in the camera path. `SpeechService.stopRecording()` already does it. Calling `setActive(false)` on an already-inactive session can churn the audio HAL.

---

### Watch Audio Transfer Format (locked 2026-07-14)

The watch transcodes every clip to **mono · 16 kHz · AAC (`.m4a`) before `transferFile` — it never ships the raw recording.** The hardware input is 3-channel / 48 kHz / Float32 PCM (~576 KB/s of audio): a 59 s clip is ~33 MB raw vs ~230 KB compressed (~144×), and the raw payload takes minutes over WatchConnectivity — the ~50× sync-slowness bug (dogfood 2026-07-14).

- **Whole-file transcode, after stop — never per-callback.** Per-callback resampling inside the record tap starves the resampler's continuity filter and produces silence (the July 5 2026 saga, reverted twice — see `feedback_avaudioconverter_nodatanow_starves_resampler`). Use a single stateful `AVAudioConverter` pass over the finished file; `AVAudioFile` does the AAC encode (no `AVAssetWriter` — unavailable on watchOS, which is why `AudioCompressor` can't be reused here).
- **Timing (watchdog-sensitive).** `WatchRecordingService.stop` deliberately does NOT sync-drain the write queue (a sync drain on the main thread trips the watchOS watchdog — a documented QA crash), so the transcode runs **off-main, on the send path, after the file finalizes**, idempotent across the retry triggers — never synchronously in `stop()`.
- **Explicit mono downmix.** `setVoiceProcessingEnabled(false)` does not collapse the watch input to mono on device (still 3 channels) — downmix explicitly.
- **Guard.** The file handed to `transferFile` MUST be mono / 16 kHz / AAC. An automated assertion (`WatchTransferAudioTranscoderTests`) enforces it; that test failing IS the oversized-transfer bug.
- **Transport is WatchConnectivity, permanently.** The watch never writes to CloudKit or an iCloud container; the phone is the sole iCloud writer (media → iCloud Files, metadata → private DB), off the capture path. "Watch uploads to CloudKit" is retired, not deferred.

Source of truth: `docs/design/Watch · spec.md §2`, `docs/design/HiMem · Locked Decisions.html`, `docs/architecture/2026-07-14-watch-audio-compression.md`.

### Watch Capture Session Mode (locked 2026-07-15)

**The watch records in `AVAudioSession.Mode.default`, never `.measurement`.** `.measurement` minimizes system input processing — **including input gain** — which left the watch mic at ~−40 dBFS: clips arrived **silent and untranscribable** (dogfood: `[Amp]` `in_peak` pinned ~0.01 regardless of how loud the user spoke). `.measurement` was *also* selecting the raw 3-channel hardware input. `.default` applies normal input gain **and** resolves the input to processed **mono** — one change fixes the level bug and dissolves the 3-channel downmix problem at the source (dogfood 2026-07-15: `in_peak` 0.1, clips transcribe at full coverage).

- The mode lives in one place — `WatchAudioSessionConfig.recordMode` (`Shared/`) — used by both the warm and record paths in `WatchRecordingService`.
- **Guard:** `WatchAudioSessionConfigTests` asserts the mode is `.default`, not `.measurement`. Real input energy needs mic hardware to measure (the `[Amp]` transcode log is that device-side check); this config-invariant test is the deterministic guard that a refactor can't silently revert the mode and re-break capture.
- The transcode's **pick-hottest** N→1 downmix is **retained as defensive, tested code** for any future multichannel route — not ripped out even though `.default` now yields mono on device.

Source of truth: `docs/architecture/2026-07-14-watch-audio-compression.md` §4e, `docs/design/Watch · spec.md §2`.

### Wake Lock (Idle Timer)

HiMem holds the system wake lock (iOS: `UIApplication.shared.isIdleTimerDisabled`; watchOS equivalent) **only during active capture** — recording in progress, photo composer open, video composer active. Everything else respects the system idle timer.

**Wake lock ON:**

- Recording audio (watch or phone) — until stop or wrist-off auto-stop.
- Photo or video composer open — until commit or cancel.

**Wake lock OFF (the default — never override here):**

- Browsing memories, viewing a memory, watching the inbox, reading transcripts.
- Listening back to your own audio. Audio plays through the system audio session, which keeps audio running through screen-off; the screen sleeps on schedule and the user can wake to scrub.
- Editing a memory's text fields. The keyboard already keeps the screen alive while typing; we don't override beyond that.

**Two corollaries worth naming:**

- **Playback is not capture.** Listening back doesn't hold the wake lock. The audio session handles continuity.
- **The watch's recording UI being foreground ≠ recording.** If the user opened the recording screen but hasn't tapped to start, no wake lock. Only `recording == true` flips it on.

The system idle timer is a trust contract. HiMem isn't special enough to override it for casual reading.

---

### Test Concurrency and Shared Singletons (Mandatory)

**A process-global mutable singleton must be made safe AT ITS OWNER. Serializing the tests that touch it is not a remedy — it is a remedy-shaped thing that works until enough tests reach the object.**

Swift Testing runs `@Test` methods inside a `@Suite` in parallel by default, and tests that touch non-thread-safe shared singletons crash — `libsystem_malloc.dylib: Abort Cause`, `signal segv`, or a bare `Crash: HiMem`.

**The retired rule, and why it could never have worked.** This section used to say: *mark any suite that exercises a shared non-thread-safe API with `@Suite(.serialized)`.* That orders tests **within** a suite. **Swift Testing runs suites concurrently**, so two different suites reaching the same singleton are exactly as unsafe as before — and the singleton is process-global, so the scope the annotation controls is not the scope that needs controlling. The rule appeared to hold only while few tests reached the shared object.

**Disproven by reproduction, not by argument** (2026-08-12). Adding a handful of tests that call `ClipClusterProposer` — which reaches `LocalEntityExtractor.shared` — tipped a latent race into reliable crashes, with `@Suite(.serialized)` correctly applied and doing nothing. The lock fixed it; the annotation had not.

**Rule:** own the compound operation. Wrap the whole read-modify-write (or assign-then-enumerate, or any multi-step use of shared mutable state) in a lock **at the owner**, and say at the lock why the compound operation — not any single call — is the unit that must be atomic. Both current instances follow this shape:

- `BenchClipReviewStore` — `NSLock` around the whole read-modify-write. `UserDefaults` is individually thread-safe, which is precisely what made the tear invisible: no single call is wrong.
- `LocalEntityExtractor.shared` — `NSLock` around `extractEntities`'s assign-then-enumerate over one shared `NLTagger`. Two callers interleaving leaves the second enumerating a string the first replaced.

`@Suite(.serialized)` remains legitimate for **suite-local** shared state (a fixture file, a singleton the suite itself installs and tears down). It is never the answer for a process-global one. This is the *"where a rule can be replaced by a mechanism, replace it"* non-negotiable: a lock removes the failure mode, an annotation asks every future suite author to remember a rule that would not have protected them anyway.

**THE READING TRAP, and it is the expensive part.** A crash takes down the **test host**, so every test scheduled after it fails as collateral. That run reported **49 failures**; it was **one defect**. The 41 extras spanned suites with no relationship to the change — URL detection, entity keys, manifest dedup — which is the tell: a change cannot plausibly break that spread at once.

**Detect it before diagnosing anything:** read the failure *text*, not the count. `Crash: HiMem at <deduplicated_symbol>` or `Test crashed with signal segv` means the host died and the count is meaningless. Fix the crash, re-run, and only then read the number. This is the **exit-65 overload one layer along** — one signal, several meanings — and it earns the same discipline: *name which failure you have before you act on it.*

**Corollary for mutation verification:** a mutation that makes code *crash* rather than misbehave proves nothing about the guard you are testing, because it fails everything downstream too. If a mutation's collateral spans unrelated suites, discard the run and choose a mutation that produces a wrong answer instead of a trap. *(Cost 2026-08-11: an `Int.max` mutation of a bounds check was read as evidence about a different defect entirely.)*

---

## Planning Discipline

### Plan Before Executing

For any non-trivial task (3+ steps or architectural decisions):

- Plan before writing code.
- Get alignment before executing.

If something goes wrong during execution, **STOP and re-plan**. Do not push through a failing approach.

### Verification Before Done

- Never mark a task complete without proving it works.
- Run tests, check logs, demonstrate correctness.
- "Does this look right?" is not verification. Tests passing is verification.

### Multi-Agent Orchestration

For change sets large enough to warrant parallel work, follow `AGENTS.md` (repo root): **sequential by default**; dependency-aware parallel cycles only when the work is genuinely independent; centralized integration; **re-plan each cycle from the actual repository state.** You are the head implementer and integration owner — agents implement bounded slices; you own architecture, sequencing, schema/migrations, shared interfaces, integration, and the **design-fidelity diff review** (green tests are necessary, not sufficient — a toast in the wrong voice passes every test). Don't stand up a swarm for a two-file change.

---

## Autonomous Bug Fixing

When a runtime error or incorrect behavior is encountered during work:

- **Do not stop and ask for instructions.** Fix it.
- Follow the Bug-First Testing Rule autonomously.
- **Report what you fixed, not what you found.** Include the test name and root cause.

Escalate only when:

- The bug cannot be reproduced in a test.
- The fix would require changes outside the current scope.
- The root cause is ambiguous and multiple fixes are plausible.
- The fix would change a *what* (behavior, copy, verb, ontology, layout intent). That's a design decision, not a bug fix — escalate per Design Authority. Autonomous fixing is for *implementation* defects only.

---

## Session Management

### Starting a Session

1. Read this file (`CLAUDE.md`)
2. Scan recent session logs if they exist
3. Understand the current state before proposing work

### Closing a Session

When the user says "Prepare session close" (or similar):

1. Write session summary to `docs/session_logs/YYYY-MM-DD.md`
   - Scope, decisions, implemented, commits, open threads, risks
   - No prose, no reflection -- facts only
2. Ask: **"Ready to close, or do you want to continue?"**

Session summaries are **immutable logs**. Never edit after writing.

---

## Non-Negotiables

- Do not invent process or ceremony
- Do not assume undocumented context
- Session summaries are logs -- never edit after writing
- Discipline > convenience
- **Where a rule can be replaced by a mechanism, replace it.** A rule asks someone to remember; a mechanism removes the possibility. `-derivedDataPath` is the model — it doesn't remind anyone that the gate and the IDE share a cache, it stops them sharing one. This is not the same as inventing ceremony: ceremony adds a step to every future task, a mechanism deletes a failure mode. **When a rule has failed while being cited, it has proven it cannot be carried by memory — attach a procedure or a mechanism, or stop pretending it is enforced.**

---

## Product Architecture (synced from `docs/design/CLAUDE.md`)

The design-system CLAUDE.md is the source of truth for product architecture; this section mirrors its locked decisions so the two stay coherent. If a decision changes there, sync here in the same PR.

### Three primary objects (Clips · Memories · Projects)

The app is three tabs in capture→shape→build order: **Clips · Memories · Projects = Evidence · Context · Intent.** A **clip** is the atom (voice/photo/video/note), stored once. A **memory** references 1–N clips and adds a derived layer (title · summary · topics); clip↔memory is many-to-many. A **project** connects memories (many-to-many) — it does not contain or own them. **Cold launch lands on Memories** (what you open HiMem for); **Clips is a first-class tab**, and the standalone "Captured Clips" window is **retired** — its bench is now the Clips tab's default (New) view.

### Two capture paradigms

HiMem has two distinct capture modes. These are properties of **intent**, not platform — a surface can host either, though each surface has a current default.

- **Structured capture** — User intentionally creates a Memory. Reflective space. Clips and media flow into a container that already exists or is created on the spot. Memory-oriented from the first tap. *Today: phone direct-voice composer, phone append composer, iPad (when it ships).*
- **Ad-hoc capture** — User catches fragments. Brainstorms. Doesn't organize yet. Session-oriented; structure comes later via consolidation. *Today: watch, **and the phone Clips-tab + (ad-hoc)** (July 10 2026).* *Future possibilities (don't design for these now): Studio quick-capture, phone widget, Siri shortcut into the session inbox.*

The boundary isn't watch-vs-phone. It's "I'm capturing inside a container I'm building" vs "I'm catching something to sort out later." Don't bake "watch = ad-hoc" into anything fundamental.

**Captured Clips is the consolidation seam for ad-hoc captures**, regardless of which surface produced them — it is the Clips tab's default view, not a standalone window. The **session** is the right primary unit there: the natural grouping of what the user is moving through, and any session *may* become a memory (though it needn't).

### The consolidation ladder

Three layers, same dance at each scale:

1. **Clips → Session → Memory.** Done on the Clips tab. Bundling a session (**Start a Memory**) is consolidation at the smallest scale.
2. **Memories → Project membership.** Manual tagging. Mid-scale grouping.
3. **Project + Memories → Project summary.** Project Assist. High-scale synthesis.

At each layer: messy input → recognition → structure. Brainstorming is messy; reflection creates structure; memory formation is editorial. The product models that explicitly.

**The normal vs edge inversion on the Clips bench.** Most users, most of the time, see a session and bundle it. That's the normal flow. Clip-level tools (delete one, retry transcription, exclude accidental) are *exception handling*, accessed by expanding a session card. Don't put everyone in granular-management mode by default.

### Crucible token contract

The single source of truth for design tokens (colors, topic palette) is `docs/design/crucible.css`. iOS asset-catalog entries under `Assets.xcassets/Crucible/*.colorset` mirror it byte-for-byte. When the spec changes, both sides change in the same PR.

**Every token is a `light-dark(<light>, <dark>)` pair — both modes are locked, not just light.** All 47 colorsets carry a Dark-Appearance variant. Dark applies to *all* surfaces (the reflective/operational split is not enforced at the token layer), designed to read as *"lamp-lit book at night," not "Netflix title card."* On dark: paper `#000000`, ink `#F0E9DC`, ochre `#EC7442`, AI blue `#5BA4D6`. **Judge a surface against its own column** — `#C64A1C` on black is the deviation. Default appearance is `.system` (`Settings → Appearance` overrides); the watch is dark-native and ignores it. Full table: `docs/design/CLAUDE.md` § Palette.

**Topic-slug strings are a cross-platform contract.** The 16-swatch palette names (`ember`, `terracotta`, `clay`, … `slate`) defined in `docs/design/Crucible · topic palette spec.md` must match the asset-catalog entries (`topic-ember.colorset` etc.) AND the `Topic.paletteKey` Core Data values AND the Swift `topicSlug(for:)` hash output. Drift in any of these silently mis-renders chips. If a slug needs renaming, that's a data migration on every device.

---

_Governance derived from TheCombine (~/dev/TheCombine/) -- 2026-04-14_
