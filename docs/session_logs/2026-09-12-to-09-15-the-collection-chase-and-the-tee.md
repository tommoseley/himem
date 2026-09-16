# Session log · 2026-09-12 → 09-15 · the collection chase, four self-corrections, and the tee

Facts only. Immutable. **Written for a context-free reader.** Covers `69a172c..9a86081` (2 commits).

---

## Repo position

- Branch **`f8-overlay-and-wiring`** @ **`9a86081`**, **82 ahead of `main`**, **0 behind**, **0 unpushed**.
- **`main` @ `36ce159`** — deliberately behind.
- Code tree clean. `docs/design/` holds Tom's uncommitted work; **CC edited nothing there this session.**
- `MemoryStreamTests/DuplicateEdgeConvergenceTests.swift.held` unchanged — B26's deferred reconcile, `.held` so it never compiles. Not a pending red.

### Toolchain — diffed against the 09-11 21:45 baseline in the addendum

| Quantity | Baseline | This session | |
|---|---|---|---|
| macOS | 27.0 `26A5425a` | **27.0 `26A428`** | **MOVED** |
| CommandLineTools pkg | `…1787197235` | **`…1788430756`** | **MOVED** |
| `xcode-select -p` | `/Library/Developer/CommandLineTools` | unchanged | held |
| bare `xcodebuild` | errors | **still errors** | **guard intact** |
| Xcode-beta.app | 27.0 `27A5237l` | unchanged | held |
| iPhoneOS / WatchOS SDK | `24A5408c` / `24R5346a` | unchanged | held |
| Runtime pins | iOS 26.4.1 `23E254a` · watchOS 26.5 `23T570` | unchanged | held |

**The CLT install did NOT repoint `xcode-select`.** The addendum's ② inversion did not happen: a naive `xcodebuild` still fails loudly. It fired on CC's own recon call mid-session (`xcrun: error: unable to find utility "simctl"`), and again on Tom's paste of a `devicectl` command — the guard demonstrably works.

`softwareupdate --history` dates the change exactly: **macOS 27 installed 09-11 22:57:19**, reboot 23:00, **Command Line Tools for Xcode 27.0 at 23:11:01**. Neither is labelled beta.

**Because `sw_vers -buildVersion` moved, both gates this session are NEW BASELINES, not confirmations** — stated at the time, before the numbers were read.

### Gate — both read from result bundles, isolated `-derivedDataPath`, run sequentially, watch pair booted immediately before

| Scheme | Opening run | Closing run (with the tee) |
|---|---|---|
| `MemoryStream` | **1537 / 216** — 1526 passed, 3 skipped, **8 deliberate**, 0 crash lines | **1542 / 217** — 1531 passed, 3 skipped, **8 deliberate**, 0 crash lines |
| `Himem Watch Watch App` | **34 / 6**, 0 failed, 0 install failures | **34 / 6**, 0 failed, 0 install failures |

Both phone runs exited **65**, classified before being read: 0 compile errors, 0 launch-denial signatures, `Test run with` present ⇒ assertion failure. The two `ValidateEmbeddedBinary` hits are build-phase invocations on the widget and watch app, **not** the platform-mismatch error — 0 `BUILD FAILED`, no `error:` on either line.

The 8 are `SpeechAssetGate`, **membership re-derived rather than trusted**: 8 call sites across 6 test files, and the 8 failing identifiers map onto exactly those files. **The gate is a count, not a coverage claim** — those 8 legs are the only end-to-end record → compress → transcribe coverage and none of them ran.

Closing counts were **predicted before the run** (1537+5 cases, 216+1 suites) and matched.

**The watch runner-install failure did not return.** Clones demonstrably in use (`Clone 1 of iPhone 17 Pro Max`), 0 `-308`, 0 `Invalid device state`. `CoreSimulator.log` was therefore not read, and the macOS candidate stays untested.

---

## THE HEADLINE — five failed collections, and a true measurement pointed at the wrong subject

A wiped-install device pass ran to completion and **produced almost no reading**, for reasons that had nothing to do with the app.

### What the device pass established

- Wipe clean: container **93 files → 12**, `Documents/` empty.
- Cold launch **19:47:49 EDT**, and CloudKit's first import **ran and completed**: store rebuilt 0 → **8.3 MB by 19:49**.
- Reading #2's quantity, recovered from **Apple's** instrumentation (`PFCloudKitSetupAssistant`) rather than ours:

| Milestone | Time | From launch |
|---|---|---|
| Cold launch | 19:47:49 | — |
| `Successfully set up CloudKit integration for store` | 19:47:51.969 | **+3.0 s** |
| Arc armed (derived from the one surviving line) | 19:47:54.203 | +5.2 s |
| First import work item finished — first records in the store | 19:47:56.434 | **+7.4 s** |
| Last of 154 import work items | 19:49:37.016 | +108 s |

### THE INSTRUMENT FINDING, AND ITS CORRECTION IN THE SAME SESSION

Our `[HiMem][CKArc]` and `[HiMem][InboxDx]` lines were **absent** from the 2.3 GB sysdiagnose archive for the launch window, while 994 HiMem process lines from Apple subsystems sat in the same window. Across the whole archive — 09-08 → 09-15, 11,391 HiMem process lines — exactly **one** `[HiMem][` line existed.

**CC reported that as "a week of app usage produced one persisted line from `com.himem.app`", framed as a property of OUR logging.** It was a true measurement attached to the wrong subject.

**The control that dissolved it took thirty seconds and had not been run:** *does the archive contain ANY third-party subsystem?* In the 19:40–20:00 window — **138,522 lines, 527 subsystem tokens, essentially all `com.apple.*`.** The apparent non-Apple entries are message-text fragments and references to third-party *processes* from inside Apple subsystems.

**There is no third-party app subsystem logging in that archive at all. Not ours, not anyone's.** `DeviceLog` is not broken; neither is the arc.

> **The rule this produces, and it is the actionable half: before attributing an absence to the subject, check whether the instrument shows the same absence for a peer. An absence with no comparison class is a reading of the apparatus, not of the subject.** The discriminator was never more scrutiny of our own emitters.

This is the **fifth measurement class** — a well-formed reading of the wrong quantity — and the cleanest instance recorded: a correct count, a clean artifact, no error anywhere, and a wrong mapping from reading to claim.

### `log collect --device-udid` HAS NEVER WORKED ON THIS MACHINE

That is the finding, **not** "it broke". Five attempts across three device states:

| Attempt | Device state | Result |
|---|---|---|
| 1 | no sudo | exit 77 `Must be root` |
| 2 | sudo, phone locked | `Device not configured (6)` |
| 3 | sudo, phone unlocked/`connected`/`wired`/devmode on | `Device not configured (6)` |
| 4–5 | sysdiagnose without a TTY, then with one | consent notice; `Password:` prompt hung to timeout |

Nothing in any prior log records it working here. It was treated as the obvious instrument **because it looked like the right one** — the same shape as the rest of the stretch: well-formed effort pointed at an unvalidated tool.

**A `devicectl --console` bridge worked immediately** and proved emission: `[HiMem][Ubiquity] container resolved at …` live at 16:11:11.518. `NSLog` is a dual-channel probe — stderr (bridged) and unified log (archived) — which is what split emission from collection.

---

## The work

### `be6510b` · The inbox manifest docstring named the one path the code forbids

`InboxClip`'s class doc said the manifest lives at `Documents/Inbox/manifest.json` with audio beside it. Both halves wrong, and the first dangerous: `inboxRoot` (`:281`) resolves to sandbox **`Documents/ClipInbox/`**, and the comment directly above it warns `Documents/` is WatchConnectivity's staging tree — *"the delivered files vanish before we can copy them."* **The docstring pointed a reader at exactly the directory the code exists to avoid.**

Rewritten to name `inboxRoot` and `audioDirectory` as the authorities rather than restating literals — which is how this one rotted.

**Found the expensive way:** CC warned Tom that wiping would destroy the three stranded B29 clips, sourcing the warning from this docstring. Tom chose "back up first" on the strength of it. Both halves were false (below).

### `9a86081` · `DeviceLogFile` — a reading that does not depend on collection

Every `DeviceLog` line tees to `Library/Logs/device.log`; a reading is pulled with `devicectl device copy from` — no sudo, no password, no retention window, no dependency on third-party log persistence. **Per the CLAUDE.md non-negotiable, this replaces the rule "collect the archive within hours" with a mechanism.**

- **Unconditional, not `#if DEBUG`-gated** — a reading that exists only in a debug build cannot answer a question about a TestFlight build.
- **`DeviceLog` only, never `NSLog`.** Every `DeviceLog` line is already `privacy: .public` and structural per the 2026-08-23 rule; content stays private. No new exposure.
- **Not `Documents/`** — per `be6510b`'s warning. Rotation caps disk at 2 × 1 MiB. Lock at the owner, because size-check → rotate → append is the unit that must be atomic.
- Placed in `MemoryStreamApp.swift` beside `DeviceLog` (Reuse-First): the app target is **not** a file-system-synchronized group, so a new file would have required a `project.pbxproj` edit (`CloudKitArcLog.swift` is explicitly referenced 4×). `MemoryStreamTests` **is** synchronized, so the test file needed none.

**Guards (5), each mutation-verified, each biting only its named test:**

| Mutation | Bit |
|---|---|
| M1 drop the `inbox` tee | `everyDeviceLogCategoryReachesTheFile`, at the named assertion, file holding WC/Build/Launch and not Inbox |
| **M2 wrap the tee in `#if DEBUG`** | **`theTeeIsNotBuildGated` ONLY — all four behavioural tests passed** |
| M3 remove the owner lock | `concurrentAppendsDoNotTearLines` |
| M4 rotation never triggers | `rotationCapsTheFile` |

**M2 is the load-bearing one and demonstrates Guard-the-Caller rather than arguing it.** A DEBUG-compiled suite cannot see whether the tee is compiled out of Release, so the four behavioural tests passed while the property was broken. Only the mechanical source assertion caught it. The scanner constructs **no `Range` at all** (splits on markers) and self-tests four shapes including degenerate input, per the 2026-08-25 trap that cost 199 failures across 110 suites.

---

## Decisions and rulings (all Tom unless stated)

1. **Toolchain verified before any gate**; both gates recorded as new baselines because macOS moved.
2. **~17–21 s is RETIRED, not contradicted.** It was inferred and never measured. Baseline is now **setup +3.0 s, first records +7.4 s**, carried with its qualifiers: one sample, one device, one dataset, **Debug build**.
3. **`CD_M2M_JournalEntry_topics` gets the Release control before any diagnosis.** The `initializeCloudKitSchema` hypothesis is well-formed and is exactly the shape that died on the clone run — a real mechanism mistaken for the cause.
4. **Back up `Documents/Inbox/` before the wipe**, then wipe. (Condition satisfied vacuously — see corrections.)
5. **Skip the sysdiagnose control** on third-party persistence: it characterises an instrument being replaced. Wrong order.
6. **Build the tee.** Thirty lines plus a rotation cap against five failed collections is an obvious trade.
7. **The tee carries the same category/level discipline as `DeviceLog`** — written unconditionally, not mirroring whatever `Logger` decided to persist.
8. **D1 is ruled open for reconsideration** (below).
9. **Device pass deferred** — a fresh piece of work; this session produced four self-corrections.

**Options closed (do not re-litigate):**

- **`log collect --device-udid` as the device-reading instrument — abandoned on evidence.** Five attempts, three device states, never established as working here.
- **Archive-based collection as the primary device instrument — superseded by the tee.**

---

## D1 — the premise expired

D1 reads *"macOS 27 beta hosts no release Xcode… only true submit blocker."* **macOS 27 is no longer beta.**

| Xcode | build | released | **min macOS** | iOS SDK | watchOS SDK |
|---|---|---|---|---|---|
| **27.0 RC** | **`27A266a`** | **2026-09-09** | **26.6** | **`24A430`** | **`24R360`** |
| 27.0 beta 6 | `27A5252f` | 2026-08-24 | 26.4 | `24A5422a` | `24R5355a` |
| 27.0 beta 5 — **installed** | `27A5237l` | 2026-08-10 | 26.4 | `24A5408c` | `24R5346a` |

- **Xcode 27.0 RC requires macOS 26.6; the host runs 27.0. It installs here.** None of D1's three workarounds (Xcode Cloud, second Mac, downgrade to 26.6) is needed.
- **The RC's SDKs are release-form** (`24A430`, `24R360` — no `5xxx` seed digit), taking submission off the F6h seed-window axis entirely.
- Apple's 09-09 announcement names it: *"Download the Xcode 27 Release Candidate… submit for review to the App Store."* Also: **from April 2027, uploads must be built with the iOS 27 / watchOS 27 SDK or later.**
- **The installed toolchain is now two seeds stale** — the exact mechanism behind the 08-22 rejection, further along.

**CC's proposal, not built:** install the RC alongside the betas (as `27A5228h` already is), keep `DEVELOPER_DIR` on `Xcode-beta.app` for every gate, use the RC **only for archive/upload** — so the submission path moves without destroying gate comparability.

---

## Retractions and corrections

**Four this session.**

1. **"The wipe will destroy the three stranded B29 clips."** **Wrong in both halves.** Sourced from the stale docstring (`be6510b`); the bench manifest does not exist on the device (`Documents/ClipInbox/` empty, no JSON files anywhere in a complete 93-file listing), and `40D421BB` / `DDA80712` / `48D2EF6E` appear nowhere — not in the device container, not in the ubiquity container. The app's data container was created **08-25 1:24 PM**, so the evidence had been gone for three weeks. **Tom made a decision on this warning.** The backup taken was of the **ubiquity** `Documents/Inbox/` (18 `.caf`), which an uninstall never threatened — kept anyway, since the materializer moves files out when it bundles.
2. **"`26A428` is a GA/shipped build."** Apple's release page names it **"macOS 27.0 RC (26A428)", dated 09-09**. Read off the `softwareupdate --history` label "macOS 27" with no "beta".
3. **"A week of app usage produced one persisted line from `com.himem.app`," framed as our logging being broken.** The count was right; the subject was the artifact. Disconfirmed by a control in the same session, before anything rested on it. **Propagation: none** — no commit or ruling carried it.
4. **The `.serialized` rationale in `DeviceLogFileTests` claimed "suite-local" state.** False: only this suite *sets* `directoryOverride`, but the **sink is reachable from every suite** via `DeviceLog`. The concurrency test asserted a total line count, **passed in isolation, and failed at 1542 cases** when other suites' lines landed in the same file. That is CLAUDE.md § Test Concurrency's retired rule reappearing verbatim, written into a doc comment justifying it. Assertion rescoped to its own markers; **M3 re-verified against the corrected assertion rather than inheriting the old evidence.**

*Two instrument mis-readings, corrected within the hour, no conclusion rested on either:* a `head -25` of a 93-file container listing was nearly read as "no manifest"; and the first `du -sh` of the ubiquity Inbox read **0 B** because the files are cloud-dataless locally — the copy materialised 1.8 MB.

---

## What was NOT verified

**This is an absence section. It is the part most expensive to inherit wrong.**

- **THE TEE IS UNPROVEN ON HARDWARE.** Every guard runs in the simulator. The file has never been written on a device and never pulled with `devicectl device copy from`. **It is a mechanism that SHOULD remove the collection class, not one that has.**
- **B29 is unanswered, and this run could not have answered it.** `Documents/ClipInbox/` stayed empty through the whole window, so nothing was in `awaitingBytes`, so `awaitDownloads` plausibly never armed — and zero `InboxDx` lines survived collection, so even the arming receipt is unreadable. **Predicted in advance as the "proves nothing" row.** B29 needs a *manufactured* stranded clip: a watch capture caught between iCloud arrival and local download.
- **The import FAILED and the cause is unknown.** `_importFinishedWithResult(1398): Import failed with error: <private>` at 19:49:37.023, preceded by **ten** `CoreData: fault: Already have a mirrored relationship registered for this key: CD_M2M_JournalEntry_topics` in four seconds. It is the **only** `_importFinishedWithResult` in the archive; every other mirroring line across a week is `_exportFinished`. Exports resumed immediately and were still working at 00:02. **First parse of this log family; the error text is `<private>`.** Debug-only `initializeCloudKitSchema` ran at 19:47:50.758 and is the leading hypothesis — **untested, and the control is cheap.**
- **The mechanism behind third-party log absence is UNKNOWN** and recorded as unknown. The one surviving line was 16 h old at collection and the missing ones 20 h; that fits a shorter third-party persistence window, but it is a **sample of two**. The tee makes it moot rather than answering it.
- **The arc is vindicated on hardware, by one line.** `export ended ok +15254711ms` puts `armedAt` at 19:47:54.2 — our launch — and it was still logging **4 h 14 m later**, never having removed its observer. Under the pre-`ef41a91` coupled design it would have died at +3 s. **This is the arc's first real-world evidence.** It has still never logged a *setup* event we could read.
- **The `UbiquityStore` / `Documents/Inbox/` conflict is LATENT, flagged not fixed.** `documentsRoot` falls back to sandbox `Documents` when the container is unresolved, so `inboxDirectory` becomes the path `InboxManifest.inboxRoot` forbids — and `subdirectory()` **creates it as a side effect of a read**. It did **not** fire: no sandbox `Documents/Inbox/` after a full cold launch and import, and `container resolved` confirmed positively from the console bridge. The existing sandbox-fallback note at `UbiquityStore:135–139` reasons about the *metadata query* and does not reach this. **Wants a ruling and a bug-first cycle, not a quiet patch.**
- **Two mutation runs were discarded as NOT A RED** — 0 compile errors, no `Test run with`, `Busy ("Application failed preflight checks")`. The denial **survived** `simctl shutdown all` ⇒ device-specific; `E3C0710E` erased and recreated **on the same runtime** (`iOS-26-4` verified before and after). **No runtime rotation.**
- **`CoreSimulator.log` was not read** — the watch gate passed, so there was nothing to read it about.
- **Enumerations swept mechanically:** `SpeechAssetGate` membership (8 call sites / 6 files, re-derived); the complete 93-file and 113-file device container listings (grepped whole, not headed); every `InboxDx` emitter in `WatchSessionDelegate` (12, of which **two** contain `re-entering sweep`); all Xcode 27 builds with min-macOS and SDKs. **Trusted rather than re-counted:** C2 step 5's *"~59 source-scan assertions"*, still inherited.

---

## Open threads

- **The device pass with the tee in place** — proves the mechanism *and* takes B29's reading in one go. Needs a manufactured stranded clip for the B29 half.
- **The Release control on `CD_M2M_JournalEntry_topics`** (ruling 3).
- **D1** — ruled open; the deciding fact is recorded above.
- **The `Documents/Inbox/` fallback conflict** — needs a ruling.
- **The two-emitter trap, recorded so it is not rediscovered:** `WatchSessionDelegate:508` emits `retry timer fired — re-entering sweep` and `:570` emits `ubiquity update — re-entering sweep`. **Only `:570` is B29's close condition.** A grep on the shared phrase closes B29 falsely — a correct match against the wrong emitter, the same wrong-quantity family.
- **The memory canvas** — scoped, not sequenced.
- **④ out-of-range** — the delivered-awaiting-ack gate has never been exercised.
- Carried: **B26's reconcile** (held) · **B27's partition axis** · **B30** · the layout flip · **C2 step 5** · **C1/C8** · D3 · D4 · D7 · D9b · F34/C15 · B19.

## Risks

- **`main` and `f8` are 82 apart.** Pushed, so the exposure is integration. Conflict-watch files: `ClipsTabView.swift`, `EntryExpandedView.swift`, `ChronologicalCaptureStream.swift`.
- **The tee ships unproven.** It writes on every launch of every build including TestFlight, and no hardware run has confirmed the file appears or is pullable.
- **The installed toolchain is two seeds stale**, so any upload from it is likely to be rejected.
- **The CloudKit import failure is unexplained**, and a wiped install is the only condition that has surfaced it.
- **The 8 red legs still read as a regression** to anyone who skips the qualification.
- Four OS changes now sit across the watch-gate gap; correlation remains unattributable and no control is available.
