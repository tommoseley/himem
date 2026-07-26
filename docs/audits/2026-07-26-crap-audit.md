# CRAP Score Audit — HiMem iOS Codebase

_2026-07-26 · 185 Swift files · 50,539 lines (production only; ~230 files / ~64k incl. tests)_

Delta baseline: `docs/audits/2026-06-07-crap-audit.md` (136 files / 30,507 lines, overall 14 · Smelly).

---

## Overall Score: 13 (Smelly — but the axis of risk moved)

**Function-level complexity got healthier; file size ballooned.** In seven weeks the production codebase grew **+49 files (+36%) and +20,032 lines (+66%)** — the July clip-model convergence, the evidence-and-context ontology, and P0-3 clip-sync. That is a lot of code, but the two things that make it *pass rather than fail* are:

1. **Both 2026-06-07 critical bodies were fixed by the recommended extractions.** `JournalView.body` fell from **CC 26 → ~7** (detail/capture/error surfaces extracted — the root god-view is finally an orchestrator). `EntryExpandedView.body` fell from **CC 22 → ~15** (the per-fragment editor wiring came out). The single most valuable pre-launch action from last audit landed.
2. **The new giants are decomposed, not tangled.** `ClipsTabView` (1929 lines, the new #1) spreads across **22 view types** with a ~CC-9 `body`; `ClipEditorModal` is ~30 small members. This is the PermissionWizardView pattern — file-as-architecture, not god-function.

**No function reaches the CC>30 critical threshold.** The one to watch is `HiMemTabView.body` at **~30, sitting exactly on the line** — an event-bus shell hanging ~13 `.onChange` observers off one `body`; each trivial, collectively at the boundary (F2b's `restorePending` observer was the most recent nudge). One regression worth naming: `ProcessingEngine.processEntry` grew **CC 8 → ~17** as tier/fallback routing expanded.

**The structural risk is now file-size/navigability, not complexity.** Files over 800 lines roughly doubled (~7 → **16**). Five files sit in 1300–1930-line territory. None is a maze, but each is a magnet for the next inline feature — the exact trend line the last three audits flagged, now on a bigger base.

---

## Scorecard

| File | Lines | Funcs/Types | Top CC | Grade | Note |
|------|-------|-------------|--------|-------|------|
| ClipsTabView.swift | **1929** | 53 fn / 22 types | ~9 (body) | **C** | NEW (Jul 11). The Clips tab — status/type filters, sessions, connections, multi-select. Well-decomposed across 22 types; `body` delegates. File-size, not CC. |
| EntryExpandedView.swift | **1694** | 37 | **~15** (body) | **C** | Was 1184 / CC 22. Grew +510 but **body CC dropped 22→~15** (per-fragment editors extracted). The decomposition the June audit recommended landed. |
| PermissionWizardView.swift | **1641** | ~32 / 18 types | ~17 (stepIfShouldSkip) | **C** | ~flat vs June (1607). The permission matrix (`stepIfShouldSkip` 7-case) tops the 11-case body router. Still one-file-many-steps. |
| SessionListView.swift | **1425** | 46 | ~11 (applyClipRetryOutcome) | **C** | Was 790 (+635). P0-3 bench-reads-refs + retry/edit/delete backing-aware paths. `body` is pure delegation (~3); the retry-outcome switch is the peak. |
| EntryLifecycleService.swift | **1410** | 57 | ~11 (migrateOrphanedContentIfNeeded) | **B** | Was 763 (+647). 57 dispersed small functions, no hot one — the orphan-note guard ladder is the densest. Query split still overdue (flagged since May 28). |
| InboxManifest.swift | **1319** | 52 | ~6 (load) | **B** | Was 702 (+617). Mass is branch-free verbatim `InboxClip(...)` field carry-forward rebuilds; low CC throughout. |
| SearchView.swift | 1014 | ~14 | ~7 (filterSuggestions) | B | Was 729. Only real logic fn is `filterSuggestions`; rest declarative. |
| SettingsView.swift | 956 | ~10 | ~10 (body) | C | Was 810. `#if DEBUG` block adds length not branching; Form-driven. |
| VoiceCaptureScreen.swift | 939 | ~10 | ~8 (body) | B | Was 824. Orchestrator split (June) still holding. |
| WatchSessionDelegate.swift | 937 | ~14 | <8 | B | Was 623 (+314). Transcription sweep + P0-3 materialize wiring. Flat. |
| ProjectDetailView.swift | 924 | ~14 | ~14 (body) | C | Was 752. Topic-filter machinery + share-text flow. |
| TutorialsHubView.swift | 861 | ~10 | ~3 (rows) | A | Declarative catalog; no logic hotspot. |
| ProcessingEngine.swift | 843 | 22 | **~17** (processEntry) | **C** | Was 591 / CC 8. **processEntry regressed 8→~17** — plus/hasAI/online boolean algebra + on-device outcome switch + fallback guard. `processReorganize` mirrors it (~15). |
| ClipAtomView.swift | 828 | 18 / 7 types | ~15 (ClipContentSlot.body) | C | NEW (Jul 11). Empty-transcript precedence ladder concentrates complexity; atom `body` trivial. |
| ClipEditorModal.swift | 806 | 18 | ~7 (clipHero) | B | NEW (Jul 16). Deliberately ~30 small members; modest peak. |
| JournalView.swift | 801 | ~7 | **~7** (body) | **A** | Was 652 / **CC 26**. **body CC 26→~7** — the June #1 critical, fixed. Detail/capture/error surfaces extracted. |
| StorageService.swift | 775 | ~24 | ~9 (init) | B | Was 500 (+275). Two-store init reads as a checklist. |
| EntryCardView.swift | 718 | ~10 | ~9 (mediaDescription) | B | Was 730 / CC 14. **Improved** — `body` no longer the peak. |
| ChronologicalCaptureStream.swift | 672 | ~14 | ~6 | B | Was 482. Per-struct bodies stay small. |
| ClipClusterProposer.swift | 613 | 11 | ~16 (distinctiveTokens) | B | NEW (Jul 4). NLP tokenization; `proposeTimePlace` BFS second (~11). Contained. |
| HiMemTabView.swift | 571 | 9 | **~30** (body) | **D** | **body ~30, on the critical line.** ~13 `.onChange` event-bus observers + `.onAppear`/`.sheet`/`.fullScreenCover` off one body. Each trivial; collectively at the boundary. Best remediation candidate. |

---

## Cross-File Top Functions by Cyclomatic Complexity

| Rank | Function | File | CC | Verdict |
|------|----------|------|----|---------|
| 1 | `body` | HiMemTabView.swift | **~30** | **At-threshold** — event-bus onChange cluster on one body; any new observer tips it over. |
| 2 | `stepIfShouldSkip` | PermissionWizardView.swift | ~17 | Smelly — permission matrix, 7-case switch with per-case ternaries. |
| 2 | `processEntry` | ProcessingEngine.swift | ~17 | Smelly — **regressed 8→~17**; tier × AI × online routing + fallback. |
| 4 | `distinctiveTokens` | ClipClusterProposer.swift | ~16 | Smelly — NLP tokenization; inherently branchy, contained + tested. |
| 5 | `body` | EntryExpandedView.swift | ~15 | Smelly — **improved 22→15**; List-row wiring + sheets. |
| 5 | `ClipContentSlot.body` | ClipAtomView.swift | ~15 | Smelly — empty-transcript precedence ladder. |
| 7 | `body` | ProjectDetailView.swift | ~14 | Borderline — topic-filter machinery. |
| 8 | `applyClipRetryOutcome` | SessionListView.swift | ~11 | Acceptable — TranscriptionService.Outcome switch. |
| 8 | `migrateOrphanedContentIfNeeded` | EntryLifecycleService.swift | ~11 | Acceptable — the orphan-note defense ladder (guarded by SynthesizedNoteRenderGuardTests). |
| 10 | `body` | SettingsView.swift | ~10 | Acceptable — Form-driven. |

---

## Critical Findings

### 1. `HiMemTabView.body` — ~CC 30, sitting on the critical line

The tab shell hangs its entire cross-tab event vocabulary off a single `body`: ~13 `.onChange` bus observers (capture routing, coachmark `restorePending`, clip-status sheets, project nav, memory/clip detail presentation, quick actions) plus `.onAppear`, `.sheet`, and `.fullScreenCover`. Each observer is individually trivial (a one-line `if`), but they sum to ~29 branch points + 1 base ≈ 30. It is not *cleanly over* 30, so not mandatory-remediation — but it has been climbing (F2b's `restorePending` observer was the latest addition), and the next bus observer tips it critical.

**Remediation:** extract the observer cluster into a `.tabRoutingObservers(...)` view modifier (the JournalView playbook — bundle onChange/sheet wiring into an attached modifier). Body drops to a ~10-line layout + a modifier chain; the observer matrix moves to a focused file. Est. ~1.5h, −18 CC. **This is the single best CRAP action in the codebase.**

### 2. `ProcessingEngine.processEntry` — regressed CC 8 → ~17

The June audit called `processEntry` a clean 4-bucket dispatcher. Since then it absorbed the on-device/cloud tier matrix, the `.safetyRefusal → never-cloud` ruling, the `.failed` task-status path, and the connectivity/hasAI/isPlus boolean algebra (P1/P1-2 work). `processReorganize` mirrors it (~15). Not critical, but it's the one function that got materially worse, and the two mirror each other — a candidate to factor the routing decision into a testable pure `route(connectivity:plus:hasAI:) -> Backend` and leave the two callers thin. Est. ~1h, −8 CC across the pair, +1 unit-testable seam.

### 3. File-size growth is the accelerating structural risk

Sixteen files now exceed 800 lines (vs ~7 in June); five exceed 1300. None is a god-function — the decomposition discipline held on the *new* code (ClipsTabView's 22 types, ClipEditorModal's small members). The risk is navigability and gravity: a 1400–1900-line file is where the next inline feature lands by default. The highest-value targets if a size pass is wanted: **SessionListView** (1425 — P0-3 grew it fast; the bench synth-adapter + backing-aware write paths could split into a `BenchClipStore` seam) and **EntryLifecycleService** (1410 / 57 funcs — the long-flagged query/command split would finally pay off). Neither is urgent; both are where mass concentrates.

---

## Net Movement vs. 2026-06-07

| File | Then | Now | Δ Lines | Δ Top-fn CC |
|------|------|-----|---------|-------------|
| JournalView.swift | 652 / CC 26 | 801 / **CC ~7** | +149 | **−19 (fixed the #1 critical)** |
| EntryExpandedView.swift | 1184 / CC 22 | 1694 / **CC ~15** | +510 | **−7 (fixed the #2 critical)** |
| EntryCardView.swift | 730 / CC 14 | 718 / CC ~9 | −12 | −5 |
| ProcessingEngine.swift | 591 / CC 8 | 843 / **CC ~17** | +252 | **+9 (regressed)** |
| HiMemTabView.swift | (not measured) | 571 / **CC ~30** | — | new at-threshold |
| SessionListView.swift | 790 / B | 1425 / C | +635 | dispersed |
| EntryLifecycleService.swift | 763 / 34 fn | 1410 / 57 fn | +647 | dispersed |
| InboxManifest.swift | 702 / B | 1319 / B | +617 | flat (verbatim rebuilds) |
| ClipsTabView.swift | (not top) | 1929 / C | new giant | ~9 body |
| PermissionWizardView.swift | 1607 / CC 16 | 1641 / CC ~17 | +34 | +1 |

**The honest read:** the two god-view bodies that worsened for three audits running were finally decomposed — the single best structural outcome since this series began. The cost of the 66% growth landed as **file size**, not function complexity, and the new code carries its own decomposition. The two things that *drifted the wrong way* are small and localized: `HiMemTabView.body` climbing to the critical line, and `processEntry` doubling. Both are ~1–1.5h fixes.

---

## Recommended Actions

In order of value:

1. **Extract `.tabRoutingObservers` from `HiMemTabView`** (~1.5h, −18 CC). Pulls the one function at the critical line back to acceptable and stops the "add another `.onChange`" drift. Highest value.
2. **Factor `ProcessingEngine.processEntry`/`processReorganize` routing into a pure `route(...) -> Backend`** (~1h, −8 CC across the pair, + a unit-testable seam). Reverses the one real regression.
3. **(Optional, size pass) Split `SessionListView` and `EntryLifecycleService`** (~3–4h). Not urgent — both are dispersed, not tangled — but they're where mass concentrates, and EntryLifecycleService's query/command split has been flagged since May 28.

Total for the two CC fixes: ~2.5h. Neither is a launch blocker (no mandatory CRAP remediation — nothing is cleanly over 30), but #1 keeps the gate honest.

---

## Acceptable / Clean (Not Listed Above)

Most of the codebase passes. Notable clean callouts this cycle:

- **The clip-model convergence files** (ClipsTabView, ClipAtomView, ClipEditorModal, ClipClusterProposer) — all NEW, all large, all decomposed under the intra-file-types pattern; not one god-function among them.
- **JournalView** — the standout win: the root god-view's body went 26 → ~7. The extraction discipline the last audit recommended was applied and worked.
- **InboxManifest / WatchSessionDelegate** — grew substantially (+617 / +314) but stayed flat on CC; the mass is verbatim field-carry-forward and sweep logic, not branching.
- **ArrivedClipMaterializer** (155 lines, NEW Jul 25) — P0-3's single-source-of-truth materializer; small, guarded, fully tested.

---

_Audit derived from branching-keyword counts (`if`, `guard`, `case`, `switch`, `for`, `while`, `catch`, ternary, `&&`/`||`) approximated against function bodies, calibrated to the 2026-06-07 baseline. Test-coverage component of true CRAP not computed; the suite is at zero known reds (2026-07-26) so coverage is assumed non-regressed from baseline._
