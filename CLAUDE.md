# CLAUDE.md - himem

## Purpose

himem is a new project. This file establishes development governance — the engineering discipline that applies regardless of what himem becomes.

These rules are derived from battle-tested governance in The Combine (`~/dev/TheCombine/`).

---

## Project Root

**Filesystem path:** `~/dev/himem/`

---

## Development Governance

### Bug-First Testing Rule (Mandatory)

When a runtime error, exception, or incorrect behavior is observed, the following sequence **MUST** be followed:

1. **Reproduce First** -- A failing automated test MUST be written that reproduces the observed behavior. The test must fail for the same reason the runtime behavior failed.
2. **Verify Failure** -- The test MUST be executed and verified to fail before any code changes are made.
3. **Fix the Code** -- Only after the failure is verified may code be modified to correct the issue.
4. **Verify Resolution** -- The test MUST pass after the fix. No fix is considered complete unless the reproducing test passes.

#### Constraints

- Tests MUST NOT be written after the fix to prove correctness.
- Code MUST NOT be changed before a reproducing test exists.
- If a bug cannot be reliably reproduced in a test, the issue MUST be escalated rather than patched heuristically.
- Vibe-based fixes are explicitly disallowed.

This rule applies to all runtime defects including: exceptions, incorrect outputs, state corruption, and boundary condition failures.

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

### Simplicity First

- Make every change as simple as possible.
- Find root causes, not symptoms.
- No temporary fixes without a tech debt entry.
- Changes should only touch what is necessary.
- If a fix feels hacky, pause and find the elegant solution.

### Verification Before Done

- Never mark a task complete without proving it works.
- Run tests, check logs, demonstrate correctness.
- "Does this look right?" is not verification. Tests passing is verification.

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

_Governance derived from TheCombine (~/dev/TheCombine/) -- 2026-04-14_
