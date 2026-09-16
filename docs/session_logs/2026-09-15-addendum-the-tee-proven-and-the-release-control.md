# Session log · 2026-09-15 (addendum) · the tee proven on hardware, and a control that disconfirmed

Facts only. Immutable. **Written for a context-free reader.**

**This is an addendum, not a revision.** `2026-09-12-to-09-15-the-collection-chase-and-the-tee.md` stands as written and was sealed before this pass. It records the tee as **unproven on hardware**. That is no longer true, and two of its open items are now closed or sharpened.

**No commits.** One device pass, one control run, no code changed. Repo unchanged at **`c809627`**, 83 ahead of `main`, 0 unpushed.

---

## ① THE TEE IS PROVEN ON HARDWARE

Debug build installed over the existing app (no wipe), launched **20:02:19 EDT**. `Library/Logs/device.log` existed within seconds — **3 KB, mtime 8:02 PM** — and was pulled with:

```
xcrun devicectl device copy from --device <udid> \
  --domain-type appDataContainer --domain-identifier com.himem.app --user mobile \
  --source Library/Logs/device.log --destination <local>
```

**No sudo. No password. No retention window. No third-party-persistence question.** 32 lines returned, all four categories present — `[WC]`, `[Build]`, `[Launch]`, `[Inbox]` — so the Guard-the-Caller property holds on device, not merely in the suite.

**The build stamp is in the evidence, as designed:**
`2026-09-15 20:02:19.822 [Build] [HiMem][Build] v1.0 (28) · binary built 2026-09-15 20:02:00`

**CLI gotcha, recorded so it is not retyped wrong:** `devicectl device info files` takes **`--username`**; `devicectl device copy from` takes **`-u/--user`**. The same concept, two spellings, and the wrong one fails with `Unknown option`. Cost one invocation.

**Consequence: the collection class is removed, not merely mitigated.** One warm launch delivered more readable diagnostic than twenty hours of archive collection did on 09-14.

---

## ② READING #2 — MEASURED BY OUR OWN INSTRUMENT, ON A RELEASE BUILD

From the wiped **Release** install (launch 20:05:19, arc armed 20:05:20.401):

```
20:05:21.723  [CKArc] setup ended ok +1321ms
20:05:21.731  [CKArc] import started +1329ms
20:07:10.431  [CKArc] import ended FAILED +110028ms err=… (Cocoa error 134419.)
20:07:10.433  [CKArc] import started +110032ms
20:07:10.978  [CKArc] import ended ok +110577ms
```

**This is the first `setup` event the arc has ever logged.** Elapsed figures are from `armedAt`, so setup completes **≈1.3 s after arm, ≈2.7 s after launch**.

Against the 09-14 Debug run measured with Apple's `PFCloudKitSetupAssistant` (setup +3.0 s from launch, import ~108 s), the two agree closely across **two builds and two independent instruments**:

| | 09-14 Debug (Apple's instrument) | 09-15 Release (our instrument) |
|---|---|---|
| setup complete | +3.0 s from launch | +1.32 s from arm (~2.7 s from launch) |
| import duration | ~108 s | **110.0 s** |
| import outcome | **FAILED** | **FAILED**, retry ok +0.5 s later |

**The ~17–21 s figure stays retired**, now on two measurements rather than one. Qualifiers still attached: one device, one dataset, one account, one network.

---

## ③ THE CONTROL DISCONFIRMED THE HYPOTHESIS — `initializeCloudKitSchema` IS EXONERATED

**Hypothesis under test** (recorded 09-15, ruled by Tom to be controlled before any diagnosis): the first-import failure and its ten `CD_M2M_JournalEntry_topics` faults are a **Debug-only artifact**, because `initializeCloudKitSchema` is `#if DEBUG`-gated and is the only thing in that window that does not ship.

**Protocol stated before the run:** Release + wipe → observe; a run that merely succeeds answers *"does it pass now"*, not *"was the hypothesis right"*.

**Result: the Release build does not run `initializeCloudKitSchema`, and the first import failed anyway** — same shape, same ~110 s, `Cocoa error 134419`.

The hypothesis is dead on the first run; the reverse control is unnecessary, because the symptom **persisted when the variable was removed** rather than disappearing. Combined with 09-14's Debug failure, the defect is now observed in **both configurations**.

> **This is the third well-formed mechanism disconfirmed by its own control in six days** — the clone/`parallel-testing` hypothesis (09-10), the "our logging never persists" reading (09-15), and this one. Each had real supporting structure. *Finding a true difference between a working case and a failing one is not finding the cause.*

**What this upgrades, and it is bad news:** the first-import failure is **not** a debug artifact. **It reproduces in the configuration that ships.** Every wiped install / new device / restored device takes this path.

**Mitigating fact, and the reason nobody noticed:** the retry **immediately succeeds** (`import ended ok` 0.5 s later). The data arrives; the store reached 8.3 MB on 09-14. The failure is real and currently self-recovering — which is exactly why *"it seemed to be working fine"*.

**NOT established:** the meaning of `Cocoa error 134419`, and whether it is the same defect as the ten `CD_M2M_JournalEntry_topics` faults seen on 09-14. Those faults are `com.apple.coredata` lines, which **the tee cannot see** — the tee carries `DeviceLog` only. Linking the two needs a system-log read, and that is the collection path this session just retired. **Recorded as unlinked.**

---

## ④ THE DECOUPLED OBSERVER, VINDICATED DIRECTLY

`ef41a91` was argued from structure. It is now observed:

```
20:05:20.400  [LifeDx] first-import watch armed (timeout=3.0s)
20:05:21.729  [LifeDx] ck event type=1 succeeded=false ended=false +1328ms
20:05:21.731  [CKArc]  import started +1329ms
20:05:23.524  [LifeDx] first-import phase → complete (3s fallback — no import event arrived) +3122ms
   … 107 seconds during which the coupled design would have been deaf …
20:07:10.431  [CKArc]  import ended FAILED +110028ms
```

**`FirstImportState` gave up at +3.1 s. The import it was waiting for did not end until +110 s.** Under the single-observer design the observer would have been removed at +3.1 s and **the failure would have been invisible** — which is, precisely, how reading #2 was void three times.

The arc never latched, never removed its observer, and reported for the full 110 s.

**A separate finding, cosmetic but wrong:** the fallback message reads *"no import event arrived"*, and that is **false** — `[LifeDx] ck event type=1` was logged **1.8 s earlier**, by the same subsystem. An import had arrived; it had not *ended*. A reader of that line would conclude no import was in flight while a 110-second one was. **Copy defect in `FirstImportState`'s fallback log. Flagged, not fixed.**

---

## ⑤ B29 — NOW PROVEN UNANSWERABLE FROM A WIPED INSTALL, AND BLOCKED UPSTREAM

Predicted in advance on 09-15; now evidenced directly, twice, from the device's own file:

```
[InboxDx] sweep trigger=scene-active total=0 pending=0 ids=[] awaitingBytes=0 ids=[]
[InboxDx] retry not scheduled — queue drained
```

`awaitingBytes=0` on a **wiped install with all 18 `.caf` files present in the ubiquity Inbox**. The manifest is the source of truth for what is expected; **files alone do not create rows**, so `awaitDownloads` has nothing to await and never arms. The arming receipt (`awaiting ubiquity downloads for N clip(s)`) is **absent**, and is now absent *as read*, not absent *as uncollected*.

> **A wiped install can never answer B29.** That is settled, not estimated.

**And the manufactured stranded clip is blocked upstream:**

```
[WC] iPhone session activated — paired=true watchAppInstalled=false reachable=false
```

**The HiMem watch app is not installed on the physical Apple Watch**, and the watch was not listed by `devicectl` at the time of the pass. No watch capture ⇒ no clip ⇒ no stranded clip. Per Tom's instruction not to improvise another route, the pass **stopped here rather than substituting a different experiment**.

**B29's close condition is unchanged**, and only `WatchSessionDelegate:570` (`ubiquity update — re-entering sweep`) satisfies it — never `:508` (`retry timer fired — re-entering sweep`).

---

## What was NOT verified

- **`Cocoa error 134419` is unidentified**, and its relationship to the 09-14 `CD_M2M_JournalEntry_topics` faults is **unestablished**. The tee cannot see Apple-subsystem lines by design.
- **The failure's consequence is not characterised.** The retry succeeds and data arrives; whether anything is lost, deferred, or merely slowed on a real new-device setup is unknown. No user-visible symptom has been attributed to it.
- **Only one account, one dataset, one device.** The failure has never been reproduced elsewhere.
- **No wiped Debug run was taken this session** — the Debug data point is 09-14's. The build was reinstalled over the top deliberately, to avoid a needless 110 s re-import.
- **The tee's rotation has never fired on hardware.** The device file is 3 KB against a 1 MiB cap; rotation is simulator-verified only (M4).
- **The tee has not been observed on a phone left unattended**, which was one of its motivating cases.
- **B29 remains unproven in both directions** — the fix is not shown to work and is not shown to fail.

## Open threads (delta from the sealed log)

- **CLOSED: the tee is proven on hardware.** The sealed log's absence-section entry is superseded by ① above.
- **CLOSED: the Release control.** `initializeCloudKitSchema` exonerated; the failure ships.
- **NEW: the first-import failure is a shipping defect** — `Cocoa error 134419`, self-recovering on retry, cause unknown, present on every wiped install.
- **NEW: `FirstImportState`'s 3 s fallback log misreports** *"no import event arrived"* when one has.
- **SHARPENED: B29** needs a watch capture, and **the watch app is not installed on the physical watch.** That is the next blocker, and it is a setup step.
- Unchanged: D1 (ruled open; RC facts dated 2026-09-15) · the `Documents/Inbox/` fallback conflict · the memory canvas · ④ out-of-range · B26 · B27 · B30 · the layout flip · C2 step 5 · C1/C8 · D3 · D4 · D7 · D9b · F34/C15 · B19.

## Risks

- **A shipping first-import failure is now known and uncharacterised.** It self-recovers today; nothing guarantees it will on a slower network, a larger dataset, or a colder start.
- **The device currently carries the Debug build** (reinstalled over Release, no wipe), which is the normal dogfood configuration and the one that publishes Development schema.
- The tee writes on every launch of every build including TestFlight; rotation is unexercised on hardware.
