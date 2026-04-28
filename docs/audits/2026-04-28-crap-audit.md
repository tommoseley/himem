# CRAP Score Audit — Hi Mem iOS Codebase

_2026-04-28 · 46 Swift files · ~6,800 lines_

---

## Overall Score: 12 (Acceptable → Borderline Smelly)

The codebase demonstrates solid architectural principles with good separation
of concerns. However, three files exceed safe complexity thresholds and
20+ error catches silently swallow failures with `print()`.

---

## Scorecard

| File | Lines | Complexity | Grade | Issue |
|------|-------|-----------|-------|-------|
| JournalViewModel.swift | 445 | 25 | **F** | God object, DRY violations, silent errors |
| ProcessingEngine.swift | 240 | 20 | **D+** | God function, 4-level nesting, duplicated slug |
| StorageService.swift | 253 | 18 | **C+** | CloudKit fallback buries happy path |
| EntryExpandedView.swift | 350+ | 16 | **C** | Mega-view (read+edit+append+topic+media) |
| JournalView.swift | 350+ | 14 | **C** | View mode switching, undo toast logic |
| CrucibleTheme.swift | 362 | 14 | **C** | TopicEditorSheet mixed into theme file |
| ComposerView.swift | 450+ | 12 | **C** | Recording state machine in UI |
| SpeechService.swift | 192 | 13 | **B-** | Acceptable, audio session setup nested |
| AlbumSyncService.swift | 166 | 10 | **B** | Good, one silent catch |
| SearchEngine.swift | 129 | 12 | **B** | Clean separation |
| ProjectViewModel.swift | 157 | 11 | **B** | DRY: addMemory/removeMemory identical |
| All Models (9 files) | 40-100 | <8 | **A** | Clean |
| Services (7 files) | 50-150 | <9 | **A** | Clean |
| Most Views (15+ files) | 50-200 | <10 | **A** | Clean |

---

## Critical Findings

### 1. JournalViewModel is a God Object (Grade F)

**Lines:** 445 · **Complexity:** 25 · **Functions >15:** editEntry (18), appendToEntry (16), saveEntry (14)

The ViewModel handles entry creation, editing, appending, deletion, recycling,
restoration, feedback, topic management, and display model mapping. These are
7+ distinct responsibilities in one class.

**Specific issues:**
- `editEntry()`: 18 decision points, 5 nesting levels, handles tag removal,
  media removal, topic add/remove, entity clearing, inference clearing,
  processing task clearing, re-processing — all in one function
- `appendToEntry()`: structurally identical to parts of `editEntry()` (DRY)
- `saveEntry()`: 14 decision points, mixes creation + topic + media + processing
- 15+ `catch { print() }` blocks — failures are invisible to the user

### 2. ProcessingEngine.processWithCloud() is a God Function (Grade D+)

**Lines:** 110 · **Complexity:** 22 · **Nesting:** 4 levels

One function does: API call, entity extraction, topic slug generation,
existing topic lookup, new topic queuing, album sync check, inference
summary creation, title update, processing task completion.

**Specific issues:**
- Slug generation duplicated at lines 73 and 100 (also in StorageService)
- Album sync proposal nested 3 levels deep inside the context.perform block
- Silent error handling throughout

### 3. Silent Error Handling (20+ instances)

Every ViewModel and Service catches errors with `print()` only. No error
is ever surfaced to the user. Failed saves, failed API calls, failed topic
creation — all silently swallowed.

**Files affected:** JournalViewModel (15), ProcessingEngine (8),
ProjectViewModel (8), TopicApprovalService (1), SearchViewModel (1),
AlbumSyncService (1), SettingsView (3)

### 4. DRY Violations

| Pattern | Occurrences | Files |
|---------|------------|-------|
| Slug generation | 3x | ProcessingEngine, StorageService |
| Entity → DisplayModel mapping | 3x | JournalViewModel, SearchViewModel, ProjectDetailView |
| NSFetchRequest boilerplate | 15+ | All ViewModels and Services |
| Media type filtering/color | 4x | EntryCardView, EntryExpandedView, DisplayModels |
| addMemory/removeMemory | 2x identical | ProjectViewModel |

### 5. Mega-Views

| View | Lines | Concern Count |
|------|-------|--------------|
| EntryExpandedView | 350+ | Read mode, edit mode, append staging, topic management, media grid, mentions, audio recording |
| ComposerView | 450+ | Composition UI, recording state, media grid, camera handling, topic picker |
| JournalView | 350+ | Feed, projects toggle, undo toast, composer presentation, navigation |

---

## Remediation Plan

### Phase 1: Structured Error Handling (Priority: Immediate)

**Goal:** Replace all `print()` error catches with structured error propagation.

**New file:** `Services/ErrorService.swift`
```
enum AppError: LocalizedError {
    case saveFailed(String)
    case processingFailed(String)
    case networkError(String)
    case mediaError(String)

    var errorDescription: String? { ... }
}
```

**Changes:**
- Add `@Published var lastError: AppError?` to each ViewModel
- Replace `catch { print() }` with `catch { self.lastError = .saveFailed(...) }`
- Add error banner/alert in JournalView that observes ViewModel errors
- **Estimated effort:** 4-6 hours
- **Files touched:** JournalViewModel, ProjectViewModel, ProcessingEngine,
  TopicApprovalService, SearchViewModel, AlbumSyncService, JournalView

### Phase 2: Extract Shared Utilities (Priority: High)

**Goal:** Eliminate DRY violations.

**New file:** `Services/TopicSlugHelper.swift`
- Single `slugify(name:) -> String` function
- Replace all inline slug generation

**New file:** `ViewModels/EntryMapper.swift`
- Single `mapToDisplayModel(_ entry: JournalEntry) -> EntryDisplayModel`
- Replace duplicate mapping in JournalViewModel, SearchViewModel, ProjectDetailView

**New file:** `Services/FetchRequestHelper.swift`
- Generic `fetchOne<T>(entityName:id:context:) -> T?`
- Replace repeated fetch boilerplate

**Estimated effort:** 4-6 hours
**Files touched:** ProcessingEngine, StorageService, JournalViewModel,
SearchViewModel, ProjectDetailView, ProjectViewModel

### Phase 3: Split JournalViewModel (Priority: High)

**Goal:** Reduce from 445 lines / complexity 25 to <250 lines / complexity <10.

**Extract to:** `Services/EntryLifecycleService.swift`
```
class EntryLifecycleService {
    func save(content:inputType:audioFilePath:mediaCaptures:topicName:)
    func edit(entryId:newContent:removedTagIds:removedMediaIds:...)
    func append(entryId:additionalContent:audioFilePath:mediaCaptures:)
    func recycle(entryId:)
    func restore(entryId:)
    func delete(entryId:)
}
```

**JournalViewModel becomes:** Thin orchestrator that calls EntryLifecycleService
and updates `@Published` state.

**Estimated effort:** 8-12 hours
**Files touched:** JournalViewModel (rewrite), new EntryLifecycleService

### Phase 4: Decompose ProcessingEngine (Priority: Medium)

**Goal:** Break processWithCloud() from complexity 22 to 3-4 functions of complexity <8.

**Extract:**
- `extractEntities(from result:, into context:, for entry:)`
- `assignTopics(from result:, in context:, for entry:, objectID:)`
- `checkAlbumSync(for entry:, topics:, mediaIdentifiers:)`
- `storeInference(from result:, in context:, for entry:)`

**Estimated effort:** 6-8 hours
**Files touched:** ProcessingEngine (refactor)

### Phase 5: Decompose Mega-Views (Priority: Low)

**Goal:** Break EntryExpandedView and ComposerView into focused subviews.

**EntryExpandedView splits into:**
- `EntryReadingView` — body, media grid, mentions
- `EntryEditingView` — editable fields, topic management
- `EntryExpandedView` — mode switch + toolbar (thin coordinator)

**ComposerView splits into:**
- `ComposerRecordingRow` — audio recording UI
- `ComposerMediaGrid` — tile grid with add
- `ComposerView` — toolbar + footer (thin coordinator)

**Estimated effort:** 12-16 hours
**Files touched:** EntryExpandedView, ComposerView (split into subfiles)

---

## Governance Rules (Add to CLAUDE.md)

```
### CRAP Score Monitoring
- No function may exceed cyclomatic complexity 15
- No file may exceed 400 lines (views) or 300 lines (services/VMs)
- No catch block may silently print() — all errors must be structured
- No code pattern may be duplicated more than twice — extract on third use
- Nesting depth limit: 3 levels (extract helper on 4th)
```

---

## Timeline

| Phase | Effort | Priority | Dependency |
|-------|--------|----------|-----------|
| 1. Error handling | 4-6h | Immediate | None |
| 2. DRY utilities | 4-6h | High | None |
| 3. Split JournalViewModel | 8-12h | High | Phase 2 |
| 4. Decompose ProcessingEngine | 6-8h | Medium | Phase 2 |
| 5. Decompose views | 12-16h | Low | Phase 3 |
| **Total** | **34-48h** | | |

---

_Audit methodology: Manual cyclomatic complexity analysis per CLAUDE.md
governance thresholds (Clean <5, Acceptable 5-15, Smelly 15-30, Critical >30).
No automated coverage data available — complexity is the primary indicator._
