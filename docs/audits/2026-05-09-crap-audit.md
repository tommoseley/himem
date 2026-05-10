# CRAP Score Audit — Hi Mem iOS Codebase

_2026-05-09 · 75 Swift files · 15,152 lines_

---

## Overall Score: 11 (Acceptable, two view bodies in the smelly zone)

The codebase has roughly doubled in 11 days (46 → 75 files; 6.8k → 15.2k lines) primarily from the watch app, onboarding, and inbox-clips work. The previous remediation (Phases 1-3) shipped: `JournalViewModel` shrank 445 → 265 lines and is now a thin orchestrator; `ProcessingEngine` decomposed into discrete steps; `EntryLifecycleService` extracted. Two view files remain in the smelly zone — `JournalView.body` (CC 22) and `EntryExpandedView.body` (CC 18).

---

## Scorecard

| File | Lines | Funcs | Top CC | Grade | Note |
|------|-------|-------|--------|-------|------|
| EntryExpandedView.swift | **903** | 13 | 18 (body) | **C/D** | Mega-view: read+edit+append modes, mentions, location, capture pills |
| EntryCardView.swift | 752 | 7 | 12 (body) | **B/C** | Density-driven render; well-decomposed despite size |
| SearchView.swift | 750 | 10 | 8 (filterSuggestions) | **B** | Big file, but clean delegation to subviews |
| JournalView.swift | **706** | 3 | 22 (body) | **C/D** | Root god-view: feed/projects modes, banners, sheets, alerts |
| OnboardingView.swift | 631 | 3 | <8 | **A/B** | Linear page flow — straightforward |
| ClipInboxView.swift | 581 | 15 | 8 (clipCard) | **B** | Clean per-clip render + state machine |
| EntryLifecycleService.swift | **534** | 30 | 6 (edit) | **B** | Service > 300-line governance limit but no hot function |
| ChronologicalCaptureStream.swift | 455 | 3 | 4 (panels) | **A** | New unified fragment renderer; clean |
| SearchViewModel.swift | 373 | 22 | 7 (bucket) | **B** | Search orchestration; date-bucketing is the only concentrated branch |
| StorageService.swift | 371 | 16 | <8 | **B** | Phase 5 dropped `createTextSegment`; inMemory + cloud paths still co-located |
| SettingsView.swift | 370 | — | — | **A** | Form-driven; flat |
| ProjectDetailView.swift | 367 | — | — | **B** | Share-text composer extracted; inline rendering otherwise |
| CrucibleTheme.swift | 366 | — | — | **B** | Still bundles `TopicEditorSheet` (2026-04-28 finding still open) |
| ProcessingEngine.swift | 328 | 14 | 6 (storeEntities) | **B** | Decomposed since prior audit; clean |
| JournalViewModel.swift | 265 | 24 | 4 (recomputeFiltered) | **A** | Dramatic improvement (was Grade F, 445/CC25) |
| Most other Views/Services | 50-300 | — | <10 | **A** | Clean |

---

## Cross-File Top Functions by Cyclomatic Complexity

| Rank | Function | File | CC | Lines | Verdict |
|------|----------|------|-----|-------|---------|
| 1 | `body` | JournalView.swift | 22 | 410 | **Smelly** — view state machine |
| 2 | `body` | EntryExpandedView.swift | 18 | ~280 | **Smelly** — multi-mode view |
| 3 | `body` | EntryCardView.swift | 12 | 120 | Acceptable (density-driven) |
| 4 | `clipCard` | ClipInboxView.swift | 8 | 114 | Acceptable |
| 5 | `filterSuggestions` | SearchView.swift | 8 | 29 | Acceptable |
| 6 | `bucket` | SearchViewModel.swift | 7 | 16 | Acceptable (date classification) |
| 7 | `handleCapturedItemForNewEntry` | JournalView.swift | 7 | 59 | Acceptable (dispatch) |
| 8 | `storeEntities` | ProcessingEngine.swift | 6 | 24 | Acceptable |
| 9 | `edit` | EntryLifecycleService.swift | 6 | 37 | Acceptable |
| 10 | `processWithCloud` | ProcessingEngine.swift | 5 | 34 | Clean |

---

## Critical Findings

### 1. JournalView.body is a Root God-View (CC 22)
410-line body orchestrates feed mode toggle, projects mode, inbox banner, capture modal, undo toast, sheets (settings/inbox/topic approval), error banner, alerts, navigation. Every feature converges here.

**Smell**: every new feature added a conditional inside `body`. There's no single place where feature integration is rejected — they all land here.

**Decomposition target**: extract `JournalMemoriesView` (memories vs projects dispatch), `InboxBannerSection`, `UndoToastSection`, `JournalSheets` modifier. Body should become a 50-80 line coordinator.

### 2. EntryExpandedView.body is a Multi-Mode View (CC 18 / 903 lines)
Read mode + edit mode + append staging + topic chips + location chip + mentions + filmstrip + capture pills, all in one body. Per-fragment editing is now done by `NotePanel` and `AudioPlayerSheet`, but the host still juggles edit-mode state across the whole entry.

**Decomposition target**: `EntryReadingMode`, `EntryEditingChrome` (title field + cancel/save toolbar), `EntryAppendCoordinator` for the capture pills. The body should reduce to mode-switch glue.

### 3. EntryLifecycleService Crossed the 300-Line Service Limit
534 lines, 30 functions. No single hot function (max CC 6), but the file now spans Create / Edit / Append / Delete / Recycle / Feedback / Queries / Helpers — 8 sections. Still well-separated; not a god object yet.

**Watch for**: if new lifecycle ops land here without a new file, this trends toward god-service.

### 4. View Files Exceed 400-Line Governance Limit
`EntryExpandedView` (903), `EntryCardView` (752), `SearchView` (750), `JournalView` (706), `OnboardingView` (631), `ClipInboxView` (581), `ChronologicalCaptureStream` (455). Six views exceed the limit. Most ARE well-decomposed internally (subviews extracted) — the file just contains many subviews. SearchView and ClipInboxView are honest about it; EntryExpandedView and JournalView are not.

### 5. Architectural Smell: Append Spec Scattered
Capture-modality dispatch lives in `EntryExpandedView.handleCapturedItemForAppend` AND `JournalView.handleCapturedItemForNewEntry`, with both calling `EntryLifecycleService.append/save`. Two parallel switches, one per surface.

**Suggestion**: extract `CaptureCoordinator` that takes a `CapturedItem` + a target (newEntry vs entryId) and routes to lifecycle. Single dispatch point.

---

## DRY Status (vs 2026-04-28)

| Pattern | 2026-04-28 | Now | Resolution |
|---------|-----------|-----|------------|
| Slug generation duplicated 3× | OPEN | RESOLVED | `TopicSlugHelper` exists |
| Entity → DisplayModel mapping 3× | OPEN | RESOLVED | `EntryMapper.mapToDisplayModel` is sole site |
| `addMemory`/`removeMemory` identical | OPEN | RESOLVED | Now distinct in `ProjectViewModel` |
| `NSFetchRequest` boilerplate 15× | OPEN | OPEN | No `fetchOne<T>` helper yet; ~20 inline fetches |
| Capture modality dispatch | NEW | OPEN | Two `handleCapturedItem*` switches across views |

---

## Silent Error Handling

`grep "catch.*print"` returns **zero hits**. Phase 1 of the prior remediation landed: `ErrorState.shared.report(.saveFailed(...))` and friends are used consistently in services. Two `print()` calls survive in non-catch paths (`SpeechService:128`, `AlbumSyncService:116`) — see Security audit.

---

## Governance Compliance vs CLAUDE.md Limits

```
- No function may exceed cyclomatic complexity 15      → 2 violations (JournalView.body, EntryExpandedView.body)
- No file may exceed 400 lines (views) or 300 (services/VMs) → 6 view violations, 1 service violation
- No catch block may silently print() → COMPLIANT
- No code pattern duplicated > 2x → COMPLIANT
- Nesting depth limit: 3 levels → No hot offenders found
```

---

## Remediation Plan (Bounded Batches)

### Batch 1: Decompose `JournalView.body` (4-6h)
Extract `JournalMemoriesView`, `InboxBannerSection`, `UndoToastSection`, `JournalSheets` modifier. Target body CC ≤ 8, file ≤ 400 lines.

### Batch 2: Decompose `EntryExpandedView.body` (6-8h)
Extract `EntryReadingMode`, `EntryEditingMode`, `EntryAppendCoordinator`. Target body CC ≤ 8.

### Batch 3: `CaptureCoordinator` extraction (3h)
Single dispatch for `CapturedItem → save | append`. Removes the parallel switches in JournalView + EntryExpandedView.

### Batch 4: `fetchOne<T>` helper (2h)
Replace 15+ inline `NSFetchRequest` blocks. Improves readability + makes test mocking easier.

### Batch 5: Split `EntryLifecycleService` if it grows past 600 lines (deferred)
Currently 534 lines; not urgent. Extract `EntryQueryService` (loadRecycledEntries, recycledCount, recycledCountForTopic) on the next addition.

---

_Methodology: cyclomatic complexity counted by CLAUDE.md rules — 1 + each `if`/`else if`/`guard`/`case`/`for`/`while`/`catch`/`&&`/`||`/ternary. Coverage data not used (no per-function coverage tooling for Swift in this project)._
