# CRAP Score Audit — Hi Mem iOS Codebase

_2026-06-07 · 136 Swift files · 30,507 lines (production code only; ~180 / ~37k incl. tests)_

---

## Overall Score: 14 (Smelly — three bodies above the 15-CC threshold; one new ~1.6k file with good intra-file decomposition but a deferred extraction; the rest acceptable to clean)

Production file count down 141 → 136 (-3.5%) but lines up 27,748 → 30,507 (+10%) — the storage-architecture overhaul (8 phases of ubiquity work) and the photo/video description feature both landed cleanly, but the legacy mega-views absorbed more state instead of shedding it. `JournalView.body` and `EntryExpandedView.body` are both worse than last audit; `PermissionWizardView` is the new giant (NEW since May 28: 0 → 1607 lines) but its body is well-bounded thanks to per-step view structs. No new critical (CC > 30) functions. Net: file-size growth on the same legacy mega-views is the structural risk worth tracking — and we should land at least one extraction before launch so the trend doesn't continue post-1.0.

---

## Scorecard

| File | Lines | Funcs | Top CC | Grade | Note |
|------|-------|-------|--------|-------|------|
| PermissionWizardView.swift | **1607** | ~32 | **16** (body) | **C** | NEW (May audit had no file). 13 sub-step view structs each with their own bodies — good intra-file decomposition. `body` is a 13-arm switch over `WizardStep`; per-step views are 50-100 lines apiece. File-size is the concern, not function complexity. |
| EntryExpandedView.swift | **1184** | ~25 | **22** (body) | **D** | Was 1248/CC 10. File shrank 64 lines but body CC went UP because more inline conditionals landed for the description editor wire-up, media viewer sheet, organize-pass card, edit-mode swaps. The previously-extracted `EntryAppendCoordinator` did its job; the body absorbed new responsibilities anyway. |
| VoiceCaptureScreen.swift | 824 | ~10 | ~8 (body) | B | Step 11 (June 1) extracted `VoiceCaptureOrchestrator` cleanly — body shrunk 932 → 824, function count ~25 → 10. Body is a state-driven switch over capture phase. Healthy. |
| SettingsView.swift | 810 | ~8 | ~12 (body) | C | Grew 664 → 810 (+22%). Added: AI & Organizing list, Plus override picker, Captures toggle, Storage explainer. Form-driven; lots of inline conditionals but mostly trivial. |
| SessionListView.swift | 790 | ~30 | ~6 (body) | B | NEW in May audit. Unchanged this cycle. Session-first Captured Clips v2; well-decomposed. |
| EntryLifecycleService.swift | 763 | ~34 | 6 (mergeDuplicateEntities) | B | Was 758. Added `updateMediaDescription`. 34 small functions, no hot one — 30 ifs / 38 guards / 49 fors fan out cleanly across the service. Query split is still overdue (flagged May 28). |
| ProjectDetailView.swift | 752 | ~12 | ~10 (share-text flow) | C | Grew 585 → 752 (+29%). Share-text flow absorbed dual-mode (ubiquity vs PHAsset) media routing. The PhotoKit-vs-ubiquity branching could extract into a `MediaShareCollector` helper. |
| EntryCardView.swift | 730 | ~10 | ~14 (body) | C | Was 782/CC 14. Same CC, slightly smaller. Density branching unchanged from May. |
| SearchView.swift | 729 | ~10 | 8 (filterSuggestions) | B | Unchanged from May. |
| InboxManifest.swift | 702 | ~22 | ~7 (load) | B | Watch-sync consolidation (May 30) still holding the line. |
| JournalView.swift | 652 | ~7 | **26** (body) | **D** | Was 856/CC 20. File shrunk 204 lines via `JournalCaptureCoordinator` (CRAP Batch 5) but body CC went UP — 15 ifs + 6 fors + switches now stack inline. The root god-view is *still* the root god-view; extractions are landing around it, not into it. |
| OnboardingView.swift | 633 | ~8 | <8 | A | Unchanged. |
| WatchSessionDelegate.swift | 623 | ~12 | <8 | B | Watch sync consolidation locked. |
| CreateMemoryFromClipsSheet.swift | 592 | ~20 | 3 (body) | B | Lost 68 lines as ubiquity move retired the inbox path. |
| ProcessingEngine.swift | 591 | ~18 | 8 (processEntry) | B | Grew with tier routing matrix (#39) — `processEntry` now has the four-bucket routing but stays compact. |
| SpeechService.swift | 531 | ~18 | <8 | B | Unchanged. |
| WatchInboxNotificationCoordinator.swift | 516 | ~12 | <8 | B | Unchanged. |
| StorageService.swift | 500 | ~22 | 7 (init) | B | Grew 408 → 500 (+23%) with two-store split for `ProcessingTask`. `init()` is the most branchy (cloud + local descriptions + load-fallback) but reads as a checklist, not a maze. |
| ChronologicalCaptureStream.swift | 482 | ~14 | ~6 (per struct) | B | Grew with `MediaCard` + `MediaDescriptionEmpty/Filled`. Each struct's body stays small; `panels` computed property dropped from 65 lines to 11 when photo-strip grouping retired. |
| AudioPlayerSheet.swift | 365 | ~22 | 6 (hero switch) | A | Refactored to use `EditTextSheet`. Was a NavigationStack with inline player+editor; now delegates chrome to the template, keeps state machine. Cleaner. |

---

## Cross-File Top Functions by Cyclomatic Complexity

| Rank | Function | File | CC | Lines | Verdict |
|------|----------|------|----|-------|---------|
| 1 | `body` | JournalView.swift | **26** | 257 | **Critical** — worsened from 20. Inline conditionals continue to stack. |
| 2 | `body` | EntryExpandedView.swift | **22** | 384 | **Smelly** — worsened from 10. New description-editor + viewer wiring landed inline. |
| 3 | `body` | PermissionWizardView.swift | **16** | 134 | Borderline — but it's a clean 13-way switch over `WizardStep` delegating to extracted sub-views. Honest CC. |
| 4 | `body` | EntryCardView.swift | ~14 | 140 | Borderline (unchanged from May). Density-driven. |
| 5 | `body` | SettingsView.swift | ~12 | ~250 | Acceptable — Form-driven, branchless within sections. |
| 6 | `migrateOne` | MediaReferenceUbiquityMigration.swift | 10 | 67 | Acceptable — guards-and-cases checklist. |
| 7 | `init` | StorageService.swift | ~9 | ~80 | Acceptable — two-store setup with fallback path. |
| 8 | `runRestoreStateMachine` | PermissionWizardView.swift | 9 | 67 | Acceptable — sequenced phase machine. |
| 9 | `processEntry` | ProcessingEngine.swift | 8 | ~40 | Acceptable — tier × AI × online routing matrix reads cleanly. |
| 10 | `filterSuggestions` | SearchView.swift | 8 | ~60 | Acceptable (unchanged). |
| 11 | `loadVideo` | MediaViewerView.swift | 7 | ~45 | Acceptable — ubiquity vs PhotoKit dispatch. |
| 12 | `downloadStatus` | UbiquityStore.swift | 5 | ~40 | Clean — 4-way state switch. |

---

## Critical Findings

### 1. JournalView.body Regressed — CC 20 → 26

The extraction work paid off in file size (-204 lines) but failed to extract from the body itself. The 257-line body now stacks 15 `if` / 6 `for` / 1 `switch` / 1 ternary in linear flow: memory-vs-projects toggle → inbox banner → topic filter → memories list → empty state → FAB → error toast → undo toast → search nav → detail nav → inbox nav → Siri intent → topic approval sheet → album sync alert → voice + camera error dialogs → quick-action handler → daily nudge sheet.

**Each new pre-launch feature has converged here.** The recent additions:
- Pricing C1 / C3 trigger sheets
- PermissionWizardView restore-path nav
- AlbumSyncService prompt routing
- Photo description sheet routing

**Decomposition target:** finally pull `JournalNavigationLayer` (search/detail/inbox links), `JournalSheetStack` (topic approval + album sync + voice/camera errors + daily nudge), and `JournalQuickActionHandler` (the Siri / quick-action dispatcher). Body becomes a 60-80 line orchestrator over those four pieces. Estimated 2 hours; -16 CC.

### 2. EntryExpandedView.body Regressed — CC 10 → 22

The May 28 audit specifically called out this body's improvement to CC 10 via the read/edit split. That win has been undone: the body grew 384 lines and absorbed every new media-fragment editor wire-up (transcript editor sheet, audio player sheet, note editor sheet, description editor sheet, viewer presentation, organize-pass review surface).

**The pattern:** every new editor adds another `.sheet(...)` modifier plus state vars (`audioPlayerForFile`, `noteEditorTarget`, `selectedMedia`, etc.) plus a callback closure plus the `private func updateXxx` glue. Five fragment-kinds × five operations = the matrix is the cost.

**Decomposition target:** extract a `MediaFragmentEditorStack` view-modifier that bundles all the per-fragment sheets and their state + callbacks into a single attached modifier. The body shrinks to ~150 lines; the matrix moves into a focused file. Estimated 3 hours; -10 CC.

### 3. PermissionWizardView is the New Giant — but Honestly Decomposed

1607 lines is a lot of code for what was zero on the May 28 audit. The intra-file decomposition is good (13 separate per-step view structs) and the body's CC 16 is the price of the switch over `WizardStep`, not a tangle. The risk here isn't function complexity — it's **file-as-architecture**: thirteen view structs in one file is awkward navigation and tempts other contributors to add wizard-step 14 inline rather than promoting a new file.

**Decomposition target (lower priority):** move the per-step view structs (`WizardWelcomeView`, `WizardMicView`, `WizardCameraView`, etc.) into a `Views/Onboarding/Steps/` subdirectory, one file per step. Container file (`PermissionWizardView.swift`) shrinks to the dispatch body + state-machine logic + sub-step view dispatch, ~600 lines. Estimated 2 hours; no CC change, but unblocks parallel edits.

---

## Net Movement vs. May 28

| File | Then | Now | Δ Lines | Δ Body CC |
|------|------|-----|---------|-----------|
| JournalView.swift | 856 / CC 20 | 652 / **CC 26** | **−204** | **+6** |
| EntryExpandedView.swift | 1248 / CC 10 | 1184 / **CC 22** | −64 | **+12** |
| EntryCardView.swift | 782 / CC 14 | 730 / CC 14 | −52 | 0 |
| EntryLifecycleService.swift | 758 / 30 funcs | 763 / 34 funcs | +5 | (dispersed) |
| ProjectDetailView.swift | 585 / B | 752 / C | +167 | +new branching |
| StorageService.swift | 408 / B | 500 / B | +92 | acceptable |
| ProcessingEngine.swift | 450 / B | 591 / B | +141 | tier-routing matrix |
| _PermissionWizardView.swift_ | _(none)_ | _1607 / CC 16_ | _+1607_ | _new_ |

**The honest read:** the storage architecture rebuild (Phases 1-8) added ~600 lines of real code (UbiquityStore, MediaResolver, MediaReferenceUbiquityMigration). The photo description feature added ~300 lines. The PermissionWizardView landed ~1600 lines. None of those is the problem — they're clean.

**The problem is JournalView.body and EntryExpandedView.body absorbing every new feature inline instead of extracting receiving surfaces.** Three feature cycles in a row, the same two bodies have either stayed smelly or worsened.

---

## Recommended Pre-Launch Actions

In order of value:

1. **Extract `MediaFragmentEditorStack` from `EntryExpandedView`** (3 hours, -10 CC). This will pay forward immediately as future fragment types are added.
2. **Extract `JournalSheetStack` and `JournalNavigationLayer` from `JournalView`** (2 hours, -16 CC). Brings the root god-view back under the smelly threshold.
3. **Move PermissionWizard step views into `Views/Onboarding/Steps/`** (2 hours, structural only). Defer if launch timeline is tight — no functional risk.

Total: ~7 hours for both critical CC fixes plus the structural cleanup. Acceptable to ship at v1.0 without these, but the trend across three audits says they'll only get worse.

---

## Acceptable / Clean (Not Listed Above)

Everything else passes — that's most of the codebase. Notable callouts on the clean side:

- **UbiquityStore (319 lines)**, **MediaResolver (57 lines)**, **MediaReferenceUbiquityMigration (224 lines)**, **EditTextSheet (123 lines)**, **PhotoDescriptionEditSheet (123 lines)** — all new this cycle, all under CC 10 per function, all well-documented.
- **AudioPlayerSheet** refactor went the right direction: chrome moved into `EditTextSheet` template, the file shrank from 404 → 365 even though it gained two new media states and the unified-edit-sheet wiring.
- **ChronologicalCaptureStream** — the `panels` computed property dropped from 65 lines of strip-grouping logic to 11 lines of straight per-item enumeration when the photo-strip retirement landed. Net CC reduction.
- **ProcessingEngine.processEntry** — the new tier-routing matrix is non-trivial but reads as a 4-bucket dispatcher with explicit pre-conditions, not a maze.

---

_Audit derived from branching-keyword counts (`if`, `guard`, `case`, `switch`, `for`, `while`, ternary) approximated against function bodies. Test coverage component of true CRAP not computed — assumed coverage is unchanged from May 28 baseline since no broad test removal landed._
