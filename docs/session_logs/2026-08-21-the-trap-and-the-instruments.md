# Session log · 2026-08-21 · the SIGTRAP, eight instrument faults, and the watch on a wrist

Facts only. Immutable. **Written for a context-free reader.** Covers `f3d9597..e20e8e1` (6 commits).

---

## Repo position

- Branch **`f8-overlay-and-wiring`** @ **`e20e8e1`**, **52 ahead of `main`**, **0 unpushed**.
- **`main` @ `36ce159`** — deliberately behind; every C2 rebuild commit lives on `f8` only.
- Code tree **clean**. `docs/design/` holds Tom's uncommitted work and was not touched; he added to it during the session.
- **One deliberate tracked artefact:** `MemoryStreamTests/DuplicateEdgeConvergenceTests.swift.held` — B26's deferred reconcile. Committed (`68420f5`, prior session), extended this session with the nil-`linkedAt` ruling. Not a pending red.

### Gate — both read from result bundles via `scripts/gate-report.sh`, isolated `-derivedDataPath`, `DEVELOPER_DIR` on Xcode-beta, run **sequentially** with the watch pair booted immediately before

| Scheme | Result | Destination |
|---|---|---|
| `MemoryStream` | **1497 cases / 211 suites** — 1486 passed, 3 skips, **8 deliberate failures**, **0 crash lines** | sim `E3C0710E` (**iOS 26.4.1**) |
| `Himem Watch Watch App` | **34 cases / 6 suites, 0 failed, 0 crash lines** | watch `B17233F6` + paired `74EED5FE` (**watchOS 26.5**) |

The 8 are `SpeechAssetGate`, membership **byte-identical by `diff`** against a set re-derived mechanically this session from the 8 call sites across 6 files. **The gate is a count, not a coverage claim:** those 8 legs are the only end-to-end coverage of record → compress → transcribe and none of them ran; this machine reports the en_US speech asset as `unsupported`.

Counts moved **1491/210 → 1497/211** (phone), watch **34/6 unchanged**. Runtimes held; **no rotation**. Session-open gate matched the inherited baseline exactly.

---

## Scope and rulings (all Tom unless stated)

1. **Seeder grows a voiceless sitting.** Fixture change, not behaviour.
2. **`shortIds` widened.** Accepted as built at head+tail rather than the ruled wider prefix — see Retraction-adjacent note below.
3. **Nil `linkedAt` in B26's survivor policy: nil must LOSE.** Non-nil beats nil; oldest among non-nil; annotated among all-nil; then either. *An artefact may never outrank a record.*
4. **The "Remove from this memory" fix ships before Judi's build**; the reconcile still defers to the C-family.
5. **Both voiceless sittings kept** (CC built two against a ruling of one; the override was accepted — one sitting agrees by coincidence and leaves B25 unreproducible).
6. **Burst summary collapses to a chevron-only affordance when expanded** — logged, not built.
7. **Delete unused simulators**, keeping `E3C0710E`, `B17233F6`, `74EED5FE` (CC kept a fourth — see below).
8. **④ out-of-range deferred** — airplane mode is not the same test.

**Options closed (do not re-litigate):**

- **Sweeping the 44 non-optional-over-optional attributes — rejected.** The shape is a property of `NSPersistentCloudKitContainer` requiring every attribute optional, not 44 defects. Three named sites are the finding.
- **Consolidating `BuildStamp` into `Shared/` — deferred on mechanism, not preference.** `Shared/` uses explicit `project.pbxproj` references; the watch app directory is a `PBXFileSystemSynchronizedRootGroup`. Moving the file is project-file surgery, which is what orphaned `Shared/` during F18.
- **Fixing `syntheticClip` / `referencedFilenames` on a hypothesis — refused.** Both are genuine instances; neither is diagnosed. Awaiting a ruling.

---

## THE HEADLINE — a whole-table fetch read a non-optional accessor and trapped (`5e40842`)

**Device, twice: the app vanished with `App terminated due to signal 5`.** Not the signal 9 the 2026-08-19 log documents as benign console teardown. **Signal 5 is SIGTRAP** — a Swift runtime trap.

`QAFixtureSeeder.clear` fetches **every** `MediaReference` in the store — the user's real clips, not just fixtures — and calls `isSeeded(ref.id)`, which takes a **non-optional** `UUID`. `MediaReference.id` is `@NSManaged var id: UUID` over an **`optional="YES"`** cell. One nil cell traps with `EXC_BREAKPOINT`.

### `shouldDeleteInaccessibleFaults` is why a nil cell is reachable — RECORD THIS

`StorageService:165` sets `viewContext.shouldDeleteInaccessibleFaults = true`, under a comment saying it *"drops faults that point at deleted CloudKit records instead of throwing on access."*

**What the flag actually does is mark the object deleted and NIL OUT EVERY PROPERTY.** It converts a catchable `NSObjectInaccessibleException` into a **silently nil-valued object** — the say-nothing-and-continue shape this project has spent weeks removing from its own code, sitting inside a Core Data flag.

**Deleting rows is what makes a cached fault inaccessible.** That is why both observed traps landed immediately after a delete and never before one, and it is the answer to "why now" for a line that is years old.

### The reading rule that came out of it

**A non-optional `@NSManaged` accessor is a force-unwrap that does not look like one.** `try!`, `as!` and a bare `!` announce themselves; `guard let` announces its absence. This wears **neither** shape. CC read `clear` earlier the same evening and pronounced it safe — *"no force-unwraps, every fetch and file op is `try?`"* — having scanned for exactly the failure modes it does not present. **Pronouncing something safe is a hypothesis too.**

### The enumeration, and its honest size

**44 attributes across 11 entities** are declared non-optional in Swift over `optional="YES"` cells. **That is not 44 latent crashes.** Every attribute in this model is optional *because `NSPersistentCloudKitContainer` requires it*, so the shape is universal here by construction; what makes a site dangerous is whether a nil cell is **reachable**. Ranked:

- **`QAFixtureSeeder.clear`** — fixed. DEBUG-only, so no user could reach it.
- **`ArrivedClipMaterializer:115/122`** (`syntheticClip`) — **LIVE**, reads `ref.id` and `ref.osIdentifier`, reached from `composeBenchClips` at `SessionListView:421` — **the bench composition path, crossed on every regroup.** Untouched, awaiting a ruling.
- **`UbiquityStore:446`** (`referencedFilenames`) — same shape, whole-table, reads `ref.osIdentifier`. **Latent:** its only caller `plan(context:)` has zero production callers since T1.1 disabled the sweep. Live again the day it is re-enabled.
- **`EntryLifecycleService:1136`** — weak: reads `edge.memoryId` but the fetch is `id IN %@` against known ids.
- **`BenchInventory:76`** — **NOT an instance.** `for ref in refs` matched the grep; `refs` is `[BenchRefDescriptor]`, a **struct**. Verify the type, not the name.

### Reproduction, and why it is not the guard

`ClearNilIdTrapTests` **crashes the host** against the unfixed code (`Test crashed with signal trap`). Per CLAUDE.md § Test Concurrency a failure that takes the host down proves nothing about any assertion and buries unrelated suites, so **it is the diagnosis, not the guard**. After the fix it passes normally and guards that `clear` survives a foreign row **and still removes the seeded ones** — a fix that stopped working would satisfy "no trap" alone.

**Limit, stated:** the fixture nils the cell via KVC. That proves nil-cell → trap. It does **not** prove how the nil arrived in the device's store — an inaccessible fault returned by the fetch, or a row genuinely carrying a nil id. **The provenance is unproven.** The `.ips` was requested and never obtained.

---

## THE INSTRUMENT TAXONOMY — eight faults, three sub-shapes, one night

**Every one returned a clean, plausible, correctly-formatted answer. None looked like an error at the moment of reading.**

| # | Check | What it actually did |
|---|---|---|
| 1 | `[BinThumb]` read as a Recently-Deleted manifest | Logs only tile-render **failures** (carried from 08-19) |
| 2 | `crashed with signal abrt` alone | Missed `Crash: HiMem at <deduplicated_symbol>` — 51 crashes reported as 0 (carried from 08-19) |
| 3+5 | `prefix(8)` | **ONE defect, TWO sites** — `ClusterProposalTrace.shortIds` and both `QAFixtureSeeder` filename builders |
| 4 | `^/.*: error:` | Returned **0** on a run that failed to compile; that run printed errors only in the summary block |
| 6 | `until [ -f "$SP/watch.rc" ]` | Matched an **82-minute-old** success marker; the run had not started testing |
| 7 | crash grep over the `.log` | The crash text is in the **result bundle**; `gate-report.sh` reads it and had already been run four times |
| 8 | `timeout 90 xcodebuild …` | **`command not found` (rc 127) — the check never executed**, and its empty output was nearly read as a finding |
| 9 | `-showdestinations` listing the watch with no error | Enumerates what is **known**; the `error:` field populates at resolution time |

**Three sub-shapes:**

- **A check against an artifact nobody read** — 1, 2, 3+5, 4, 9.
- **A check against an artifact that was current once** — 6. *Worse than a wrong pattern, because it is right in every respect except time; an 82-minute-old success marker is byte-identical to a fresh one.* Shape A can be closed by reading the emitter, a cost that stays paid. Shape B re-expires on every run.
- **A check that never executed** — 8.

**#7 sits outside the taxonomy as its own warning: a mechanism that can be bypassed by habit is not yet a mechanism.** The pattern lived in a script precisely so it would not be retyped, and it was retyped anyway.

**Two of the eight occurred while writing up the first six.** The failure mode is not ignorance of the rule — it is that the rule does not fire at the moment of typing a command that looks obviously correct. **The remedy is not another rule; it is making the wrong artifact unreachable.** Mechanisms banked this session: the compile-failure detector is now the format-independent `Testing cancelled because the build failed` / `The following build commands failed`; `shortIds` is guarded by a test that fails against `prefix(8)`; a completion marker is now deleted **in the same statement that launches** the thing it marks.

---

## THE EXIT-CODE PILE — now five meanings

`65` (compile failure · assertion failure · launch denial · embedded-binary platform mismatch), `66` (no Xcode project in the working directory), **`70` (destination never became available)**, `73` (out of disk), `144` (after a `pkill`).

**Exit 70's discriminator:** `xcodebuild: error: Timed out waiting for all destinations matching the provided destination specifier to become available`, with **0 compile errors and no failed build commands**. It reads as a build failure and is a **reachability** failure.

**And the diagnostic that answers it is not the one you would reach for.** Three commands, only one tells the truth:

- `devicectl list devices` → `available (paired)` — means *known and paired*, **not reachable**
- `xcodebuild -showdestinations` → lists the watch with **no error attached**
- **`devicectl device info details`** → `Device State: disconnected` · `Last Connection Date: Aug 13, 2026` · `Developer Mode Status: Enabled`

Only the third reports **Device State** and **Last Connection Date** — the two fields that answer *"is it actually there"*. The watch had not connected to this Mac in **eight days**.

---

## XCODE'S SILENCE IS NOT THE APP'S SILENCE

**Mac↔watch and phone↔watch are independent transports, and roughly an hour went to treating one as a proxy for the other.**

The Mac could not see the watch at all (`disconnected` since Aug 13, transport `localNetwork`) — while **WatchConnectivity between the phone and the watch was plainly alive**, delivering files and acks. A watch can be fully functional for the app while remaining invisible to Xcode. Do not infer app-side state from developer-tool reachability.

---

## The four-item watch pass

**① Watch app installed — INFERRED, NOT VERIFIED.** All night the phone logged `Watch app is not installed`; it then changed to `WatchConnectivity session on paired device is not reachable`, and two `transferUserInfo` payloads were **delivered and confirmed**. A `transferUserInfo` cannot be delivered and confirmed by an app that is not there. **The identification comes from a changed FAILURE MODE, not from a success.** CC never installed it; it auto-installed from the bundle embedded in the phone build.

**The on-wrist binary is the phone build of `2026-08-21 20:55:49`, which predates `e20e8e1`. It therefore carries NO watch build stamp, and the stamp's absence on the watch is expected rather than a defect.** The stamp exists in git and has never been built for device.

**② The two stranded clips — RESOLVED.** `DDA80712` and `48D2EF6E`, stranded since 08-18 with nothing to ack them, were **delivered and confirmed**. The sequence is the designed two-path behaviour working end to end on hardware for the first time: `sendMessage` failed **honestly and named its own fallback** (*"(transferUserInfo backup will deliver)"*), and the fallback delivered.

**③ Record on the watch → bench — PASSED, full chain confirmed.**

| Link | Evidence |
|---|---|
| transfer | `[WC] iPhone received file … 8DBA38AD….m4a` with metadata keys incl. `clipId`, `rollGroupId`, `capturedAt` |
| accept | `acceptArrivedClip clipId=8DBA38AD rollGroupId=7BEE88FE offsets=0` |
| sweep | `sweep trigger=arrival total=3 pending=1 ids=[8DBA38AD]` |
| transcription | `preflight … exists=true bytes=39135` → `done segments=1 coverage=2.56s file=3.40s textLen=24` |
| composition | `[ClusterTrace] sessions=2` naming `8DBA38AD`; `[ResolveProbe] every session fully resolved · nothing undrawable` |

**The regroup line alone would have understated it.** `lens=2` looks flat against an earlier `lens=2`, but those were the two *stranded* clips, which are not drawable; the `2` afterwards **is** the two watch clips. Reaching the proposer is downstream of composition, so the ClusterTrace naming the id is the stronger evidence.

**Two bonuses, neither sought:**

- **The watch transfer format contract, verified on hardware for the first time:** `fileFmt=<AVAudioFormat 1 ch, 16000 Hz, aac>`, 39135 bytes for 3.40 s, arriving as `.m4a`. The July 14 lock — *the watch never ships the raw recording* — had been simulator-guarded only.
- **B17(a)'s untested half ran.** `FORMED timePlace "Fri 10:23 PM" · ids=2 → SURVIVED` — the **first `timePlace` proposal ever observed on hardware**, because the seeder carries no location by design and the rule is structurally unreachable from fixtures (recorded 08-19 as *"test-pinned only"*). The name reads **"Fri 10:23 PM"**, NOT "Together at Fri 10:23 PM". **Confirmed on device.**

**④ Out-of-range provocation — DEFERRED, and it remains the one hardware-only check never exercised.** Airplane mode is not the same test: the delivered-awaiting-ack gate keys on **reachability transitions**, and a radio kill may not produce the sequence a walk produces. A simulator structurally cannot flap reachability. Carried since the F6 stretch.

---

## B23 — the memo measured on hardware, twice

The 08-19 log recorded it as *"a fix with a measured defect and an unmeasured benefit."* Both readings tonight:

| Bench | regroup #1 | #2…n | propose |
|---|---|---|---|
| 17 items | 21.8 ms · `memo=miss` | 10.4–11.4 ms · `memo=hit` ×15 | **10.3 ms** |
| 20 items | 21.8 ms · `memo=miss` | 11.0–11.4 ms · `memo=hit` | **10.1 ms** |

**16 regroups in 2.09 s at an unchanged bench, one miss and fifteen hits.** ~15 × 10.3 ms ≈ **155 ms of proposer work skipped**; pre-memo all 16 would have paid it (~165 ms → 10.3 ms, **~94 % of the proposer cost gone**).

**Corroborated independently:** regroup #1 at 21.8 ms against #2–#14 at 10.4–11.4 ms is a ~10.5 ms gap that **matches `propose=` without being derived from it**. Two signals, so *"a memo wired to nothing"* is ruled out rather than assumed.

**A second positive signal, from Tom's set-asides:** `lens` grew 17 → 18 → 19 while `memo=hit` held and `sessions=1` stayed constant. **Correct by construction** — the memo's key is the proposer's inputs (`[ClipGroup]`, voice-only via `projectGroup`), so media is structurally invisible to it while `lens` counts it.

**The inherited 532 ms target still does not reproduce.** Three readings now — 16 regroups/532 ms, 11/138.9 ms, and tonight's 16 whose pre-memo proposer cost would have been ~165 ms. **Left unexplained rather than averaged.**

**NOT VERIFIED: the invalidation path.** Only **one** `memo=miss` occurred in each launch — regroup #1, the cold miss. A voice capture was planned three times and never taken. **A memo that never invalidates would produce a trace identical to tonight's.** One later miss did occur (`sessions=0 · lens=2 · propose=0.0ms`) when the bench emptied, which proves the memo *recomputes on an input change* but exercises only the coarse case.

---

## The rest of the work

| Commit | What |
|---|---|
| `e5f52be` | **B26 · Remove did not remove.** `fetchLimit = 1` on one door and delete-the-edge-you-were-handed on the other left a duplicated pair attached; the row renders once either way, so the button reported success and changed nothing. One owner, `dropEveryEdge(memoryId:clipId:)`. **Red verified by value** (`count → 1`, expected 0, both doors; `→ 2`, expected 1, on the ceiling). The pre-fix tree **is** the mutation. |
| `b08ddaa` | **`shortIds` widened to head+tail.** Mutation-verified M18: restoring `prefix(8)` fails only the new namespaced test, with the random-id companion still green. |
| `c6dcbf1` | **Seeder: filename collision + two voiceless sittings.** Both filename builders keyed on `prefix(8)` under the `5EED0002` namespace, so **all ten seeded voice clips wrote to one file** and all photos to one JPEG — the fixtures never exercised per-clip audio, and Cluster A's materialization was *"proving the written CAF is real"* about a file shared with nine others. |
| `94f5dc8` | **Nil-`linkedAt` policy** recorded in the held file. |
| `5e40842` | **The SIGTRAP** (above). |
| `e20e8e1` | **Watch build stamp.** The surface with the least evidence had no instrument. Duplicates the phone's `BuildStamp` — the `.measurement` shape, taken deliberately over pbxproj surgery. |

**Confirmed on device, from the corrected header (`3f4f956`, prior session):** header read **"20 clips · 13 sessions · Aug 19 10:21 PM – today 8:04 PM"** against 12 (clusters) + 3 (loose) + 3 (stack today) + 2 (Aug 19 burst) = **20**. The burst row is a **container, not an item** — `ClipsListItem.burst([MediaReference])` is one row over N refs (`sameBurst` = ≤60 s and same place), so the collapsed summary plus its two expanded members is **three visual lines, two items**. `13 sessions` corroborated independently by `ClusterTrace sessions=13`, and the 08-19 leftover contributing exactly 2 matches a figure derived arithmetically before the fixtures existed. **Not F35(b).**

**Simulators:** 39 deleted, keeping `E3C0710E`, `B17233F6`, `74EED5FE` **and `9860631D`** — the fourth kept deliberately as `E3C0710E`'s paired watch, because the phone gate builds the embedded watch app and CLAUDE.md's fourth meaning of exit 65 is a pair-induced platform mismatch. Simulator dir **21 G → 6.0 G**; disk **8.1 Gi → 14 Gi**. *A `df` taken immediately after the bulk delete read **3.2 Gi** — that measured APFS mid-reclaim, not the result.*

---

## Retractions

1. **"The trap is on the delete path."** False. Deletes succeeded; the trap followed the **clear**. CC had proposed reproducing the delete path.
2. **"`memoryId` at `EntryLifecycleService:943` is the cause."** False — CC's own new read, dead once the deletes survived. **Chasing his own disclosure.**
3. **"The trap is on the seed path."** False — Tom had tapped Clear, not Seed. Second hypothesis pointing at CC's own diff, also wrong.
4. **"`clear` looks safe — no force-unwraps, every fetch and file op is `try?`."** False, and the trap was in a line already read. See the reading rule above.
5. **"0 crash signatures — the test failed without crashing."** False; it crashed with `signal trap`. The grep was over the `.log`; the crash text is in the bundle.
6. **"The transport is up"** (from `-showdestinations` listing the watch without an error). False — the next build failed identically.
7. **"The watch isn't offering itself as a destination."** Not a finding — `timeout` is not installed, so the check never ran.
8. **"Membership DIFFERS from expected-failures."** CC's own two-space indentation in the comparison file, not a gate finding. Content was identical.
9. **B23's `lens` growth with `memo=hit`** was raised as a possible invalidation failure; resolved as correct by construction once Tom confirmed both items were photos.

*Propagation: none of these reached a committed file except (4), which is corrected in `5e40842`'s message and in the `clear` comment.*

---

## What was NOT verified

**This is an absence section. It is the part most expensive to inherit wrong.**

- **The memo's invalidation path is unexercised.** No voice capture was taken. The only misses observed were the cold miss and a bench-emptying miss.
- **The SIGTRAP's provenance is unproven.** The reproduction nils the cell by KVC; how a nil arrived in the device store is unknown. **The `.ips` was requested and never obtained.**
- **① is inferred, not verified** — from a changed failure mode plus a confirmed delivery, not from an install CC performed or a stamp read off the watch.
- **④ has never run** on any surface, and cannot run on a simulator.
- **`syntheticClip` and `referencedFilenames` are named, not fixed, not diagnosed.** `syntheticClip` is on a path crossed by every regroup.
- **The four commits `e5f52be`…`94f5dc8` were gated once over the COMBINED tree, not per commit.** `5e40842` and `e20e8e1` were each individually gated.
- **The watch app has never been built for device.** The wrist binary is the embedded copy from the phone build; the watch device build failed twice at exit 70.
- **Enumerations trusted rather than re-counted:** none inherited. The 44-attribute model/Swift comparison, the `SpeechAssetGate` membership, and the five-site bounded check were each swept mechanically **this session** — and the five-site check produced one **false positive** (`BenchInventory`) caught by verifying the type.
- **`ClearNilIdTrapTests` is the only guard added this session that was not mutation-verified by an injected mutation** — its pre-fix crash serves that role, which is weaker evidence than a clean assertion failure.

---

## Open threads

- **④ out-of-range** — needs a walk, not a radio kill. The one hardware-only check.
- **The memo invalidation** — one voice capture closes it.
- **A ruling on `syntheticClip`** (live, every regroup) and **`referencedFilenames`** (latent until the sweep is re-enabled).
- **The `.ips`**, to settle the trap's provenance.
- **Build the watch app for device** once the Mac↔watch transport is restored, so the wrist carries a stamped binary.
- **Burst summary → chevron when expanded** (ruled, not built).
- **`BuildStamp` consolidation into `Shared/`** — needs pbxproj work.
- **B26's reconcile** (C-family) with the survivor policy now complete including nil-`linkedAt`.
- **C2 step 5** — retires ~59 source-scan assertions; **that figure is inherited from an earlier log and still not re-counted.**
- Carried: B19, B22 ⊘ retired, B27 post-tag, D1 · D3 · D4 · D7 · F34/C15 · D9b · C1–C15.

## Risks

- **`main` and `f8` are 52 apart.** Pushed, so the exposure is integration, not loss.
- **A live instance of the trap class sits on the bench composition path** (`syntheticClip`). If a nil-id ref is ever reachable there, it traps on every regroup.
- **The wrist binary predates the watch stamp**, so any watch reading taken before the next device build is unverifiable against a stale install — the exact gap the stamp was added to close.
- **B24 may recur.** If it does, it is a second mechanism, not this fix failing.
- Disk recovered to **14 Gi**; simulator dir 6.0 G. Simulators shut down and trees cleared at close.
