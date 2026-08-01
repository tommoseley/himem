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

### Measurement Discipline (Mandatory)

**Name what a measurement actually is before building on it.** Every diagnostic failure in this project has been a signal that *looked* authoritative because it was well-formed, and was in fact truncated, aggregated, or overloaded. None looked like an error at the moment it was read — which is why care alone doesn't catch them.

- **Never let `head` (or any limit) bound a completeness claim.** "No callers exist" is a statement about the whole codebase; a `head -8` that filled with matches from one test file cannot support it. If the conclusion is *"there are none"*, the command must be able to show all of them — filter the noise out (`grep -v`), don't cap the output.
- **Count by the structure you mean.** Counting unique log *lines* is not counting test *cases*: interleaved timestamps split one result line in two, and the halves de-duplicate as distinct entries. Aggregate on the actual unit (per-suite tallies), not on incidental text.
- **Never treat one exit code as one meaning.** See the Bug-First constraint above: `xcodebuild` returns **65** for compile failure, assertion failure, *and* launch/infrastructure failure. **A fourth 65: `ValidateEmbeddedBinary` refusing a platform mismatch on the watch scheme** — *"This target is built for iOS but contains embedded content (Himem Watch Watch App.app) built for watchOS Simulator."* It is a **build** failure, so it shares the launch failure's signature (0 compile errors, no `Test run with` line, no `Failing tests:` block) and reads as a red. Cause: the watch simulator's **paired iPhone simulator was shut down**, so no simulator destination resolved for the container app and it built for `iphoneos` instead. Remedy: `xcrun simctl list pairs`, then boot **both halves of the pair** — the watch sim's partner is not necessarily the phone scheme's canonical destination. Detect: `grep ValidateEmbeddedBinary` in the log tail. *(Hit 2026-07-31 establishing the session baseline; the re-run with the pair booted was 34/6 green, unchanged.)* **It also exits 66 when the working directory contains no Xcode project** — same family as the 65 overload, and it reads as a test failure in a scripted loop because the only difference is one line near the top of the log (`error: The directory … does not contain an Xcode project`). Pass `-project <path>` explicitly rather than relying on the shell's current directory, which does not survive a `cd` in an earlier command. *(Hit 2026-07-31 mid-F23: a `git commit` run from the repo root moved the working directory, and the next test invocation "failed" without running.)*
- **Rotating a simulator must not change the runtime.** The phone gate is pinned to an **iOS 26.4** simulator, and the known-8 `SpeechAssetGate` failures exist *because* the en_US speech asset is `unsupported` there. A 26.5 runtime may resolve that asset differently and **silently move the failure count** — a run returning 5 failures, or 0, is not good news, it is an *incomparable* measurement that destroys the baseline while looking like a fix. Simulator attrition forces rotation often on this machine (four consumed in three days), and "grab any available iPhone" is exactly how the runtime drifts inside a routine step nobody thinks of as a decision. **Erase and recreate on the same runtime rather than moving runtime;** if the runtime genuinely must move, re-cut the baseline explicitly and say so. *(Pinned 2026-07-31.)*
- **A conclusion inherits the weakness of its weakest input.** When a finding rests on a measurement, state the measurement alongside it, so a wrong reading is visible as a wrong reading rather than propagating as fact.

*Origin: three instances in one session (2026-07-29/30) — a truncated `grep` producing "P0-3 is unwired" when it was fully wired; a watch-suite count reported as 27 when it was 28; and exit 65 read as an assertion failure when it was twice a compile error and once a simulator launch denial.*

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

### Test Concurrency and Shared Singletons

Swift Testing runs `@Test` methods inside a `@Suite` in parallel by default. Tests that touch non-thread-safe shared singletons crash with `libsystem_malloc.dylib: Abort Cause` errors when run concurrently.

Known offenders in this codebase:

- `LocalEntityExtractor.shared` — uses an `NLTagger` instance which isn't thread-safe.

**Rule:** mark any suite that exercises a shared non-thread-safe API with `@Suite(.serialized)` and leave a comment naming the reason. Example: `ProcessingEngineFallbackTests`.

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
