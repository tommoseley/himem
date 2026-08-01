# Session log · 2026-07-31 (evening) · F23 Tiers 1–3

Facts only. Immutable. **Written for a context-free reader** — assume nothing survives except files and git. Covers everything after `0898d75` (the 07-31 pm handoff).

---

## Repo position

- Branch **`f8-overlay-and-wiring`** @ **`5f81dae`**.
- **19 commits** this session.
- **66 ahead of `main`**, **1 behind** (main still holds the New-lens fix this branch never took).
- **37 ahead of `origin/f8-overlay-and-wiring`**, 0 behind. **Nothing from 07-30, 07-31, or this session is pushed.**
- **Working tree clean of tracked code changes.** Design-domain files under `docs/design/` remain modified/untracked — Tom's; do not commit. Add design files by explicit path only.

### Gate — READ THE QUALIFICATION

| Scheme | Result | Destination |
|---|---|---|
| `MemoryStream` | **1198 cases / 169 suites** — 1187 passed, 3 documented skips, **8 deliberate failures** | sim iPhone 17 Pro Max `109A1381` |
| `Himem Watch Watch App` | **34 cases / 6 suites, 0 failed** | watch Series 11 46mm `B17233F6`, UITests skipped |

**The 8 failures are expected and permanent on this machine.** They are `SpeechAssetGate` — the transcription round-trip's coverage, made loud this session (`d74680c`). `AssetInventory` reports the en_US speech model **`unsupported`** on the iOS 26.4 simulator; it cannot be downloaded here (verified by running the production install path). The failure text names the cause and the remedy.

**This is not a regression. A green run on this machine is now impossible and would itself be suspicious.** The 8 clear only where the speech model is supported — a real device, or a simulator runtime that ships the assets.

Prior to `d74680c`, those same 8 legs `print`ed and `return`ed, which reports as **passed**. So every gate reported earlier on 2026-07-31 — including "1147 passed" and "1195 passed" — contained **zero** end-to-end transcription coverage while reading as full coverage. Those numbers were accurate as counts and weaker than they read.

Toolchain unchanged: Xcode 27.0 beta 4 via `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.

---

## Scope

Tom ruled the whole F23 tier list, in order. All three tiers closed this session.

**Tier 1** (T1.1 landed pre-session as `fcb378b`): `a278507` `1f189d5` `7ddcba6` `3cd6c98`
**Tier 2**: `03e6485` `b49203a` `9deb27c` `49156dd` `c4f22c5` `7b17296` `73a7859` `0bbf6a0`, plus `ab1f8a6` (unplanned, blocking)
**Tier 3**: `88a6bcc` `03ba471` `c3a7fc8` `5f81dae`
**Governance**: `e3cc8ac`
**F22 completion**: `3cd6c98`
**Transcription gate**: `d74680c`

---

## Decisions and rulings

- **Silence for secondary surfaces (F22)** — approved. Three surfaces speak with ruled copy; eleven render nothing while importing. Rejected: inventing eleven more "getting your…" lines.
- **Three new copy strings approved**: "Couldn't remove this clip. Try again." · "Couldn't create this memory. Try again." · "Couldn't add these clips. Try again." All parallel construction with the existing approved sibling.
- **The manifest-refusal string stays technical** — matching the precedent two functions away beats inventing Crucible-voice copy for a can't-happen path; a user-facing sentence implies a user-facing situation.
- **`SessionListView` keeps the F22 gate.** Gating withholds a claim for ≤3s on a fresh install; exempting where the ruling said "gate" would be a silent deviation.
- **`.strict` — closed.** Correct the docs, do not make it real. Summary/title grounding is `.relaxed` on **both** tiers by a deliberate 2026-07-24 decision (strict exact-substring flagged legitimate name expansions and discarded whole summaries). `.strict` governs only the ungrounded-mention drop, plus one correct use in `ProjectAssistViewModel.deriveShortSummary`. **Rejected:** re-imposing strict — it means accepting that regression or calibrating a third strictness against a platform-controlled 3B model with no repeatable harness. Wiring now pinned in both directions.
- **Transcription tests: (a) now, (b) post-tag**, after trying the install first. **Rejected: a local opt-out** — an opt-out is how the gap hid.
- **B10 shape A** — make `ensureModelReady` throw; caller 2 absorbs at the call site. **Rejected: B** (rename only — the defect renamed) and **C** (ignorable return code — the pattern the new rule distrusts).
- **Verify-first for the comment pass** — do not take the audit's characterisations as inputs to a rewrite.
- **`Identifiers.inboxArrival` deleted** — dead code kept under a note explaining it is dead is how phantom comments start.
- **Not started, by standing ruling:** the error-surface rebuild and the clip-storage seam rebuild. Both post-tag.

---

## Retractions and corrections

**Six audit errors found**, five in the first F23 pass and one in this session's own work. All recorded in `docs/audits/2026-07-31-f23-second-scan-brief.md`.

1. **`DisplayModels:27-30` misattributed.** Recorded as "no readers; the eyebrow reads Core Data". It has a reader — `EntryExpandedView.entry` **is** an `EntryDisplayModel` and `:918` reads the field. Acting on the finding would have turned a true comment false **and left the real defect** (omission from `==`) in place. The `==` fix landed and is scoped **latent, not live**: no `EquatableView`, no `.equatable()`, no `removeDuplicates`, no equality-gated publish.
2. **Transcription skip sites undercounted** — stated 5 tests / 4 files; actually **8 sites / 6 files**.
3. **`TranscriptionServiceLongFormTests:40` missed entirely.**
4. **"Permanently stranded" overstated** — the transcoder's failure mode leaves a clip *waiting*, not stranded; retries exhaust and later reachability/scenePhase triggers re-enter the send path.
5. **`FirstImportState`'s "seven surfaces"** — the measured figure is 34 empty-state sites, 14 store-backed.
6. **CC's own `.strict` sweep was production-only** and missed the same false claim in **two test files** (`OnDeviceOrganizerCalibrationTests:149`, `TruthReconcilerTests:9`). Both corrected; a no-cap re-sweep is clean. This is CC's own instance of the incomplete-enumeration class.

**CC reproduced a defect class one hour after closing it.** The first `:614` attempt added `finishAppend` and left the early `guard … return` above it — four green seam tests, production still silently returning. Fixed structurally (single exit) and guarded by `appendHasNoEarlyExitPastTheDecision`, mutation-verified.

---

## What was NOT verified

**Everything below is an absence. It is the section most likely to be skipped and the most expensive to inherit wrong.**

- **Nothing this session is device-verified.** 19 commits, simulator-only. Several touch the capture path.
- **`SpeechService` (B10) has no test coverage and needs the speech model.** Shape A's safety rests on **reading plus preserved control flow**, not on a red-green cycle. It touches live-analyzer setup. The one observable difference is two added NSLog lines on failure paths — disclosed before building.
- **The 8 transcription legs have never run on this machine.** The record → compress → transcribe round trip is unexercised here, this session and every session before it.
- **`ensureModelReady`'s `.installationUnavailable` and `.unknownStatus` paths are unexercised.** Only `.unsupported` was observed.
- **The F22 fix only ever runs on a fresh install** — the path with the least device history and no repeatable dogfood. `FirstImportStateTests` is not the durable half; it is the only half.
- **The error banner may not draw** from `PlaceClipSheet` / `CreateMemoryFromClipsSheet`. Those sheets are presented from modals and `JournalErrorBanner` renders beneath. The observable win is the sheet staying open, **not** that the user reads a message. That only becomes true with the error-surface rebuild.
- **Enumerations trusted rather than re-counted:** the audit's Tier-2/Tier-3 item lists were re-verified for everything acted on, but items never acted on were not re-counted. Given six enumeration errors, treat any unacted finding's count as unverified.
- **Guards mutation-verified this session:** `GroundingStrictnessWiringTests`, `InboxManifestBadgeSyncTests`, `WatchTransferAudioTranscoderTests` caller gate, `AddToMemorySilentNoOpTests` caller gate, `EnsureModelReadyCallerTests`. **Not mutation-verified:** the F22 scanner (self-tested for both blind spots, but no live mutation), `SingleAudioPlayerOwnerTests` (verified red against the real pre-fix defect instead), `OrphanSweepReachabilityTests` (pre-session).
- **`ProjectDetailView` z-order still unverified** — if it is a pushed destination, its 8 `ProjectViewModel` error reports fall under the error-surface finding too.

---

## Open threads

- **Device pass — now the bottleneck.** Queue: F18 iPad capture (live preview + landscape) · F16 cold-read · the three summary-eyebrow states · the out-of-range provocation · F6g's runtime-issue breakpoint stack · **B10's live capture on a system whose locale asset is unsupported** (new, and the one with no test behind it).
- **Post-tag rebuilds**, untouched: error surface (59 report sites, one unreachable renderer) · clip-storage seam (device-local manifest describing device-shared files). The `clips = []` cross-surface finding belongs to the latter's brief.
- **Second F23 scan** — brief written; not commissioned.
- **`:614`'s sibling** and other unacted audit items remain in the action-items inventory.
- Carried from the prior handoff: App Store submission toolchain · iPad screenshots · F21 · `v1.0-b27` re-cut and the `f8 → main` merge · `GET /himem/epigraphs` 404 · Tom's J3, the bench action's name, the walkthrough copy cold-read.

## Risks

- **The 8 red legs will read as a regression to anyone who doesn't read the qualification above.**
- **`ClipsTabView.swift` and `EntryExpandedView.swift` were edited again this session** — both are the `f8 → main` conflict-watch files, and that merge is harder than it was.
- **Judi tests a beta-SDK binary**; the submitted build will use a different toolchain and SDK.
- **The simulator throws `SBMainWorkspace` launch denials repeatedly** on this machine — environmental. A denial that survives a shutdown is device-specific (switch simulators); one that clears after a shutdown was busy state (re-run). Hit ~5 times this session.
- **Six weeks elapsed between the watch fixing `clips = []` and the phone fixing the identical defect.** Nothing prevents the next such divergence; that is the seventh class in the second-scan brief.
