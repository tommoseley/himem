# Session log · 2026-08-10 (addendum) · the freeze confirmed · the probe · the in-flight defect

Facts only. Immutable. **Written for a context-free reader.** Covers `c234904..58e431d`.

**This is an addendum, not a revision.** `2026-08-05-to-08-10-2b-ii-revert.md` stands as written and contains none of the below.

---

## Repo position

- Branch **`f8-overlay-and-wiring`** @ **`58e431d`**, **7 ahead of origin, UNPUSHED**.
- **`main` @ `36ce159`**, still never involved.
- Tree clean of tracked code **except the 2b-ii-b red**, deliberately uncommitted so the branch never carries a knowingly-failing gate. `docs/design/` holds Tom's uncommitted work plus **B14–B18**.

### Gate

| Scheme | Result | Destination |
|---|---|---|
| `MemoryStream` | **1406 cases / 192 suites** — 1395 passed, 3 skips, **8 deliberate failures** | sim `E3C0710E` (**iOS 26.4.1**) |
| `Himem Watch Watch App` | **34 / 6, 0 failed** | watch `B17233F6` + paired `74EED5FE` (**watchOS 26.5**) |

The 8 are `SpeechAssetGate`, membership byte-identical. Runtimes held; no rotation.

---

## THE FREEZE IS CONFIRMED CLOSED ON HARDWARE

`18021bc` (the `ClipGroup.id` sentinel) was previously closed **only in reasoning and a red-first test**. Device now confirms it: Clips draws, `[BenchPerf]` runs to `body #125` with regroups at 0.3–0.9 ms throughout. That was the last thing gating the 2b-ii redo.

## B16 CONFIRMED BY MEASUREMENT, NOT INFERENCE

Added `lens=` (`lensClips.count`) to `[BenchPerf]`. Device shows **`lens` falling in step with `sessions` while `clips` holds at 27** — never `lens` steady while `sessions` drops. So the shrinking session count is **review writes**, not a clock and not a grouping defect, exactly as B16 predicted. Previously this rested on inference plus a screenshot.

*Cost stated at the call site:* one extra grouping pass per body, and the `regroup` line prints it, so an instrument that began distorting what it measures would say so.

---

## THE PROBE — and it caught a real regression on its first run

**2b-ii-c is atomic** (absorber and grouper group media by different rules), so the swap is a 76-reference edit that cannot be landed partially. `2b-ii-c1` therefore composes the new bench **alongside** the old and reports disagreement. Nothing renders from it.

It immediately fired: **`bench DIFFER · oldCount=4 newCount=3`**, only ever *inside* a retry sweep, `AGREE` in every quiet window.

### The defect, and `newCount` was the wrong number

`RenderedBench.compose` applied the lens (step 1) then partitioned in-flight **from the already-lensed set** (step 2). A **reviewed** clip that is re-arriving was dropped before reaching the in-flight region — while `SessionListView:714` feeds its `IncomingCard` list from `arrivals.sortedNewestFirst()`, **un-lensed**. The item is on screen and absent from the composed count.

**`DrawnBench` would have shipped a real regression into the value the entire redo rests on** — counting 3 while drawing 4, under a green gate, looking exactly like the class this rebuild exists to end. Invisible to every test, because every test composes its own inputs; only the device, mid-sweep, produces a clip that is *both reviewed and arriving*.

### THE FINDING WORTH KEEPING — a term that looked like the defect was the patch

The old header's `inFlightOnly` — `arrivals.clipsInFlight.keys.filter { !lensClips.contains(…) }` — reads like a rogue extra set and had been flagged as part of the header's three-set assembly. **It is not. It adds back exactly the clips the lens dropped: right intent, wrong layer.** That is why it survived F35(a) and F38 — both corrected other terms and left this one alone because it was, in effect, correct.

Recorded because the next reader will otherwise re-diagnose it as the defect and "fix" the compensation while leaving the cause.

### The fix (`58e431d`)

- in-flight partitions from `allItems`, not `lensItems` — the lens governs what is **groupable into sessions**, not what is **arriving**; an arriving clip's review state is stale by construction
- `items` composes as `groupable + inFlight` so the partition property (`count == loose + clustered + inFlight`) stays true

**Red-first on real device-found behaviour:** `bench.inFlight.count → 0`, then `bench.count → 0`, then green (26/26). Mutation-verified twice, 0 compile errors each, each naming the guard. `anUnreviewedArrivingClipStillCounts` pins the converse so the fix cannot degrade into "in-flight ignores the lens in both directions".

## SECOND PROBE — all AGREE

Post-fix device run: **every reading `AGREE`, including through five retry sweeps.** No `DIFFER` anywhere, where the prior build fired it four times. The in-flight fix was the whole difference.

**CAVEAT, AND IT MATTERS: this bench is voice-only.** The absorber and the grouper can only diverge **when media is present**. `AGREE` proves no divergence in the count arithmetic on a media-free bench; it does **not** prove the margin shift is absent. *Untested, not disproven.* Tom is dropping a photo near a session boundary before the next session to convert this into a number.

---

## Items logged this stretch

| # | Item |
|---|---|
| **B15** | **RAISED ⏸ → ▶.** Unbounded 30 s retry with no backoff/cap/terminal state is now a **visible UX defect**: the Clips screen empties and rebuilds every ~15 s. It also drives most `body` passes and most `Publishing changes from background threads` noise, and it is what made the `DIFFER` window periodic. Fix shape: a file's arrival is an **event, not a poll**. |
| **B16** | ✅ explained — the New session count shrinking is P7-2 working, now measured. |
| **B17** | Two copy items: cluster title *"Together at Sun 5:44 PM"* asserts an event the card only proposes; Clip Detail states "not in any memory" twice in one sheet. |
| **B18** | **Duplicate `ForEach` ID**, live: `ClipsTabView:1574` — `ForEach(memoryTitles.prefix(3), id: \.self)`. Memory *titles* as identity; SwiftUI logged "undefined results". **Same family as the `ClipGroup.id` freeze.** `ProjectCardView:59` shares the shape over `topicNames`. |

---

## What was NOT verified

- **The absorber/grouper margin shift.** The only remaining unknown in the swap. Needs a bench with media.
- **F37 remains unruled** — the list header reads the lens (3) while the drill-in is deliberately unfiltered (4). Both are correct for their own scope; the *ruling* is what makes them differ. Seen again on device this stretch. Worth ruling before ship: a header saying 3 above a card whose glyph says 3, opening to 4 rows, is arithmetic the user must reconcile.
- **B18 has not been observed to misbehave**, only warned about — but the freeze came from the same class and also looked harmless first.

## Open threads

- **2b-ii-c2 — the swap. FIRST THING NEXT SESSION, and it lands as ONE COMMIT or not at all**: header and cards move together, intermediate states do not compile. Against a fully measured target once the photo reading is in.
- The 2b-ii-b red (`theHeaderAssemblesNoCountOfItsOwn`) stays uncommitted until the swap turns it green.
- Carried: B14 (NLTagger), B15 ▶, B17, B18 · D1 · D3 · D4 · D7 · F34/C15 · D9b · C1–C15.

## Risks

- **The swap is all-or-nothing.** There is no partial landing; a half-done edit leaves the tree broken. That is the reason this session closed here rather than starting it — the reverted 2b-ii was itself written at the tail of a long stretch, and that is not a coincidence worth reproducing.
- **`AGREE` is easy to over-read.** It is a media-free result. Anyone treating it as "the margin shift does not exist" will be surprised by the first photo near a boundary.
- Disk 24 Gi at close; derived-data trees cleared.
