# EVAL-001 — Binder-to-Mockup Alignment Evaluation

| | |
|---|---|
| **Status** | Active |
| **Date** | 2026-04-14 |
| **Evaluator** | Operator + AI |
| **Binder** | MSA-001-binder (7) |
| **Design Artifact** | memorystream.png |
| **Scope** | All WPs, WSs, TA-001, and data models in MSA-001 |

---

## 1. Purpose

This evaluation compares the MSA-001 binder's planned architecture, work packages, and work statements against the authoritative UI mockup (`memorystream.png`). The mockup was produced after the binder was generated and represents the current design intent for Memory Stream.

Findings are structured as formal gaps requiring binder revision before execution begins.

---

## 2. Design Authority

**`memorystream.png` is the authoritative UI reference for Memory Stream.**

The binder was generated from discovery (PD-001) and implementation planning (IP-001) prior to the mockup's existence. Where the binder and mockup conflict, the mockup governs.

---

## 3. Findings Summary

| ID | Finding | Severity | Affected Artifacts |
|----|---------|----------|--------------------|
| GAP-001 | Topic/category tabs not modeled or planned | High | TA-001, IP-001, WP-027 |
| GAP-002 | User feedback loop (confirm/edit/ignore) missing | High | TA-001, IP-001, WP-026, WP-027 |
| GAP-003 | AI inference summary card not designed | High | TA-001, WP-026, WP-027 |
| GAP-004 | Real-time processing status not exposed in UI | Medium | WS-139, WS-141, WP-025 |
| GAP-005 | Entry card complexity underspecified in WS-139 | High | WS-139 |
| GAP-006 | Unified input surface not designed | Medium | WS-136, WS-137, WP-025 |
| GAP-007 | Siri shortcut as UX/onboarding surface not addressed | Low | WS-140 |
| GAP-008 | Data model missing topic/category and user-feedback entities | High | TA-001 |

---

## 4. Detailed Findings

### GAP-001 — Topic/Category Tabs Not Modeled or Planned

**Mockup shows:** Horizontal tab bar with "All | Garden | Combine | Astro" — inferred topic groupings derived from entry content and extracted entities.

**Binder state:** No data model, component, or work statement addresses topic-level categorization. The `ExtractedEntity.entity_type` enum (`project, person, issue, idea, next_action`) does not produce topic groupings. These are a higher-order inference — a classification of entries into user-meaningful domains.

**Impact:** Without this, the primary navigation and filtering mechanism shown in the mockup cannot be built.

**Required changes:**
- TA-001: Add a `Topic` or `Category` data model (inferred, not user-created) with entry association
- TA-001: Add a component responsible for topic inference (likely part of AI processing)
- IP-001: Scope topic inference into WP-026 or create a new WP
- New WS(s): Topic inference logic, topic-based filtering UI

---

### GAP-002 — User Feedback Loop Missing

**Mockup shows:** An "APP IS INFERRING" card with three action buttons: "Looks right" (confirm), "Edit" (correct), "Ignore" (dismiss). This is the mechanism by which the user validates or corrects AI output.

**Binder state:** No component, data model, or work statement addresses user feedback on AI inferences. Entity extraction is treated as a one-way pipeline: extract, store, display. There is no concept of user confirmation state, correction workflow, or feedback persistence.

**Impact:** Without this, the app cannot build user trust, cannot improve over time, and the core interaction pattern shown in the mockup is missing.

**Required changes:**
- TA-001: Add data model for inference feedback (confirmation state, user corrections, timestamps)
- TA-001: Add a component for feedback handling and persistence
- New WS(s): Feedback UI implementation, feedback data model, feedback-to-entity update logic
- Consider: Whether feedback affects future extraction (learning loop) or is purely confirmational for MVP

---

### GAP-003 — AI Inference Summary Card Not Designed

**Mockup shows:** A natural-language summary card: "Saved immediately from Siri, linked to Bed 4, and flagged as both a plant-health note and a content opportunity." This is distinct from entity tags — it is a human-readable explanation of what the AI concluded.

**Binder state:** The AI processing pipeline (WP-026) produces structured entities with confidence scores. No component generates a natural-language inference summary. No display component renders such a summary.

**Impact:** Without this, the app loses its key differentiator — the feeling that the AI "understood" the entry, not just tagged it.

**Required changes:**
- TA-001: Add an inference summary field to the processing output (either on `ProcessingTask` or a new `InferenceSummary` model)
- WP-026: Extend AI Processing Engine to generate natural-language summaries alongside entity extraction
- WP-027: Add display component for inference summary cards
- New WS(s): Summary generation logic, summary display UI

---

### GAP-004 — Real-Time Processing Status Not Exposed in UI

**Mockup shows:** Status badges on entries: "Parsing now" (active processing), "Confirmed" (user-validated). A "PROCESSING" card shows intermediate state: "Raw note saved. The app is extracting beds, plant condition, and content intent."

**Binder state:** `ProcessingTask.status` exists (pending, processing, completed, failed) but is treated as a backend queue concern. WS-139 (journal display) does not reference processing status. No WS addresses the visual transition from capture to processing to inference to confirmation.

**Impact:** Without this, the user cannot see that the app is working on their entry. The "alive" feeling of the mockup is lost.

**Required changes:**
- WS-139: Revise to include processing status display within entry cards
- TA-001: Define how processing status is surfaced to the UI layer (observation/notification pattern)
- Consider: Whether status updates are push (reactive) or poll-based

---

### GAP-005 — Entry Card Complexity Underspecified in WS-139

**Mockup shows each entry card contains:**
- Entry title (inferred or derived)
- Timestamp + source badge ("Captured via Siri" / "Typed-in app")
- Processing status badge
- Entry content text
- Processing status card (when active)
- Inline entity tags
- Inference summary card (when available)
- User feedback controls

**Binder state:** WS-139 specifies: "UITableView-based entry listing" with "content, input type, and timestamp" in cells. This describes roughly 20% of what the mockup shows.

**Impact:** WS-139 as written would produce a minimal list view that bears no resemblance to the mockup.

**Required changes:**
- WS-139: Rewrite to specify the full entry card structure shown in the mockup
- WS-139: Add dependency on tag rendering (WS-147), processing status (GAP-004), inference summary (GAP-003), and feedback controls (GAP-002)
- Consider: WS-139 may need to be split — basic card structure vs. progressive enrichment as processing completes

---

### GAP-006 — Unified Input Surface Not Designed

**Mockup shows:** A persistent bottom bar with: text field ("Tell me what happened..."), Siri-ready indicator, and "Save entry" button. This is a single input surface that handles both text and voice entry points.

**Binder state:** WS-136 (voice) and WS-137 (text) are designed as separate components with separate controllers. No WS or component describes the unified input bar shown in the mockup.

**Impact:** Building WS-136 and WS-137 as separate controllers would produce two disconnected input mechanisms rather than the cohesive bottom bar shown.

**Required changes:**
- TA-001: Add a unified Input Bar component that composes voice and text input
- WS-136/WS-137: Either merge or add a new WS for the unified input surface that integrates both
- Consider: The "Siri ready" indicator implies real-time Siri availability state — this needs design

---

### GAP-007 — Siri Shortcut as UX Surface Not Addressed

**Mockup shows:** A prominent banner at the top: "SIRI SHORTCUT — Tell Memory Stream that..." with explanatory text: "Capture a thought from your headphones or lock screen. The app saves it now and sorts it out after."

**Binder state:** WS-140 covers Siri integration as a technical backend concern (INExtension, intent handlers). No WS addresses the in-app Siri discoverability/onboarding banner.

**Impact:** Minor — the banner is a UI element that could be added to the journal display WS. But it signals that Siri is a first-class capture method, not just an integration.

**Required changes:**
- WS-139 or new WS: Add Siri shortcut banner as a journal display element
- Consider: Whether the banner is persistent, dismissible, or contextual

---

### GAP-008 — Data Model Gaps

**Mockup implies data models not present in TA-001:**

| Missing Model | Purpose | Evidence in Mockup |
|---------------|---------|-------------------|
| `Topic` / `Category` | Inferred entry groupings | "All \| Garden \| Combine \| Astro" tabs |
| `InferenceFeedback` | User confirmation/correction of AI output | "Looks right" / "Edit" / "Ignore" buttons |
| `InferenceSummary` | Natural-language AI conclusion | "Saved immediately from Siri, linked to Bed 4..." card |

**Additionally, existing models need revision:**

| Model | Change Needed |
|-------|---------------|
| `JournalEntry` | Add optional `title` field (mockup shows "Hands-free capture", "Garden session") |
| `JournalEntry` | Add `source` field or clarify `input_type` to distinguish "Captured via Siri" vs "Typed-in app" |
| `ProcessingTask` | Add `progress_description` for the intermediate status text shown in the PROCESSING card |

---

## 5. Dependency Impact

The gaps are interconnected. Addressing them requires changes that cascade across the binder:

```
GAP-008 (data models)
  --> GAP-001 (topics) --> new WS for topic inference + topic UI
  --> GAP-002 (feedback) --> new WS for feedback UI + persistence
  --> GAP-003 (inference summary) --> new WS for summary generation + display
      --> GAP-004 (processing status in UI) --> WS-139 revision
          --> GAP-005 (entry card complexity) --> WS-139 rewrite
              --> GAP-006 (unified input) --> WS-136/137 revision
```

**Recommended revision order:**
1. Revise TA-001 data models and components first (GAP-008)
2. Revise IP-001 work package scoping
3. Revise or create WSs bottom-up: data models, then processing, then UI

---

## 6. Scope Assessment

This evaluation identifies **8 gaps**, of which **5 are high severity**. The gaps are not minor omissions — they represent core interaction patterns visible in the mockup that have no corresponding plan in the binder. Executing the binder as-is would produce an app whose UI does not match the design intent.

**The binder requires revision before execution is authorized.**

---

*End of Evaluation*
