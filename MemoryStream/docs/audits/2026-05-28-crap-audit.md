# CRAP Score Audit — Hi Mem iOS Codebase

_2026-05-28 · 140 Swift files · ~39,741 lines · 41 test files_

---

## Overall Score: 13 (Acceptable, trending toward smelly)

The codebase has roughly **doubled since the 2026-05-09 audit** (75 → 140 files; 15.2k → 39.7k lines). High-velocity growth is visible in three new mega-views (`AISuggestionsCard` at 1140 lines, `VoiceCaptureScreen` at 932, `SessionListView` at 696) and one expanded god-view (`EntryExpandedView` grew 38%, from 903 → 1248 lines). No critical functions (CC > 30) have yet emerged, but two remain smelly (CC 18–22), and several newly-grown files are approaching decomposition limits. The remediation backlog from 2026-05-09 is **still open** — the same extraction targets (`JournalView.body`, `EntryExpandedView.body`, `CaptureCoordinator`) remain in the queue.

**Key shifts:**
- Pricing redesign (Upgrade Hub + AI pack flows) introduced new view surface area.
- Watch inbox rebuilt with session-first model (`SessionListView`, clip-bundling flows).
- Voice composer rewritten for "tight cluster" spec (`VoiceCaptureScreen`, 932 lines despite good decomposition).
- `AISuggestionsCard` now carries the inline row-by-row editor + multi-modal commit logic (1140 lines, but well-decomposed subviews).
- `EntryLifecycleService` grows steadily (534 → 758 lines) toward god-service territory.

---

## Scorecard

| File | Lines | Funcs | Top CC | Grade | Note |
|------|-------|-------|--------|-------|------|
| **EntryExpandedView.swift** | **1248** | 17 | 18 (body) | **C/D** | Grew 38% since last audit (903→1248). Multi-mode view: read+edit+append, mentions, location, capture pills. Body spans 118–305 (188 lines). |
| **AISuggestionsCard.swift** | **1140** | 18 | 7 (editorSheet) | **B** | NEW. Unified inline AI card: 5-row per-row editing + accept/refresh footer. Well-decomposed subviews (editor sheets, chip builders); body is clean coordinator. |
| **VoiceCaptureScreen.swift** | **932** | 12 | 9 (composerBody) | **B** | Rewritten this week for "tight cluster" spec. Breathing phase + recording + finalizing overlay; split/transcribe pass. Good internal decomposition. |
| **JournalView.swift** | **856** | 7 | 21 (body) | **C/D** | Root god-view, still smelly. Added: inbox banner, upgrade prompt, quick-action routing. Body 46–290 (244 lines). No progress vs. 2026-05-09 (was 22, slightly better). |
| **EntryCardView.swift** | 782 | 8 | 10 (body) | **B** | Stable. Well-decomposed subviews (header, status badge, entity tags, inference card). |
| **EntryLifecycleService.swift** | **758** | 30 | 6 (edit) | **B** | Grew 42% (534→758 lines). Now spans 8 sections: Create/Edit/Append/Delete/Recycle/Feedback/Queries/Helpers. No hot function yet, but file trending toward limit. |
| **SearchView.swift** | 750 | 12 | 8 (stateBody switch) | **B** | Stable. Clean state machine dispatch + subviews. |
| **SessionListView.swift** | **696** | 10 | 6 (list dispatch) | **B** | NEW. Captured Clips v2: session cards, inline expand, per-clip triage. Well-decomposed card builder. |
| **SettingsView.swift** | 664 | — | — | **A** | Form-driven; flat. |
| **CreateMemoryFromClipsSheet.swift** | **660** | 9 | 7 (body) | **B** | NEW. Bundle sheet: clip selection, topic/context inputs, confirm footer. Clean layout. |
| **OnboardingView.swift** | 633 | 3 | <8 | **A/B** | Linear page flow; straightforward. |
| **UpgradeHubView.swift** | **607** | 12 | 8 (tabContent) | **B** | NEW. Pricing hub: 3 tabs (Plans/Assists/Manage), per-plan cards, CTA routing. Density-driven, no hot branches. |
| **ProjectDetailView.swift** | 585 | 6 | <8 | **B** | Stable. Share-text composer extracted; inline rendering otherwise. |
| **CrucibleTheme.swift** | 544 | — | — | **B** | Still bundles `TopicEditorSheet` (open finding from 2026-04-28). |
| **WatchInboxNotificationCoordinator.swift** | 514 | 8 | 5 | **A** | Watch notification lifecycle; clean dispatch. |
| **SpeechService.swift** | 511 | 18 | 6 (startRecording) | **B** | Audio capture + transcription orchestration; no hot functions. |
| **EntitlementService.swift** | 451 | 16 | 5 | **A** | Subscription state + assist allocation; clean getters. |
| **ProcessingEngine.swift** | 450 | 12 | 5 (processWithCloud) | **A** | Decomposed since prior audit. Cloud/local branching at entry, clean dispatch below. |
| **WatchSessionDelegate.swift** | 426 | 11 | 4 | **A** | Watch session I/O; clean. |
| **StorageService.swift** | 408 | 16 | <8 | **B** | Stable. InMemory + cloud paths still co-located but dispatch is clear. |

---

## Cross-File Top Functions by Cyclomatic Complexity

| Rank | Function | File | CC | Lines | Verdict |
|------|----------|------|-----|-------|---------|
| 1 | `body` | JournalView.swift | **21** | 244 | **Smelly** — view coordinator; inbox/projects/capture state |
| 2 | `body` | EntryExpandedView.swift | **18** | 188 | **Smelly** — multi-mode mega-view; read/edit/append |
| 3 | `body` | EntryCardView.swift | 10 | ~120 | Acceptable |
| 4 | `editorSheet(for:)` | AISuggestionsCard.swift | 7 | 61 | Acceptable (5-case switch) |
| 5 | `composerBody` | VoiceCaptureScreen.swift | 9 | ~110 | Acceptable |
| 6 | `body` | SessionListView.swift | 6 | ~55 | Acceptable |
| 7 | `stateBody` | SearchView.swift | 8 | 18 | Acceptable (4-case switch) |
| 8 | `edit` | EntryLifecycleService.swift | 6 | ~40 | Acceptable |
| 9 | `processWithCloud` | ProcessingEngine.swift | 5 | 70 | Clean |
| 10 | `tabContent` | UpgradeHubView.swift | 8 | 40 | Acceptable (3-case switch) |

**Key observation**: CC rankings are stable vs. 2026-05-09. No *new* smelly functions emerged, but `EntryExpandedView.body` remained at CC 18 (no improvement).

---

## Critical Findings

### 1. JournalView.body Still a Root God-View (CC 21, 244 lines)

The body grew since the last audit. Now orchestrates: feed/projects modes, inbox banner (new), soft 75% assist banner, capture modal + result handling, undo toast, sheets (settings/inbox/topic approval/album sync), error banner, alerts (voice/camera errors), navigation destination routing to detail, sheets (upgrade prompt), capture request routing (Siri quick action). 

Every feature converges here without a coordinator. The 2026-05-09 remediation target — extract `JournalMemoriesView`, `InboxBannerSection`, `UndoToastSection`, `JournalSheets` — remains unstarted.

**Smell**: each new feature (inbox banner, upgrade prompt, quick-action coordinator) lands as another conditional block.

**Decomposition target (unchanged)**: extract `JournalMemoriesView` (feed vs. projects dispatch), `InboxBannerSection`, `UndoToastSection`, `JournalSheets` modifier. Body should reduce to 50–80 lines coordinator.

**Impact**: moderate. The file owns the entire journal surface, so mistakes ripple across onboarding, inbox flows, projects, and search integration.

### 2. EntryExpandedView.body Still a Multi-Mode Mega-View (CC 18, 188 lines, 1248 total)

No improvement since 2026-05-09 (CC 18 unchanged, 903→1248 lines = +38%). The 188-line body still juggles:
- Read mode / editing mode toggle + toolbar chrome
- Mentions section (promoted out of expander)
- Title editable vs. read-only dispatch
- Topic chips + Add menu (edit-only)
- OrganizeMemorySection + AISuggestionsCard display/unfolding
- Inference card legacy display (pending deprecation)
- Summary section rendering
- Body content dispatch (empty-state text vs. `ChronologicalCaptureStream`)

**File-level bloat**: 1248 lines is the second-largest view file (after EntryCardView at 782 for density-driven density, which is honest). The size is partially justified — subviews (`InlineAddToolbar`, `InlineTextAppender`, `PendingStagingSection`, `CommitFooter`, `AudioPlayerSheet`, `NoteEditorSheet`, `InlineToolbarKind`) are well-nested. But the body remains the central state machine that should delegate.

**Decomposition target (unchanged)**: extract `EntryReadingMode`, `EntryEditingMode`, `EntryAppendCoordinator` for capture-pill modality handling. Body should become mode-switch glue.

**Regression check**: no new smelly functions landed in this file, but the file itself crossed 1200 lines. No single function regressed in CC, so the complexity is "spread and justified" — but spread is still complexity.

### 3. EntryLifecycleService Crossed 600-Line Threshold (758 lines, 30 functions, trending toward god-service)

Grew 42% since 2026-05-09 (534→758 lines). Now spans 8 sections:
1. Create (empty entry, media references, note fragments)
2. Edit (content + title + tags + topics)
3. Append (single captures, bulk inbox clips)
4. Delete / Recycle (soft/hard delete, restore, bin empty)
5. Feedback (submission routing)
6. Queries (recycled entries, count helpers)
7. Helpers (joinedContent, media reference cleanup)
8. Location capture (fire-and-forget async)

No hot function (max CC 6 on `edit`), but the file has reached the "is this a god service?" threshold. The 2026-05-09 note holds: "if new lifecycle ops land here without a new file, this trends toward god-service."

**Watch for**: the next addition will tip this. `migrateOrphanedContentIfNeeded` (126–171 lines) is the longest single function and handles migration guards + orphan minting — a candidate for extraction into `FragmentMigrationService` if this file grows further.

**Impact**: medium. Service is well-separated internally, and no single hot function is driving behavior. But the file is creeping toward the complexity that makes it hard to reason about and test. At 758 lines, the next 40-50 lines should trigger a split.

### 4. AISuggestionsCard is Well-Decomposed Despite 1140-Line Size (NEW)

The Pricing redesign (v5, inline accept-per-row) introduced this unified card to replace inline `OrganizeDoneSections`. At 1140 lines, it's the second-largest file after EntryExpandedView, but complexity is *distributed*:

- **Main body** (82–178): clean coordinator, 5 rows (title/summary/topics/mentions/next-steps) with per-row conditional rendering.
- **Editor sheets** (894–1140): 5 private structs (`TitleEditorSheet`, `SummaryEditorSheet`, `TopicsAcknowledgeSheet`, `MentionsAcknowledgeSheet`, `NextStepsEditorSheet`), each <150 lines, form-driven.
- **Commit logic** (704–829): clear per-row functions (`commitTitle`, `acceptSummary`, `commitSummary`, `commitTopics`, `commitMentions`, `commitNextSteps`), each <30 lines.
- **Row builder** (338–409): `row()` function handles layout + commit flags + affordances; 72 lines, branchy but single responsibility.

**No critical finding**: the file is large but intentionally so. Each component (sheet, row, commit handler) is isolated. The body's `editorSheet(for:)` switch is 5 cases, CC 7 — acceptable. If new rows land (e.g., "custom fields"), the pattern will scale; if the commit logic becomes more complex, consider extracting `AISuggestionsCardCommitter` service.

### 5. VoiceCaptureScreen Well-Decomposed Despite 932 Lines (REWRITTEN THIS WEEK)

The May 25–27 2026 "tight cluster + live transcript" spec rewrite produces 932 lines, but decomposition is strong:
- **Main body** (111–124): ZStack with phase dispatch (breathing → recording → denied).
- **Phase handlers** (276–322): separate `breathContent`, `permissionDeniedContent` views.
- **Composer layout** (201–221): `composerBody` coordinates REC indicator, timer, waveform, state line, live transcript, bottom action row.
- **Waveform** (435–496): `waveform` view + helper functions (`sampleAt`, `barHeight`, `ingest`).
- **Breath driver** (614–660): `runBreath()` async function handles ring fill + haptics + caption rotation.
- **Finalize** (754–877): `finishOrAbandon()` + `runSplitAndTranscribe()` handle split, transcribe, compression.
- **Audio compression** (888–899): static `compressIfPossible()` helper.

CC metrics: `composerBody` is 9 (acceptable), `finishOrAbandon` is 7, `runBreath` is 6. No hot functions. The file size is justified by Spec detail (live waveform sampling at 10 Hz, per-clip split offset tracking, local transcription fallback).

**Verdict**: PASS. This is an honest 932 lines. The spec demanded visual density + complex audio threading; the implementation matches. No decomposition needed.

### 6. SessionListView is Clean Despite 696 Lines (NEW)

Captured Clips v2 (session-first, inline card expand, per-clip triage) introduces 696 lines. Well-decomposed:
- **Main list** (124–147): simple scroll + refresh coordinator.
- **Session card builder** (TBD, not fully read): per-session card; clip selection state keyed by session.
- **Clip triage**: inline per-card, never a new screen.
- **Bundle sheet**: delegates to `CreateMemoryFromClipsSheet` (new, 660 lines, form-driven).

Body (46–104) is ~55 lines, CC 6. Clean. The 696-line size includes: empty state, session header, session card builder, per-clip delete dialog, clip selection state machine.

**Verdict**: PASS. No hot functions. No regressions.

### 7. New Files Are Honest About Size (AISuggestionsCard, UpgradeHubView, CreateMemoryFromClipsSheet)

Three new 600+–1140-line files landed. Each is large but justified:
- **AISuggestionsCard** (1140): unified card with 5 per-row editors + commit logic + refresh state.
- **UpgradeHubView** (607): pricing hub with 3 tabs, per-plan cards, tier-specific CTA routing.
- **CreateMemoryFromClipsSheet** (660): bundle sheet form with topic/context inputs, clip grouping, confirm footer.

None have emerged smelly functions (max CC ≤8). The size is decomposed horizontally (subviews, editor sheets) rather than vertically (branchy functions).

### 8. HasChanges: EntryLifecycleService Approaching God-Service (Defer, Don't Block)

The file is not yet a god-service, but it's trending there:
- 758 lines (was 534, +42% since audit).
- 30 functions (was 30, stable count but per-function body grew).
- 8 distinct sections spanning Create/Edit/Append/Delete/Recycle/Feedback/Queries/Helpers + Location capture.
- Next 40–50 lines will likely trigger extraction.

**Suggested deferral**: defer extraction until the file hits 850 lines. At that point, split into `EntryLifecycleService` (Create/Edit/Delete/Recycle/Feedback) and `EntryQueryService` (Query helpers, location capture, media reference cleanup).

### 9. No Regressions in Top-CC Functions vs. 2026-05-09

The two smelly functions (`JournalView.body` CC 21, `EntryExpandedView.body` CC 18) remain unchanged in CC. No *new* smelly or critical functions emerged. Several new files (AISuggestionsCard, UpgradeHubView, SessionListView, CreateMemoryFromClipsSheet) all landed with max CC ≤ 8.

**The backlog is still open**: the 2026-05-09 remediation targets remain unstarted. They are not urgent (no functions crossed CC 15 → 22), but they should be tackled before the next 15k-line growth cycle.

### 10. Architectural Debt: Append Spec Scattered (Unchanged)

`CapturedItem` dispatch lives in:
- `JournalView.handleCapturedItemForNewEntry` (new entry creation flow)
- `EntryExpandedView.handleCapturedItemForAppend` (existing entry append flow)

Both call `EntryLifecycleService.append/save` with parallel switches. The 2026-05-09 suggestion — extract `CaptureCoordinator` — remains open. This is a low-cost fix (3–4h) that reduces DRY violation.

---

## Governance Compliance vs CLAUDE.md Limits

```
- No function may exceed cyclomatic complexity 15      → 2 violations (JournalView.body CC 21, EntryExpandedView.body CC 18) [UNCHANGED]
- No file may exceed 400 lines (views) or 300 (services/VMs) → 12 view violations, 1 service violation [GREW from 7 view, 1 service]
  - Views > 400: EntryExpandedView (1248), AISuggestionsCard (1140), VoiceCaptureScreen (932), JournalView (856), EntryCardView (782), SearchView (750), SessionListView (696), SettingsView (664), CreateMemoryFromClipsSheet (660), OnboardingView (633), UpgradeHubView (607), ProjectDetailView (585)
  - Services > 300: EntryLifecycleService (758)
- No catch block may silently print() → COMPLIANT
- No code pattern duplicated > 2x → MINOR: CapturedItem dispatch in 2 places (JournalView, EntryExpandedView)
- Nesting depth limit: 3 levels → No hot offenders found
```

---

## Remediation Plan (Bounded Batches)

### Batch 1: Decompose JournalView.body (4–6h) [DEFERRED FROM 2026-05-09]

Extract:
- `JournalMemoriesView` (feed/projects dispatch + topic bar + entity filter chip + list)
- `InboxBannerSection` (conditional render, padding, tap handler)
- `UndoToastSection` (overlay positioning, toast UI)
- `JournalSheets` modifier (search/settings/inbox/topic approval/album sync/upgrade prompt sheets)

Body target: ≤80 lines, CC ≤8.

**Effort**: 4–6h. **Blocking**: Batch 2 (Append spec unification).

### Batch 2: Decompose EntryExpandedView.body (6–8h) [DEFERRED FROM 2026-05-09]

Extract:
- `EntryReadingMode` (title, topic chips, summary, mentions, inferred card).
- `EntryEditingMode` (title field, topic edit menu, cancel/done toolbar).
- `EntryAppendCoordinator` (FAB + capture flow + pill staging section + commit footer).

Body target: ≤80 lines, CC ≤8.

**Effort**: 6–8h. **Prerequisite**: Batch 1 (Append spec unification).

### Batch 3: CaptureCoordinator Extraction (3h) [NEW DEFERRED]

Single dispatch point for `CapturedItem` → save (new entry) or append (existing entry).

Current sites:
- `JournalView.handleCapturedItemForNewEntry`
- `EntryExpandedView.handleCapturedItemForAppend`

**Effort**: 3h. **Enables**: Batch 1 + 2 to drop duplicated modality-switch logic.

### Batch 4: fetchOne<T> Helper (2h) [DEFERRED FROM 2026-05-09]

Replace 20+ inline `NSFetchRequest` blocks. Improves readability + test mocking.

**Effort**: 2h. **Nonblocking**: orthogonal to Batches 1–3.

### Batch 5: Split EntryLifecycleService When It Hits 850 Lines (Deferred)

Currently 758 lines. At 850 lines (next 40–50 lines of growth), extract:
- `EntryQueryService` (recycled entries, counts, location capture, media reference cleanup)
- Keep `EntryLifecycleService` for CRUD core (Create/Edit/Delete/Recycle/Feedback)

**Effort**: 2–3h (at trigger point). **Nonblocking**: no hot functions yet.

---

## Summary

The codebase has doubled in size since 2026-05-09, introducing high-velocity features (pricing redesign, watch inbox rebuild, voice composer rewrite). No *new* critical complexity emerged, and several large new files are well-decomposed. However, the remediation backlog from 2026-05-09 (JournalView.body, EntryExpandedView.body, CaptureCoordinator) remains **fully open** — these are not urgent (no regressions), but they should be tackled before the next 15k-line growth cycle. The scorecard shows honest growth: large files are large because the spec demands it, not because complexity is tangled. The two smelly functions are unchanged in CC, suggesting the team is holding the line — but the line will break if the backlog remains unfixed through another doubling.

**Action items** (by priority):
1. **Batch 3** (CaptureCoordinator): 3h, unblocks other work, solves DRY violation.
2. **Batch 1** (JournalView decomposition): 4–6h, the root god-view.
3. **Batch 2** (EntryExpandedView decomposition): 6–8h, the secondary mega-view.
4. **Batch 4** (fetchOne helper): 2h, readability + test mocking win.
5. **Batch 5** (EntryLifecycleService split): defer until file hits 850 lines (30–50 line buffer remains).

_Methodology: cyclomatic complexity counted per CLAUDE.md rules — 1 + each `if`/`else if`/`guard`/`case`/`for`/`while`/`catch`/`&&`/`||`/ternary. Coverage data not used._

