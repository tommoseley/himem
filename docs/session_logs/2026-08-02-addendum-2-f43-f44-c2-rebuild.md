# Session log · 2026-08-02 (addendum 2) · F43 · F44 · the troika · C2 rebuild steps 1 + 2a

Facts only. Immutable. **Written for a context-free reader.** Covers `89e77df..e311b73` — everything after addendum 1, which closed at F42.

**Second addendum on one date.** `2026-08-02-device-pass-b10-f24-f25.md` and `2026-08-02-addendum-capture-gate-merge-f35-f42.md` both stand as written and contain none of the below.

---

## Repo position — THE BRANCHES ARE DELIBERATELY NOT LEVEL

- **`main` @ `36ce159`** (F44). **`f8-overlay-and-wiring` @ `e311b73`** (C2 step 2a). Both pushed, 0/0 with origin.
- **The two rebuild commits are on `f8` only, on purpose.** They are additive and **inert** — no production code calls `RenderedBench` or `BenchInventory` yet. `main` is therefore exactly as safe as it was before the rebuild started, which is why the session stopped here.
- Tag `integration-2026-08-02` → `de67dd5`. Tree clean of tracked code; `docs/design/` holds Tom's uncommitted work.

### Gate

| Scheme | Result | Destination |
|---|---|---|
| `MemoryStream` | **1384 cases / 192 suites** — 1373 passed, 3 documented skips, **8 deliberate failures** | sim iPhone 17 Pro `E3C0710E` (**iOS 26.4**) |
| `Himem Watch Watch App` | **34 cases / 6 suites, 0 failed** | watch `B17233F6` (boot its paired iPhone `74EED5FE` too) |

The 8 are `SpeechAssetGate`; membership byte-identical. Counts moved 1350/189 → **1384/192**. All gates ran with an isolated `-derivedDataPath` in the scratchpad.

**One run this stretch was a LAUNCH FAILURE, not a red** — `SBMainWorkspace` "Busy (Application failed preflight checks)", 0 compile errors, no `Test run with` line, 1 case / 1 failure in the bundle. It cleared after `simctl shutdown all`, so it was busy state and the device was not spent. Recorded because the bundle summary read as a catastrophic result.

---

## THE HEADLINE — the class was root-caused, and the root cause is a set that does not exist

A `/effort ultracode` troika (20 agents, 5 surfaces, adversarial verification, 1.84M tokens) was run on the bench-set arithmetic with a brief that was explicitly **not** to find more instances but to explain why the class survives every fix.

**Finding: "all bench clips" is VOICE-ONLY.** `composeBenchClips` unions manifest rows with materialized zero-edge **voice** refs; no photo, video or note ever entered it. **There is no "all bench items" set anywhere in the program.** Media reaches the screen through a side channel — a dictionary keyed by session id (`absorbedMediaBySessionId`) plus a cross-view singleton (`BenchAbsorbedMediaBus`) — so **every derived quantity had to remember to add a separately-scoped "+ media" term.**

Verified by hand before acting (the standing first instruction): **26 sets, 9 with more than one producer.** `KEPT-AFTER-TRIM · clips` had **four** independent producers, `· media` **three**; `ClusterTrim.keptForCommit` existed as the shared answer and was reached by one of the seven. **`RENDERED` had no producer at all** — it was the view tree, so no guard could name it.

**Each of the seven fixes added the missing term to one more consumer.** The union the screen displays had no representation in the code.

### The test finding, which is why the guards never caught it

**Across 188 test files there were ZERO behavioural invocations of any bench composition term.** Every one — `lensClips`, `sessions`, `looseSessions`, `keptClips`, `keptMedia`, `headerTitle`, `clusterSubtitle` — was `private` on a SwiftUI struct. *"What the header counted equals what the bench drew"* was **not untested; it was inexpressible.** That is why 20 of the 71 assertions in the F35–F44 suites are `String.contains` over source text: it was the only tool that could reach.

The auditor built a mutation harness against the real production files and proved the consequence:

- `keptMedia` loses its trim filter — **F44's exact defect restored — all 10 guards green**
- `keptClips` loses its filter — **F43 restored — all 10 green**
- `removedSet` returns `[]` — trim disconnected at the root — **all 10 green**
- `headerTitle` counts `sessions.prefix(1)` — **green**
- a **behaviour-preserving rename** — **fails two guards**

**Blind to wrong sets, hostile to right ones.** Also: `regroupingHasExactlyOneOwner` counted a literal, so a second writer spelled `computeSessions(applyFilter: false)` left it green.

### `UnifiedBenchGrouper` — the second `MediaBlobOrphanSweep`

Complete, tested, media-agnostic, **zero production callers**. The only production mention was a comment. The right abstraction had been built in July and never reached — which is also what bounds the rebuild: **wiring and deleting side channels, not a rewrite.**

---

## The work

### `1e48dd2` · F43 — the cluster card described its original membership
Header read *"7 clips from 3 sittings · 125 minutes apart"* over 3 kept clips. `whyText` is a stored `let` fixed at construction; the trim never fed back.

**Two of the three numbers were coincidentally right** — the kept set happened to retain both extremes, so the sittings and span were accurate by accident. Setting aside an endpoint makes the span silently wrong while still looking plausible. **A partially-correct display is more dangerous than a visibly broken one**, and `theSpanShrinksOnlyWhenAnEndpointGoes` pins exactly that.

**The commit disagreed with the card in the OPPOSITE direction from the one assumed.** The ruling anticipated that an unexcludable photo would be committed regardless; in fact `addClusterToMemory` passed `absorbedMediaRefs: []` while both session paths pass `includedAbsorbedMedia(in:)` — **no photo was ever committed from a cluster.** Bundling stranded them on the bench. Not introduced that day; F40 made it load-bearing by having the card claim them.

Also: **"Not in this memory" → "Set aside"** (memory vocabulary on a bench where no memory exists), and media became excludable — `removedByFingerprint` carried ref ids unchanged, confirmed before building rather than assumed.

### `36ce159` · F44 — three numbers, three sets, on one card
Sixth instance, **inside the card F43 had just fixed**: the subtitle read the kept set, the 📷 glyphs counted all media including set-aside, and "Show all N" read `proposal.clipIds.count` (voice only, original membership). One `keptTotal` value now serves all three.

**And a set-aside clip vanished from the bench entirely** — `looseSessions` treated the proposal's original membership as clustered. It is still new, still unconnected, still hers; hiding it is the subtractive posture J2 retired.

**A correction to F40's own reasoning, recorded because it was stated the other way:** partially-clustered sessions are unreachable *from the proposer* but the **user** creates them the moment she sets one clip aside. The subset rendering declined in F40 was required here.

**A guard wrong in both directions in one day.** F40's guard was strengthened that morning for being too weak (it accepted a mere declaration, which an unused parameter satisfies) and then broke on F44's *correct* change because it pinned one exact call expression. Rewritten to the invariant: `clusterMediaRow` is both defined and called; which set it receives is F44's guard to own.

### `4355c77` · C2 step 1 — `RenderedBench`
The union as one value: `items · sessions · clustered · loose`, composed once from explicit inputs, no SwiftUI, no Core Data. Media is an item, so the "+ media" term stops existing rather than being routed around.

The previously-inexpressible assertion now exists:

```swift
#expect(bench.count == bench.loose.flatMap(\.items).count + bench.clustered.count)
```

**`clusterSubtitle`'s seventh instance is folded in by construction** — count, sittings and span all derive from one `items`, so it is inexpressible rather than fixed. Replaces `regroupingHasExactlyOneOwner` with `composingTwiceFromTheSameInputsYieldsTheSameValue`: a pure function has nothing to regroup.

**THE FIRST MUTATION FOUND A HOLE IN THE REBUILD'S OWN SUITE.** Deleting the trim filter from `keptItems` — the F44 defect exactly — **passed**, because every test called it with an empty trim so the filter was a no-op wherever it was exercised. **The rebuild's tests had the weakness they replace**, one step in, caught only by running the mutation rather than trusting green. `keptItemsExcludesWhatWasSetAside` closes it.

### `e311b73` · C2 step 2a — `BenchInventory`, the two-store boundary
Step 2 was **split** so the highest-risk mapping lands and is gated before the 1621-line file is touched.

**Writing the mapping out exposed a latent divergence:** `syntheticClip` read `BenchClipReviewStore` for a ref's review state while the manifest row carried its own `reviewed`, and **nothing enforced that those agreed**. The item won by overwrite order; review state won by whichever store was asked. Both now follow one precedence — refs win, matching `composeBenchClips`.

**A nil `createdAt` sinking to the epoch is PRESERVED and PINNED**, not silently improved. Inherited from `syntheticClip`; such an item groups alone in 1970. Changing it is now a decision with its own evidence rather than a side effect of a refactor.

---

## What was NOT verified

- **F43 and F44 are on a device but unconfirmed.** Both were installed (stamps `21:47:25` and `22:12:02`); no pass results were reported back. The F43 commit test (bundle a cluster containing a photo, confirm it lands in the memory) and F44's set-aside-returns-to-the-bench check are both **outstanding**.
- **The F41 sequence was never run** — dismiss a cluster containing a **ref-backed** clip, record something to force a manifest write, confirm it stays dismissed, plus the background-and-reopen path. Carried from addendum 1.
- **C2 steps 1 and 2a are inert.** Nothing calls them. Their tests are **contract tests (ADR-050)** — written alongside new types, green on first run, no red-first cycle — and are mutation-verified instead (3 mutations each, 0 compile errors, exactly the named guard failing).
- **`BenchRefDescriptor`'s field copy is untestable.** Reducing a `MediaReference` to a descriptor at the boundary makes the *rules* pure; the copy itself is not covered. A stated trade, not a claim of purity.
- **Nothing since `89e77df` has been device-verified**, and the last device evidence predates F43.

## Open threads

- **C2 step 2b** — `SessionListView` reads `BenchInventory` → `RenderedBench`; delete `absorbedMediaBySessionId` (14 refs), `SessionMediaAbsorber` (6), `BenchAbsorbedMediaBus` (7). **The first step where a mistake reaches the screen**, in the file all seven defects lived in. Then 3 (`ClipsTabView`, `unplacedRefs` + `ClipsUnplacedFilter`, 11 refs), 4 (cluster card; migrate `ClipGroup` → `UnifiedSession`), 5 (retire ~59 source-scan assertions).
- **THE GATE COUNT WILL FALL AT STEP 5.** Retiring 59 source-scan assertions removes more cases than the behavioural tests add. **That is coverage improving while the number drops** — anyone reading the count alone would conclude the opposite.
- **F37** — the New count vs the opened session (`computeSessions(applyFilter: false)`, deliberate per the July 19 ruling). Logged, **needs a ruling**.
- The note-path collapsed/expanded repeat (latent) · F34/C15 · D9b · **the distribution archive (development-signed only; D1 remains the sole submit blocker)**.

## Risks

- **`main` and `f8` are not level, deliberately.** Anyone merging `f8` gets two inert commits; anyone reverting the rebuild reverts only those. Keep them un-merged until step 2b is device-verified.
- **Step 2b is the exposure.** `SessionListView` is 1621 lines and every one of the seven defects lived in it. The grouper being built and tested bounds the work; the wiring is where the defects have been.
- **Seven instances of one class in one day**, the seventh introduced by the fix for the sixth. The ruling stands: the next recurrence is the rebuild, not an eighth scope fix.
- Simulator and disk remain the binding constraints. The 8 red legs still read as a regression to anyone who skips the qualification.
