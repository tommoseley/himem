# Session log · 2026-09-15 (close) · the shipping defect, and the handoff

Facts only. Immutable. **Written for a context-free reader.**

**Third and final document for this stretch.** `2026-09-12-to-09-15-the-collection-chase-and-the-tee.md` and `2026-09-15-addendum-the-tee-proven-and-the-release-control.md` both stand as written. This one leads with the finding that matters most, records two items neither of them carries, and states the handoff.

**No commits beyond this file.** Repo at **`93b72aa`** + this, **84+ ahead of `main`**, 0 unpushed, code tree clean, simulators down, Debug build restored to the device.

---

## ① THE HEADLINE — THE FIRST CLOUDKIT IMPORT FAILS IN THE SHIPPING CONFIGURATION

**This is the highest-value finding of the stretch, and it was produced by a control that disconfirmed the person running it.**

The hypothesis under test was that the 09-14 first-import failure was a **Debug-only artifact**, because `initializeCloudKitSchema` is `#if DEBUG`-gated and is the only thing in that window that does not ship. The mechanism was well-formed and had real structure behind it.

**The control killed it.** A **Release** build — which does not run `initializeCloudKitSchema` — was installed onto a wiped container and failed the first import anyway:

```
20:05:21.723  [CKArc] setup ended ok       +1321ms
20:05:21.731  [CKArc] import started       +1329ms
20:07:10.431  [CKArc] import ended FAILED  +110028ms  err=… (Cocoa error 134419.)
20:07:10.433  [CKArc] import started       +110032ms
20:07:10.978  [CKArc] import ended ok      +110577ms
```

No reverse control was needed: the symptom **persisted when the variable was removed** rather than disappearing.

**The consequence is worse than the hypothesis was.** This is not a debug artifact. **It reproduces in the configuration that ships, and it is on the path taken by every wiped install, every new device, and every restore.**

**Why nobody noticed, stated precisely: the retry succeeds 0.5 seconds later.** The data arrives; the store reached 8.3 MB on 09-14. The defect is real, currently self-recovering, and therefore invisible from the outside — which is exactly the description Tom gave of the device on 09-14: *"it seemed to be working fine."*

**Unidentified, and recorded as unidentified:**
- **`Cocoa error 134419`** — meaning not established.
- **Its link to 09-14's ten `CD_M2M_JournalEntry_topics` faults is UNESTABLISHED.** Those are `com.apple.coredata` lines; the tee carries `DeviceLog` only and cannot see them. Linking the two requires a system-log read, i.e. the collection path this session retired.
- **The consequence is uncharacterised.** Whether anything is lost, deferred, or merely slowed on a real new-device setup is unknown. No user-visible symptom has been attributed to it.
- One account, one dataset, one device. Never reproduced elsewhere.

**Third well-formed mechanism disconfirmed by its own control in six days** — the clone/`parallel-testing` hypothesis (09-10), the "our logging never persists" reading (09-15), and this one. *Finding a true difference between a working case and a failing one is not finding the cause.*

---

## ② READING #2 IS CLOSED — ON TWO INDEPENDENT INSTRUMENTS

| | 09-14 Debug, Apple's `PFCloudKitSetupAssistant` | 09-15 Release, our own `CKArc` |
|---|---|---|
| setup complete | **+3.0 s** from launch | **≈2.7 s** from launch (+1321 ms from arm) |
| import duration | **~108 s** | **110.0 s** |
| import outcome | FAILED | FAILED, retry ok +0.5 s |

Two builds, two instruments, independent code paths, same answer.

**The ~17–21 s figure stays retired — now on two measurements rather than one.** It was inferred and never measured. Qualifiers remain attached: one device, one dataset, one account, one network.

---

## ③ `ef41a91` IS OBSERVED, NOT ARGUED

The decoupled observer was justified structurally when it shipped. It is now witnessed on hardware:

```
20:05:20.400  [LifeDx] first-import watch armed (timeout=3.0s)
20:05:21.731  [CKArc]  import started       +1329ms
20:05:23.524  [LifeDx] first-import phase → complete (3s fallback …) +3122ms
   … 107 seconds in which the coupled design would have been deaf …
20:07:10.431  [CKArc]  import ended FAILED  +110028ms
```

**`FirstImportState` gave up at +3.1 s. The import did not end until +110 s.** Under the single-observer design the observer would have been removed at +3.1 s and the failure would have been **invisible** — which is precisely how reading #2 was void three times.

The arc never latched, never removed its observer, and reported across the full 110 s. **The defect in ① is only visible because of ③.**

---

## ④ TWO FALSE LOG LINES — PHANTOM COMMENTS IN LOG FORM

Both emitted by `FirstImportState.swift`, both contradicted by the same subsystem within two seconds, both read off the device's own file this session.

**(a) The warm launch, 20:02:**
```
20:02:19.971  [LifeDx] first-import: already complete, not arming — no ck events will be logged this launch
20:02:19.973  [CKArc]  armed — every CloudKit event, for the life of the process
```
**15 CloudKit event lines followed** (counted from the artifact, not by eye). The claim was false 2 ms after it was made.

**(b) The wiped Release launch, 20:05:**
```
20:05:21.729  [LifeDx] ck event type=1 succeeded=false ended=false +1328ms
20:05:23.524  [LifeDx] first-import phase → complete (3s fallback — no import event arrived) +3122ms
```
An import event **had** arrived — logged by `FirstImportState` itself, 1.8 s earlier. It had not *ended*. `FirstImportState.swift:150`.

**Why this is its own item rather than a footnote.** These are **phantom comments in log form**: assertions about system state, written when they were true of an older architecture, left behind when the architecture changed, and now actively misleading a reader at the moment of diagnosis. (a) describes the world before `ef41a91` decoupled the arc; (b) conflates *arrived* with *ended*. This stretch already paid for the prose version of this class — a stale docstring in `InboxManifest` reached a decision about destroying user state (`be6510b`). A log line carries the same hazard with less scrutiny, because nobody reviews a log line the way they review a comment.

**Flagged, not fixed.** Both are copy in a diagnostic path; neither changes behaviour.

---

## What was NOT verified this session

- **The tee's rotation has never fired on hardware** — the device file is 3 KB against a 1 MiB cap. Simulator-verified only (M4).
- **The tee has not been observed on an unattended phone**, one of its motivating cases.
- **B29 is unproven in both directions** — not shown to work, not shown to fail. Now **proven unanswerable from a wiped install**: `awaitingBytes=0` with all 18 ubiquity files present, because files alone do not create manifest rows.
- **No wiped Debug run this session.** The Debug data point is 09-14's.
- `Cocoa error 134419`, its link to the `CD_M2M` faults, and the defect's user-facing consequence — all open, per ①.

---

## HANDOFF — the next session

**The blocker needs Tom's hands, not CC's.** The HiMem watch app is **not installed on the physical Apple Watch** (`watchAppInstalled=false`, read from the device log). No watch app ⇒ no capture ⇒ no stranded clip ⇒ B29 cannot be manufactured. **Tom will install it.** Everything downstream is ready: the tee is proven and will carry the reading, and B29's close condition is unchanged — only `WatchSessionDelegate:570` (`ubiquity update — re-entering sweep`) satisfies it, never `:508` (`retry timer fired — re-entering sweep`).

**An audit is incoming, and CC is NOT to start on it.** Tom is bringing a proposal that **clips retire as a user-facing surface entirely**. Two consequences he named:

1. **It shrinks B29 to a Watch-arrival problem** rather than a bench problem.
2. **It deletes a large amount of shipped surface.**

**This is a *what*, at ontology scale** — the Clips tab is one of the three primary objects in the locked `Clips · Memories · Projects` model. It is Tom's to rule, arrives as an audit, and per Design Authority nothing about it is CC's to begin, scope, or prepare for. **Recorded here only so the next session does not treat B29's shape, or the Clips surface, as settled while that audit is pending.**

**Do not start on it.**

---

## Risks carried forward

- **A shipping first-import failure is now known and uncharacterised.** It self-recovers today; nothing guarantees it will on a slower network, a larger dataset, or a colder start.
- **`main` and `f8` are 84+ apart.** Pushed, so the exposure is integration. Conflict-watch: `ClipsTabView.swift`, `EntryExpandedView.swift`, `ChronologicalCaptureStream.swift` — **and the incoming audit targets the first of those.**
- **The installed toolchain is two seeds stale**; D1 is ruled open and its RC facts are dated 2026-09-15.
- **The tee ships in every configuration** including TestFlight, with rotation unexercised on hardware.
- The 8 red `SpeechAssetGate` legs still read as a regression to anyone who skips the qualification.
