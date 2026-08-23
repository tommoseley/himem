# Session log · 2026-08-22 → 08-23 · the seed window, confirmed by fix

Facts only. Immutable. **Written for a context-free reader.** Covers `f477c95..0c2b8f8` (1 commit). Ship session, not a rebuild session.

---

## Repo position

- Branch **`f8-overlay-and-wiring`** @ **`0c2b8f8`**, **59 ahead of `main`**, 0 unpushed at close.
- **`main` @ `36ce159`** — deliberately behind; every C2 rebuild commit lives on `f8` only.
- Code tree **clean**. `docs/design/` holds Tom's uncommitted work (6 modified, 6 untracked) and was not touched.
- **One deliberate tracked artefact, unchanged:** `MemoryStreamTests/DuplicateEdgeConvergenceTests.swift.held` — B26's deferred reconcile, 238 lines, survivor policy complete including the nil-`linkedAt` ruling at `:83`–`:101`. `.held` so it never compiles. Not a pending red.
- The 2026-08-15→08-19 log discrepancy the previous log flagged is **closed** — committed in `7fffe2e`.

### Gates — TWO PAIRS THIS SESSION, ON DIFFERENT TOOLCHAINS. THEY ARE NOT ONE MEASUREMENT.

**Pair A · session-open pre-flight, Xcode 27 Beta 4 (`27A5228h`) / iOS SDK `24A5390e` / watchOS SDK `24R5325e`**

| Scheme | Result | Destination |
|---|---|---|
| `MemoryStream` | **1507 cases / 213 suites** — 1496 passed, 3 skips, **8 deliberate failures**, **0 crash lines** | sim `E3C0710E` (**iOS 26.4.1**) |
| `Himem Watch Watch App` | **34 cases / 6 suites, 0 failed, 0 crash lines** | watch `B17233F6` + paired `74EED5FE` (**watchOS 26.5**) |

Matched the inherited baseline exactly. The three commits since the prior log (`a432fd2`, `7fffe2e`, `f477c95`) touch only `CLAUDE.md` and two session logs — zero source — which is why the numbers could not have moved.

**Pair B · RE-CUT BASELINE, Xcode 27 Beta 5 (`27A5237l`) / iOS SDK `24A5408c` / watchOS SDK `24R5346a`**

| Scheme | Result | Destination |
|---|---|---|
| `MemoryStream` | **1507 cases / 213 suites** — 1496 passed, 3 skips, **8 deliberate failures**, **0 crash lines** | sim `E3C0710E` (**iOS 26.4.1**) |
| `Himem Watch Watch App` | **34 cases / 6 suites, 0 failed, 0 crash lines** | watch `B17233F6` + paired `74EED5FE` (**watchOS 26.5**) |

**PAIR B IS A NEW BASELINE AND IS NOT COMPARABLE TO PAIR A.** Three variables moved at once: toolchain build, iOS SDK, watchOS SDK. **The counts coincide, and the coincidence is not continuity.** The re-cut was declared *before* the run, stating that a different number would not be a regression; the corollary is that the identical number is not a pass-through. Any future citation must carry the toolchain: *1507/213 on `27A5237l` / `24A5408c` / `24R5346a`*.

**The simulator runtimes did not move** — `iOS_23E254a` (26.4.1) and `watchOS_23T570` (26.5) pinned throughout, and no `24A5408c` runtime was pulled in when Beta 5 installed (declined at install time, verified after). One variable by design: the toolchain.

Both pairs read from the result bundle via `scripts/gate-report.sh` with isolated `-derivedDataPath`, `DEVELOPER_DIR` pinned, run **sequentially** with the watch pair booted immediately before its invocation. Exit codes read from a captured `$?`.

**Both `MemoryStream` runs exited 65, and both were identified before being read:** 0 on the format-independent compile detector (`^/.*: error: `), a `Test run with` line present, no `ValidateEmbeddedBinary` error, 0 crash lines ⇒ eight assertion failures, not a compile, launch, or platform-mismatch failure.

**The 8 are `SpeechAssetGate`.** Membership was derived **mechanically from source before each run and never reused** — the call sites re-swept (`8 sites across 6 files`), each resolved to its enclosing `func` and its **top-level** type declaration per the 08-19 `DummyError` correction, then `diff`ed against the bundle. Byte-identical both times, and the two independent derivations were byte-identical to each other.

**The gate is a count, not a coverage claim.** Those 8 legs are the only end-to-end coverage of record → compress → transcribe and **none ran** on either pair; this machine reports en_US as `unsupported` on the pinned 26.4.1 runtime. That the 8 persisted across the SDK change is expected — the runtime never moved.

---

## Scope and rulings (all Tom unless stated)

1. **Install Beta 5 and archive — the path to Judi tonight.** Upload is not gated on the re-cut; record the re-cut after.
2. **Declare the gate re-cut explicitly** when run: new compiler, new iOS and watchOS SDKs, so the pair is a new baseline.
3. **Verify the toolchain actually moved before archiving** — `DTXcodeBuild` must read `27A5237l` and `DTSDKBuild` must no longer be `24A5390e`. If either is unchanged, the replace didn't take and there is no point archiving. *(This ruling is what caught the failure below.)*
4. **Decline the iOS 27 simulator runtime** at Beta 5 install, to protect the gate pins.
5. **F6h's correction is the durable finding** — record it as governance.
6. **Keep Beta 4 and the `.xip` until Judi has actually run the build.** Reclaim after.
7. **Stand up Xcode Cloud in parallel**; first thing to establish is which Xcode versions it offers.

**Options closed (do not re-litigate):**

- **"F6h's acceptance predated the check firing" — FALSE.** The check was firing on 2026-07-30; build 28 *passed* it. Closed by measurement, not argument.
- **"The rejection was on the App Store submission path" — FALSE.** Tom confirmed it arrived as an App Store Connect email **after processing**, not a validation dialog, with **no ITMS code**. TestFlight path.
- **A rebuild on the same toolchain — worthless.** Demonstrated: the 21:38 re-archive was stamp-for-stamp identical to the 21:03 one.

---

## THE HEADLINE — the seed window, confirmed by fix rather than by argument

Upload rejected with **"Unsupported SDK or Xcode version"**, an App Store Connect email after processing, no ITMS code.

**The measurement that settled it.** The 2026-07-30 archives were still on disk, so the accepted and rejected builds were compared directly rather than reasoned about:

| Stamp | 07-30 → **accepted** as build 28 | 08-22 → **rejected** |
|---|---|---|
| `DTXcodeBuild` | **27A5228h** | **27A5228h** |
| `DTSDKBuild` | **24A5390e** | **24A5390e** |
| `DTPlatformBuild` | 24A5390e | 24A5390e |
| `BuildMachineOSBuild` | 26A5388g | 26A5388g |
| `MinimumOSVersion` | 26.0 | 26.0 |

**Byte-identical toolchain. Identical input, different verdict ⇒ the change was on Apple's side.** That conclusion does not depend on reading the rejection text.

**What moved:** Xcode 27 Beta 5 (`27A5237l`, iOS SDK `24A5408c`) shipped **2026-08-10**. On 07-30 Beta 4 was the *current* seed; on 08-22 it was one seed stale, twelve days old. App Store Connect accepts beta-SDK builds for TestFlight from the current seed. **The rule never tightened; the window slid.** Apple's own upcoming-requirements page states only the floor (iOS 26 SDK or later, since 2026-04-28) and says nothing about seeds — which is why this was never derivable from documentation, in July or now.

**CONFIRMED BY FIX, WHICH IS THE STRONGEST FORM AVAILABLE.** Identical tree, identical `CFBundleVersion` (28), only the toolchain changed → **upload succeeded, build is in TestFlight.** A single-variable intervention reproducing the accept.

---

## THE TOOLCHAIN SWAP THAT DIDN'T HAPPEN — and the mtime trap that hid it

**Beta 5 was downloaded and expanded, and never moved into place.** It sat at **`~/Downloads/Xcode-beta.app`** while `/Applications/Xcode-beta.app` remained Beta 4. Every build after the "install" — including a re-archive at 21:38 that was reported as a rebuild — used the stale toolchain. Ruling 3 is the only reason this was caught before another upload.

**THE MTIME TRAP, and it is the reusable half.** The expanded app's directory and binary mtimes read **2026-08-06** — three weeks stale, and older than the `.xip`'s own download timestamp of 21:51 the same evening. **`xip --expand` preserves the archive's internal timestamps**, so an app expanded minutes ago can look months old. The mtime is a property of the archive's contents, not of the expansion.

- **The version string was the only reliable discriminator**, and reading it settled it in one command: `CFBundleShortVersionString 27.0`, `ProductBuildVersion 27A5237l`, iPhoneOS SDK `24A5408c`, WatchOS SDK `24R5346a`.
- **Directory size is not a size.** `ls -la` showed `96` bytes for the app bundle — the directory entry, not the payload. `du -sh` showed **3.6 G**. A "husk" was called on the strength of the 96 and retracted in the same turn by measuring.

**The swap, done non-destructively:** `/Applications/Xcode-beta.app` → `/Applications/Xcode-beta-27A5228h.app` (preserved, reversible), then Beta 5 moved in. Preconditions checked first: Xcode not running, `/Applications` writable without sudo, both paths on `/dev/disk3s5` so the move is a rename. Verified after: `xcodebuild -version` → `27A5237l`, no `com.apple.quarantine` xattr, signature valid, runtimes unchanged.

**Archive on the new toolchain:** `ARCHIVE SUCCEEDED`, rc 0, **0 compile errors** — the tree builds clean against `24A5408c`, which was the open risk. Verified from the bundle across all three binaries: iOS app `DTXcodeBuild 27A5237l` / `DTSDKBuild 24A5408c`; embedded watch app and widget both `24R5346a`; `MinimumOSVersion 26.0` throughout. Written to a **plain-ASCII archive name** (`HiMem-27A5237l`) deliberately, per the U+202F fault below.

---

## GOVERNANCE — two entries, committed `0c2b8f8`

### 1 · An empirical claim about a moving target must carry its seed and date INSIDE the claim

F6h recorded **"TestFlight accepts Xcode 27-beta builds — established empirically"** from one upload on 2026-07-30. The observation was correct; the generalisation was not available from it. **A sample of one taken from inside the accepted window cannot see the window** — nothing about a successful upload reveals that acceptance was conditional on being the *current* seed rather than *a* beta seed.

**The cost is not being wrong later — it is being re-asserted later.** This session's own pre-flight repeated the stale version ("blocks App Store submission, not TestFlight") **rather than re-deriving it**, hours before the rejection arrived, and it reached a release decision that way. A claim with no expiry attached does not decay quietly; it gets quoted.

- **The tell is a claim about someone else's system stated with no version and no date.** *"TestFlight accepts beta-SDK builds"* has neither. *"TestFlight accepted iOS SDK `24A5390e` on 2026-07-30, when that was the current seed"* has both, and expires visibly.
- **Corollary:** re-verify an inherited empirical claim before a release depends on it, and treat a missing date on one as a defect in the claim.

### 2 · Never retype a path a tool gave you — consume it

**`find -print0` into `read -r -d ''`, or `-exec … {} +`.** This is a mechanism, not a reminder: a consumed path cannot be mistyped, so the failure mode is deleted rather than watched for.

**The U+202F fault.** Comparing the two archives, `find` printed `…/MemoryStream 8-22-26, 9.03 PM.xcarchive/Products/Applications/HiMem.app` while `ls`, `stat` and `test -d` on that same retyped path all returned *No such file or directory*. macOS date formatting puts **U+202F NARROW NO-BREAK SPACE** before `AM`/`PM`; the retyped path with an ordinary space could never match.

- **The signature is two tools disagreeing about one path.** Traversal lists it, interrogation denies it ⇒ the string is wrong. Do not reach for permissions, the sandbox, or a race.
- **`ls` returning "No such file or directory" is not evidence of absence** — it is evidence about your string.
- **Fifth instrument fault of the stretch, and a new variant: the artifact was readable and correctly located, and the fault was in the address.** One step further would have reported *"the archives have no app payload"* — a confident claim of absence manufactured entirely by the apparatus. Caught by the contradiction, not by suspicion.

---

## Archive pre-flight (run before the first upload attempt)

- **CloudKit schema — the repo half is clean.** Single model version. **Last model change `e283631`, 2026-07-23** (`Project.projectSummaryShort`); before it `42cb6ce` 07-19, `bcce6bc` 07-18, `bb9520a` 07-17. `git diff` of the model directory is **empty for `2a2662b..HEAD` and for `main..HEAD`**; no commit in `main..HEAD` touches it; no `@NSManaged` declaration changed. **`2a2662b` records an upload ASC processed as build 28 on 2026-07-30, whose tree already contained `e283631`** — so no schema change since the build that already shipped. **The dashboard half was NOT read** (see absences).
- **Deployment targets — D8 does not reach a shipping binary.** All 14 settings mapped to owners and verified against the built binaries: iOS app, watch app and widget all **26.0**. The `17.0` is the project-level default (overridden by every target); the `26.4` values belong only to the three test targets. D8's stated risk — *"a 26.0 app embedding a 26.4 extension can fail to load"* — is **disproven for the shipping binaries**.
- **Release build for `generic/platform=iOS` succeeded**, watch app and widget embedded (`HiMem.app/Watch/…/PlugIns/…appex`), 0 compile errors, 51 warnings — all Swift 6 concurrency and iOS 26 SwiftUI/MapKit deprecations, nothing in the removed-API class.

---

## Findings recorded, deliberately not acted on

- **Corrupt trailing bytes in a signing input.** `MemoryStream/Himem Watch WidgetsExtension.entitlements` is 323 bytes and ends `</plist>\n</content>\n</invoke>` — 21 bytes of tool-output artefact after the plist, **committed** at `d392494` (05-10) or `c4aee49` (05-25) and shipped in every build since. `plutil -lint` reports OK (it stops at the plist's end) and it has never blocked an upload. Benign in practice; still corrupt content in a code-signing input.
- **"Hi Mem" in all six usage descriptions** (`NSMicrophoneUsageDescription` etc.) while the product is **HiMem** and the bundle display name is `HiMem`. User-facing copy at first launch — a *what*, escalated not fixed.
- **No `PrivacyInfo.xcprivacy`** anywhere — not in the repo, app, watch app or widget, while required-reason APIs are used heavily (`UserDefaults` in `BenchClipReviewStore`, `BenchClipDurationStore`, `PreviouslyConnectedStore`). Expect an `ITMS-91053` warning email. Build 28 processed without one, so not a hard block today.
- **No Apple Distribution certificate in the keychain** — `security find-identity -v -p codesigning` returned exactly one identity, `Apple Development: tommoseley@outlook.com`, throughout. All three Store provisioning profiles exist and are valid to 2027-04-29 (`com.himem.app` carrying `aps-environment: production`), team `GSZN2G9HR3`. Both local archives embedded the **development** profile (`get-task-allow: true`, provisioned devices present); the distribution identity was resolved inside Tom's Distribute run.

---

## Xcode Cloud — prerequisites established, version list NOT established

**Verified already satisfied, nothing to build:** GitHub remote `github.com/tommoseley/himem` (**public**); all three schemes shared **and tracked in git**; `MemoryStream`'s `ArchiveAction` is `Release`; **the watchOS bundle-ID gotcha is already handled** — Store profiles exist for `com.himem.app.watchkitapp` and `…Himem-Watch-Widgets`, which cannot exist without registered App IDs. **The watch app and widget do not complicate it for this project.** Signing is handled by cloud-managed certificates, which would retire the missing-distribution-cert problem outright.

**The deciding question is unanswered.** If Xcode Cloud offers a **released Xcode 26.x**, that is an iOS 26 SDK build — above the April floor, valid for **both** TestFlight and App Store — and closes D1. Evidence found is weak and is stated as weak: the Xcode Cloud release-notes page's **newest entry of any kind is 2026-02-10**, and its last Xcode addition is **26.2 (17C52), 2025-12-19**, with a known issue (*export archive for development distribution may fail; use 26.1 or earlier* — development distribution, not App Store). Six months of silence through a WWDC cycle means **that page is a notices page, not an index of available versions**. Authoritative check requires credentials not present: `GET /v1/ciXcodeVersions` (no ASC API key at `~/.appstoreconnect/private_keys/`) or the workflow editor's Environment tab.

**Counter-evidence, carried:** Apple Developer Forums thread 791304 is Xcode Cloud throwing **this same error** during the iOS 26 cycle while local archive-and-upload worked. Xcode Cloud is not automatically ahead of us on toolchain.

**Encouraging:** the punch list records this codebase green on **Xcode 26.6** in late July (1132/158 + 34/6), so a release-26 toolchain is not hypothetical here. Whether it still compiles after a month of changes is untested.

---

## Retractions and instrument faults — four, all mine

**Three caught before a conclusion rested on them; one propagated into a report.**

1. **The pre-flight repeated F6h's stale claim** — *"blocks App Store submission, not TestFlight"* — hedged as read off the 07-31 log rather than asserted as policy, but **re-asserted rather than re-derived**, and it stood in a shipping recommendation until the rejection arrived. This is the one that cost something, and it is why entry 1 of the governance above exists.
2. **"The archives have no app payload"** — nearly reported, from the U+202F path. **The first explanation reached for was the sandbox, and it was wrong.** Disabling the sandbox changed nothing, which is what exposed it.
3. **`~/Downloads/Xcode-beta.app` called a "husk"** on the strength of a 96-byte directory entry. `du -sh` said **3.6 G**. Retracted in the same turn; it was the full Beta 5 app.
4. **`./scripts/gate-report.sh: no such file`** — the working directory had shifted to `MemoryStreamTests` after an earlier `cd`. The **exit-66 family** CLAUDE.md already names. Caught immediately by re-running with an absolute path, and the same discipline was applied one command later when `docs/process/session-end.md` read as missing for the identical reason.

---

## What was NOT verified

**This is an absence section. It is the part most expensive to inherit wrong.**

- **Judi has not run the build.** It is in TestFlight; nothing beyond that is known.
- **The upload's acceptance is Tom's reading of App Store Connect, not mine.** No ASC credential exists on this machine; the processing verdict was reported, not read from the source.
- **Pair B's numeric agreement with Pair A is coincidence, not continuity** — restated here because it is the single most likely thing for a future reader to misuse.
- **Zero end-to-end transcription coverage, both pairs.** The 8 `SpeechAssetGate` legs never ran.
- **The `aps-environment` substitution was never observed on a distributed binary.** Both local archives embedded `development`; the Store profile carries `production`. Whether the shipped build carries `production` is unread — check the exported `.app`'s embedded entitlements.
- **`ValidateEmbeddedBinary` against real distribution profiles was never exercised locally.** The Release build was `CODE_SIGNING_ALLOWED=NO`; the archive was development-signed. Only Tom's Distribute run exercised distribution signing, and it was not observed here.
- **The CloudKit Production deploy state is unread.** The repo half is clean; whether the July 17–23 changes reached Production is a dashboard fact. Its failure mode is silent — outbound sync breaks at runtime and never touches upload validation.
- **Xcode Cloud's available Xcode versions are unestablished** — see above; the source is a page six months stale.
- **Per-commit gating:** `0c2b8f8` is docs-only and both pairs ran on the tree, not per commit.
- **Beta 5's own seed status is assumed current, not verified against Apple's accepted list** — which is unpublished. It was current as of 2026-08-10 and the upload was accepted; that is the whole evidence. **The same expiry applies to this claim as to F6h's** — if a Beta 6 ships, this may repeat.
- **Enumerations swept mechanically this session:** `SpeechAssetGate` call sites (twice, independently), the model-change history via `git log --follow`, the 14 deployment-target settings mapped to owners and cross-checked against built binaries, the Xcode Cloud prerequisites. **Trusted rather than re-counted:** C2 step 5's *"~59 source-scan assertions"*, still inherited from an earlier session.
- **No guard was mutation-verified this session.** No production code changed; the only commit is governance prose.

---

## Open threads

- **④ out-of-range** — persistent log store (`sysdiagnose`), **not** a console bridge. Still never run on any surface; cannot run on a simulator.
- **The declaration fix** — post-Judi hardening. 53+ diagnostics across 15 files, ~44 of them `id` with no possible default. Both named routes remain unsupported.
- **B26's reconcile** — survivor policy complete including nil-`linkedAt`, held at `DuplicateEdgeConvergenceTests.swift.held`.
- **B27's partition axis** — post-tag, blocked on the field decision, not on layout.
- **The layout flip** — a *what*, unruled.
- **C2 step 5** — retires ~59 source-scan assertions; that figure is still inherited and not re-counted.
- **D1 — the App Store submission path still needs a real RC.** No beta solves it. No Xcode 27 RC exists (latest is Beta 5, 2026-08-10). Xcode Cloud on a released Xcode 26.x is the only route that closes it without new hardware or an OS downgrade.
- Carried: B19, B22 ⊘ retired, D3 · D4 · D7 · D9b · F34/C15 · C1–C15.
- **Run 1's disappearing clips** (2026-08-22) — observed, unexplained, not revisited.

## Risks

- **`main` and `f8` are 59 apart.** Pushed, so the exposure is integration, not loss.
- **The 08-21 trap still has no demonstrated mechanism.** Both named routes unsupported.
- **B24 may recur.** If it does, it is a second mechanism, not that fix failing.
- **A Beta 6 would likely repeat the seed-window rejection.** The remedy is now known and cheap; the trigger is outside our control and unannounced.
- **Beta 4 is preserved at `/Applications/Xcode-beta-27A5228h.app` (3.6 G) and `~/Downloads/Xcode_27_beta_5.xip` (2.0 G) is retained** — deliberately, per ruling 6, until Judi has run the build. Reclaim ~5.6 G after.
- Disk 23 Gi free at close; simulators shut down, result bundles and all isolated DerivedData trees cleared.
