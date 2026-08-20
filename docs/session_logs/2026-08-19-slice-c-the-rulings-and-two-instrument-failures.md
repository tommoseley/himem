# Session log · 2026-08-19 · C2 step 4 slice C · two rulings · B26 · B24 diagnosed

Facts only. Immutable. **Written for a context-free reader.** Covers `24e02ad..da6f242` (6 commits).

---

## Repo position

- Branch **`f8-overlay-and-wiring`** @ **`da6f242`**, **41 ahead of `main`**, **0 unpushed**.
- **`main` @ `36ce159`** — deliberately behind; every C2 rebuild commit lives on `f8` only.
- Code tree **clean**. `docs/design/` holds Tom's uncommitted work and was not touched. The previous session's log is still untracked (also Tom's).
- **One deliberate untracked artefact:** `MemoryStreamTests/DuplicateEdgeConvergenceTests.swift.held` is now **committed** (`68420f5`) as the record for B26's deferred reconcile — it is no longer a pending red. The `.held` suffix keeps it out of the test target.

### Gate — both read from result bundles, isolated `-derivedDataPath`, `DEVELOPER_DIR` on Xcode-beta, run **sequentially** with the watch pair booted immediately before

| Scheme | Result | Destination |
|---|---|---|
| `MemoryStream` | **1476 cases / 207 suites** — 1465 passed, 3 skips, **8 deliberate failures**, **0 crash lines** | sim `E3C0710E` (**iOS 26.4.1**) |
| `Himem Watch Watch App` | **37 cases / 8 suites, 0 failed, 0 crash lines** | watch `B17233F6` + paired `74EED5FE` (**watchOS 26.5**) |

The 8 are `SpeechAssetGate`; membership verified **byte-identical by `diff`** against a set derived mechanically from the 8 gate call sites across 6 files. **The gate is a count, not a coverage claim:** those 8 legs are the only end-to-end coverage of record → compress → transcribe, and none of them ran — this machine reports the en_US speech asset as `unsupported`.

Counts moved **1461/202 → 1476/207**: +15 cases, +5 suites. Runtimes held; **no rotation**.

---

## Scope and rulings (all Tom unless stated)

1. **A set-aside PHOTO returns to the loose bench card, exactly as a set-aside CLIP does.** Set aside means "not part of this proposal", not "gone" — F44, and the same J2 posture. **Recorded as the first answer to the question, not a change of one:** the prior behaviour existed only as a side effect of B25's broken lookup and nobody chose it.
2. **"Delete session" destroys everything the card draws**, with Recently Deleted as recoverability per the standing deletion rule.
3. **B26 split.** The `memoriesArray` dedupe + count fix ship pre-tag; the post-remote-change reconcile is deferred to the C-family. New machinery on the sync path must not land days before a build reaches the person whose data it would reconcile.
4. **B26's count fix must land in the same commit as the dedupe** — separating them would repeat the count-describes-a-different-set class a third time.
5. **Guard, not filter, on zero-clip sessions reaching the proposer.** CD proposed filtering them; **withdrawn by Tom** — a media-only sitting is a real bench state and filtering it would hide the shape B25 lived in.
6. **B24 promoted** from "logged, not diagnosed" to scheduled, then diagnosed in-session.
7. **Push retained** throughout, per the 2026-08-15 ruling; the recorded risk assessment depends on it.

**Options closed (do not re-litigate):**

- **Filtering zero-clip sessions before grouping — rejected.** The property worth protecting is that the proposer's identity is positional; that is now pinned by test (`ea5d41a`).
- **A stronger write-side guard for B26 — rejected as impossible.** See "the write path is correct", below.
- **Keeping `partlyClaimedIds` / `withoutMedia()` — rejected.** Ruling 1 removed their only consumer, and a complete, tested, never-consulted value is the `UnifiedBenchGrouper` shape.

---

## C2 step 4 slice C — the swap (`7395c83`)

B25 closed at **both** sites. `mediaBySessionId` and the card layer's use of `projectGroup` are retired; `sessions`/`allSessions` are `[ResolvedSession]`, composed once in `recompose`. Both verbatim duplicates of `session.clips.count + (mediaBySessionId[session.id]?.count ?? 0)` are now `session.count`.

The held red landed first and failed exactly as predicted: `keyA != keyB` with both ids `…E317`; `map[keyA]?.count == 2` reading back **3**; the third assertion **passing** because B was the last writer — which is what explained the device's rotating report. It was then re-pointed through `ResolvedSession` with **its three assertions and messages unchanged**.

`ClipGroup` survives as the proposer's adapter. `unresolved` kept a live consumer; the probe's count comparison retired with the pair it compared.

**A rule that was enforced by accident, and would have inverted silently.** A partly-claimed session's remainder drew no media *only because* the media lookup missed — a remainder's projected id derives from a different first clip. No test asserted it and the gate was green either way; the design-fidelity diff read caught it. Preserved in `7395c83` pending a ruling, then **reversed** by ruling 1 in `2fdca6f`.

---

## B26 — THE WRITE PATH IS CORRECT, WHICH INVERTS THE PREMISE OF THE RULING THAT GATED IT

The ruling was *no render-side dedupe until the write path is understood, or we hide the defect and keep the corruption*. Understanding it showed the write path is already right, which makes the render dedupe the correct layer rather than a cover-up.

### Three reproductions ruled out — recorded so nobody retries them

| # | Fixture | Outcome |
|---|---|---|
| 1 | Two contexts writing **sequentially** | **1 edge.** The second fetches fresh, sees the first, guard refuses. *Passed, proving nothing.* |
| 2 | Two contexts interleaved, ref from `createVoiceFragment` | **1 edge.** That helper attaches an edge as it goes, so **both** contexts saw the pre-existing one and both refused. *Passed, proving nothing.* |
| 3 | Two contexts interleaved, genuinely **zero-edge** ref | **`NSCocoaErrorDomain 133020 "Could not merge changes."`** The shared coordinator's optimistic locking refuses the second save. |

**Two of the three failed by PASSING**, which is the dangerous direction; only checking *which* assertion fired caught it.

So within one store the duplicate cannot occur: the guard is correct, and where the guard cannot see, the coordinator does. **The duplicate requires two genuinely separate stores converging via CloudKit** — two devices — and the model cannot forbid it, since `NSPersistentCloudKitContainer` permits no uniqueness constraints (verified: `uniquenessConstraint` count is 0 across the model). Per CLAUDE.md that half is **escalation, not a heuristic patch**.

### What shipped (`68420f5`)

`MediaReference.memoriesArray` dedupes by memory id, first-occurrence-wins so `linkedAt`-descending order survives. `referencingMemoryCount` and `referencingMemoriesSortedByLinkedAtDesc` derive from it, so the count is fixed by the same change.

**The July-9 split, now a named test.** That fix deduped `EntryMapper`'s `mediaItems` by ref id and then passed the **undeduped** `ref.referencingMemoryCount` onto each surviving row — it deduped the rows and left the count on them wrong. `theMapperCarriesTheDedupedCountOntoTheDedupedRow` was red at **2**.

### Survivor policy for the deferred reconcile — RULED, DO NOT RE-DECIDE

Recorded in `DuplicateEdgeConvergenceTests.swift.held` so it is inherited:

- **Oldest `linkedAt` wins.**
- **No annotation is ever lost** — adopt the loser's if the survivor has none; **append** if both are annotated and differ.
- Take the **survivor's** `orderInMemory`.

The principle, which outranks any convenience in implementing it: **an artefact of syncing may never destroy something a person typed.**

---

## B24 — DIAGNOSED. PROVEN IN MECHANISM, NOT IN ABSENCE

`HiMem-2026-08-19-205033.ips` named the owner:

```
Thread: com.apple.root.user-initiated-qos.cooperative   ← not main
  NSManagedObjectContext save:
  BenchMediaKeyCollapseTests.makeRef(in:at:)
  BenchMediaKeyCollapseTests.aBenchOfVoicelessSessionsIsDistinguishableByTheDrillIn
  _XCTTerminateHandler → abort → SIGABRT (Abort trap: 6)
```

`StorageService(inMemory:).viewContext` is `NSMainQueueConcurrencyType`; Swift Testing runs `@Test` bodies on the cooperative pool, so a suite without `@MainActor` calls `save()` off-main → ObjC exception → `abort()` → **host death**, everything after it collateral. **It was this session's own slice-C guard**, doing ten `makeRef` saves in a suite that lacked the annotation.

**52 of 57** suites building a Core Data stack declared `@MainActor`; **five did not**, including the crashing owner. B24's original entry suspected `MemoryChipIdentityTests` and `ResolvedSessionTests` for the **wrong reason** ("more parallel Core Data stacks") — both are in the five, and the discriminator was simply the missing annotation.

**THE CRITICAL FRAMING FOR THE NEXT READER: this is proven in mechanism, not in absence.** B24 was intermittent, so a green gate is consistent with the fix **and** with the old luck. What is proven is the crash report's stack, the population (5 of 57), and that the guard bites under mutation. **A recurrence after this means a second mechanism, not a failed fix.**

Three occurrences this stretch and the one before: 67, then 87, then 59 "failures" — each **one** defect.

---

## Retractions

1. **"Exit 0" reported for the first phone gate.** The real exit was **65**. The wrapper `echo`'d after `xcodebuild`, so the script's status was the `echo`'s. Corrected in-session before anything rested on it.
2. **"0 crashes in bundle" reported on a run carrying 51.** The crash check matched only `crashed with signal abrt`; that occurrence used `Crash: HiMem at <deduplicated_symbol>`. **CLAUDE.md § Test Concurrency already named both phrasings.** A re-audit of every gate reported this session (`phoneG`, `phoneR`, `phoneP`, `watchF`, `watchR`, `watchP`) came back clean under the corrected pattern — **but by the membership diff catching what the grep missed: luck of construction, not the detector working.** No committed gate claim was wrong. **Propagation: none beyond this session's own reports.**
3. **`[BinThumb]` read as a manifest of Recently Deleted** (a report from CD, accepted then corrected). It logs only tile-render **failures**, so the photo — the item ruling 2 turns on — is structurally the item that could never appear there. `…400` is the **voice** clip, not media. The ruling holds on different evidence: `lens 15 → 12 → 15` against `clips 39 → 38`, where `lens = DrawnBench.items.count` = every drawn item of every kind (definition verified, not assumed).
4. **"Two contexts over one store reproduce B26's duplicate."** False — see the three ruled-out fixtures above.

Both instrument failures are the same shape — *right artifact, wrong pattern, invisible because the answer came back well-formed* — and produced the governance rule in `da6f242`.

---

## Device pass (build 28, `v1.0 (28)`, binary 2026-08-19 20:22)

Run on Tom's iPhone (15 Pro Max, `C7830D7E`), fixtures seeded, Tom driving the UI.

- **`[ResolveProbe]` → `every session fully resolved · nothing undrawable`**, one emission, zero `UNRESOLVED` across 91 s. Slice C verified on device.
- **`[ClusterTrace]` emitted 3 times in 91 s** (was ~16 in 2 s), each tracking a real bench change — the instrument reports the bench, not itself. All three clusters formed and survived every time.
- **No crashes; no `ForEach … occurs multiple times`** — so B26's duplicate-edge warning did **not** reproduce here (the fixtures create no duplicate edges; this neither confirms nor clears anything).
- **B23 answered, and it splits in two.** `[BenchPerf]`'s independent counter: **16 regroups in the first 2.0 s** (`#1–#16`, 27.5–92.9 ms each) = **532 ms of NLTagger work, 27 % of that window**, then settling to ~17 s apart. So the *instrument artefact* is closed and the *launch burst is real* — a measured target, against a 400 ms cold-launch budget.
- `Publishing changes from background threads` recurs throughout, every phase.

**Fixture gap:** the seeder creates **no voiceless (media-only) session**, so B25's own shape is not reproducible from fixtures. The device pass verifies the swap did not regress rendering; it does **not** demonstrate the collapse is gone. The tests carry that.

---

## Guards added, and which were mutation-verified

| Guard | Mutation-verified |
|---|---|
| `BenchMediaKeyCollapseTests` (B25 money test + drill-in second site) | **Yes** — M1 (sentinel id restored) fails both |
| `ResolvedSessionProbeTests` (unresolved sweep) | **Yes** — M2 |
| `ResolvedSessionTests` (one-set count; remainder keeps media) | **Yes** — M3, M7 |
| `RenderedBenchTests` (set-aside photo returns) | **Yes** — M7 |
| `DeleteSessionScopeTests` (destructive scope + backing partition) | **Yes** — M6 |
| `ProposerSessionIdentityTests` (positional identity) | **Yes** — M8, and **M9 models CD's withdrawn filter implemented carelessly** |
| `DuplicateEdgeHonestCountTests` (B26) | **Yes** — M10 floor, M11 ceiling |
| `CoreDataSuiteIsolationGuardTests` (B24) | **Yes** — M12 names the lapsed file |
| `InboxClipRecycleTests` batch round-trip (coverage gap found: **neither batch recycler had any test**) | **No** |

**The B24 guard flagged itself on its first real run** — its self-test embeds `StorageService(inMemory: true)` as a fixture. The self-test passed; the *walk* found the false positive. Same shape as the set-aside scanner that split source on `"/// "` and passed its own mutation. Resolved by excluding that one file via `#filePath`'s basename, with `sources.count - scanned.count == 1` asserted so it can never become an opt-out list.

---

## What was NOT verified

**This is an absence section. It is the part most expensive to inherit wrong.**

- **B24's fix is not proven to prevent the abort** — only the mechanism, the population and the guard's bite. See the framing above.
- **B26's write path is escalated, not fixed** — it cannot be reproduced locally, and the reconcile is unwritten.
- **The four narrow device items are still unverified on device:** C2 step 3's partition, B17's untitled memory, B18's chip identity.
- **Ruling 1 and ruling 2 have had no device pass.** Both change what the user sees and what a destructive action destroys; both are proven in tests only. The device pass predates them.
- **`deleteSession`'s recycle path is not exercised end-to-end** — `recycleTargets` is unit-tested and the batch recyclers are tested at the manifest, but the view function calling them is private and undriven.
- **B23's memoization is unwritten** — now with a measured target rather than a suspicion.
- **The layout flip is unruled** — a *what*, not a parameter change.
- **Enumerations trusted rather than re-counted:** the "52 of 57" population was swept mechanically this session; the "~59 source-scan assertions" figure for C2 step 5 is inherited from the prior log and **not** re-counted.
- **`ClipClusterProposer` contains no read of `.id`** — verified by grep over that file only, not across the whole call graph.

---

## Open threads

- Four narrow device items → **B23's memoization** (target: 532 ms in the first 2.0 s) → **the layout flip ruling**.
- **B26's reconcile** (C-family) with the survivor policy already ruled.
- **C2 step 5** — retires ~59 source-scan assertions; the gate count will fall while coverage rises.
- Carried: B19, B22 ⊘ retired, D1 · D3 · D4 · D7 · F34/C15 · D9b · C1–C15.

## Risks

- **`main` and `f8` are 41 apart.** Pushed, so the exposure is integration, not loss.
- **B24 may recur.** If it does, it is a second mechanism — treat it as new, not as this fix failing.
- **The watch pair was erased mid-session** after two consecutive wedges (the second showing an `IOSSHLMainWorkspace` denial on the UI-test runner — launch/infrastructure class, not a test failure). Both `pkill`s produced the documented **exit 144**. Runtimes held.
- **A launch denial recurred repeatedly on the phone sim** and cleared each time on erase or explicit pre-boot; the working remedy is to boot the destination explicitly before invoking `xcodebuild`.
- Disk fell to **~12 Gi** at its lowest. Bundles cleared at close.
