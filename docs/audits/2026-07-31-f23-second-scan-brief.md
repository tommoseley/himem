# F23 · second scan — brief

Written 2026-07-31, at the close of the first F23 pass. Commissioning doc for the next class-audit. Not a findings file.

The first pass was valuable and its central framing held: the disease is **layering**, and the six classes it named are real. This brief exists because of how the pass *failed*, not whether it succeeded.

---

## Instruction 1 — verify the enumeration before acting on any finding

**This is the first instruction because the first pass got enumerations wrong six times, and one of those would have made the code worse.**

The evidence, all from 2026-07-31:

1. **`DisplayModels:27-30` — misattributed.** Recorded as a phantom comment: *"'Drives the summary eyebrow' — no readers; the eyebrow reads Core Data."* It has a reader: `EntryExpandedView`'s `entry` **is** an `EntryDisplayModel`, and `:918` reads the field off it. The comment was accurate. Acting on the finding would have "corrected" a true comment into a false one **and left the real defect** — the field's omission from `==` — untouched.
2. **Transcription skip sites — undercounted.** Stated as 5 tests / 4 files. A sweep with no output cap found **8 sites / 6 files**.
3. **`TranscriptionServiceLongFormTests:40` — missed entirely.** Not in the list at all.
4. **"Permanently stranded" — overstated.** The transcoder's failure mode was described as leaving a clip *"permanently stranded in the pending manifest."* It isn't: retries exhaust, log *"next reachability/scenePhase event will cover it,"* and those triggers re-enter the send path. The clip **waits**. That distinction decides whether something is a P0.
5. **Class-5 "9 of 17"** — the watch comment pass found the underlying items sound, but the pass had to verify all of them to establish that, because 1–4 had already shown the characterisations were not reliable inputs.
6. **CC's own `.strict` sweep — production-only.** Correcting the false *"`.strict` grounding on-device"* claim, CC swept production and fixed three docs. The same false claim also sat in **two test files**. The corrected work was itself incompletely enumerated, by the same method error, on the same day.

**Point 6 is why this brief is credible.** The failure is not the first pass being careless — it is that *scanning is easy to do incompletely and the result looks identical to a complete scan.* A truncated sweep and a thorough one produce the same shape of output.

So, concretely:

- **Never let an output cap bound a completeness claim.** If the conclusion is "these are all of them," the command must be able to show all of them — filter noise out, never cap the output.
- **Scan tests as well as production.** Four of the six errors above involved test files or test-adjacent code. A claim about "the codebase" that scanned only the app target is a claim about half of it.
- **State the measurement beside the finding**, so a wrong reading is visible as a wrong reading instead of propagating as fact.
- **Re-derive the count at the moment of acting**, not from the audit's number. The count is the cheapest thing to re-check and the most expensive thing to inherit wrong.

---

## Instruction 2 — the seventh class: an invariant fixed in one instance and never crossed over

The first pass named *ownerless invariants*. The costliest instance found is narrower and worth its own class:

**The same defect, fixed on one surface and left standing on the other, in the same repository.**

- The watch's pending manifest replaced its `clips = []` decode-failure fallback on **2026-06-18** — zeroing the array orphaned every surviving `.caf` forever, so it now rescues rows by scanning the audio directory.
- The phone's inbox manifest carried the **identical** defect until **2026-07-31** (F23 T1.4), six weeks later, discovered independently.
- Neither knew about the other.

Related, same shape, same day: the poll-until-deadline fix for a wall-clock-racing test was applied to one test on 2026-07-15 with a comment describing the exact failure — and the two sibling tests in the same file kept their fixed sleeps until they flaked on 2026-07-31.

**Scan instruction:** for every defect fixed in the last quarter, ask *where else does this shape exist* — the sibling surface, the sibling test, the sibling caller. Grep the fix's distinguishing pattern rather than its symptom. This class is invisible to a per-file audit because each file is individually correct or individually wrong; the defect is the gap between them.

---

## Instruction 3 — carry the caller-side rule into the scan

The governance rule added 2026-07-31 (*Guard the Caller, Not Just the Owner*) came from three Tier-2 items that were the same failure: **a correct owner that a caller stopped consulting, with the suite green throughout.**

The sharpest demonstration: deleting the `isTransferReady` guard from the watch's transfer path left **all six** tests of the suite the governance file names as that invariant's guard passing. Only a newly-written caller-side assertion failed.

**Scan instruction:** treat "the owner is tested" as *no evidence* about the caller. For each invariant with a designated guard, ask what happens if the caller stops calling it — and whether any existing test would notice. Where the answer is "nothing would notice," that is a finding regardless of whether the caller is currently correct.

---

## What not to re-litigate

- **Class 2 is genuinely thin** and `catch {}` is zero codebase-wide. That negative result held up.
- **The watch Class-5 concentration is comment drift, not structure.** Verified across a full comment pass; the code moved three times and the prose moved once. Do not propose a rebuild there.
- **The `.strict` question is closed** (2026-07-31): summary/title grounding is `.relaxed` on both tiers by a deliberate 2026-07-24 decision; `.strict` governs only the mention drop, plus one correct use in the project short-summary path. The wiring is pinned in both directions. Do not reopen it from a comment.

## Standing constraints

The **error-surface rebuild** and the **clip-storage seam rebuild** are post-tag by ruling. The second scan may produce evidence for both; it may not start either. The `clips = []` cross-surface finding above belongs in the clip-storage seam's brief.
