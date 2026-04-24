# Hi Mem + Hi Mem Studio — Architectural Direction

_Established 2026-04-24_

---

## Product Model

```
Hi Mem (iPhone / Watch)          Hi Mem Studio (iPad / Web)
─────────────────────────        ─────────────────────────────
Capture companion                Workbench / creation space
Session-based composition        Cross-entry synthesis
Siri / voice / camera / text     Projects, Drafts, Transformations
"I saved that in Hi Mem"         "I'm building it out in Studio"
```

**Hi Mem captures your life. Hi Mem Studio helps you shape it.**

---

## Core Language

| Term | Definition | Used Where |
|------|-----------|------------|
| **Memory** | The atomic unit. Voice, text, photo, video — composed together. | Everywhere |
| **Project** | Container for intentional work. Pulls in multiple memories. | Studio |
| **Source** | A memory referenced inside a project. Internal concept. | Studio (internal) |
| **Draft** | What you're building — script, post, outline, summary. | Studio |
| **Action** | A transformation button: Summarize, Extract steps, Generate post. | Studio |
| **Topic** | User-authored workspace/category (Garden, Work, etc.) | Both |
| **Mention** | AI-extracted entity tag. Search-only, not displayed on cards. | Both |

**Avoid:** Document, Note, File — these pull into commodity territory.

---

## What Hi Mem Has (Complete)

The capture layer is built and functional:

- Session-based Composer with multi-media composition
- Siri transactional capture
- AI processing pipeline (Claude Haiku via EC2 proxy)
- Crucible design system (warm palette, 16-hue topics, status chips)
- In-place entry expansion with reading/editing modes
- Topic system with user-selectable colors and AI suggestions
- Media tile grid (3×3, corner folds, tap-to-view, ×-to-remove)
- Recently Deleted with ghost UI and 30-day retention
- Photo album sync per topic
- Smart tag filtering, density modes, date grouping

---

## What's Missing for Studio

### 1. CloudKit Sync (Required)

**Purpose:** Share the Core Data model across iPhone, iPad, and (optionally) web.

**Approach:** Replace `NSPersistentContainer` with `NSPersistentCloudKitContainer`.

- iPhone ↔ iPad sync is nearly a drop-in swap
- Existing Core Data model travels as-is
- Media strategy: sync thumbnail JPEGs via CloudKit; full-res stays on-device
- Watch: CloudKit with paired WatchKit extension

**Auth for iPad: NOT required.** iCloud identity handles it automatically.
`NSPersistentCloudKitContainer` authenticates via the user's Apple ID — no
login screen, no auth tokens, no user management. Both iPhone and iPad
share the same iCloud container. This is the same model Apple Notes,
Reminders, and Photos use.

**Auth for Web: REQUIRED.** CloudKit JS or a custom API layer needs
authentication. Options:
- CloudKit JS with Apple ID sign-in (web → iCloud directly)
- Custom API on EC2 with Sign in with Apple (server-mediated)
- Custom API with its own auth (most flexible, most work)

**Bottom line:** iPad is free (iCloud). Web costs auth work.

### 2. New Core Data Entities (Studio)

```
Project
├── id: UUID
├── name: String
├── createdAt: Date
├── updatedAt: Date
└── sources: [Memory]  (many-to-many with JournalEntry)

Draft
├── id: UUID
├── projectId: UUID
├── title: String
├── content: String     (the generated/edited output)
├── draftType: String   (summary, outline, post, action_list)
├── createdAt: Date
├── updatedAt: Date
└── project: Project
```

These are additive — no migration impact on existing Hi Mem data.

### 3. Transformation Actions (Server)

New API endpoints on the EC2 proxy:

```
POST /himem/transform
{
  "memories": ["text of memory 1", "text of memory 2", ...],
  "action": "summarize | outline | extract_actions | generate_post",
  "context": "optional topic or project name"
}
→ { "result": "structured output text" }
```

Uses Claude (Sonnet for quality, Haiku for speed) with action-specific prompts.

### 4. iPad Layout (Studio Surface)

- Split view: memory browser (left) + editing canvas (right)
- Project list in sidebar
- Drag memories into projects
- Draft editor with rich text
- Transformation action buttons in the toolbar
- ⌘↵ to commit, ⌘1-9 for topic switching

### 5. Bridge Feature (Lives in Hi Mem Today)

The smallest possible Studio action, buildable without CloudKit or iPad:

**"Make something from this"** button in the expanded entry view.

Menu options:
- Summarize
- Create outline
- Extract action items
- Generate post draft

Calls `/himem/transform` with the entry content. Returns structured text
the user can copy, share, or (later) send to a Studio project.

This proves the output loop without building Studio itself.

---

## Implementation Sequence

```
Phase 1: Bridge feature ("Make something from this")
         → lives in Hi Mem, no new infrastructure
         → proves the transformation value proposition

Phase 2: CloudKit sync (NSPersistentCloudKitContainer)
         → iPhone ↔ iPad sync, no auth needed
         → Hi Mem runs as universal app on iPad immediately

Phase 3: Studio iPad layout
         → split view, project/draft entities, drag-to-project
         → transformation actions in toolbar

Phase 4: Web (if/when needed)
         → auth layer (Sign in with Apple or custom)
         → CloudKit JS or custom API
         → thumbnail-only media (full-res stays on-device)

Phase 5: Watch
         → CloudKit companion, Siri complication
         → capture-only (no Studio on Watch)
```

---

## Auth Decision Matrix

| Platform | Auth Needed? | Mechanism | Effort |
|----------|-------------|-----------|--------|
| iPhone | No | Already running | Done |
| iPad | **No** | iCloud via CloudKit | Low — container swap |
| Watch | **No** | Paired via iPhone | Medium |
| Web | **Yes** | Sign in with Apple or custom | High |

**Recommendation:** Ship iPhone + iPad first (zero auth work).
Web is a separate decision with separate infrastructure.

---

## Design System Note

Crucible already defines adaptive layouts:
- **Portrait (iPhone/iPad):** scrollable topic chip row
- **Landscape (iPad/Web):** persistent sidebar with sub-topics, ⌘1-9 shortcuts

The topic palette, status chips, media tiles, and Composer all travel
to iPad unchanged. Studio-specific components (project list, draft editor,
transformation toolbar) extend Crucible, not replace it.

---

## Risk: The Warehouse Trap

> "Users capture a lot, system organizes it beautifully, then they stop
> coming back. Not because it's bad — because it doesn't do anything
> for them later."

The bridge feature ("Make something from this") is the minimum viable
answer. Ship it before CloudKit. If users don't use it, Studio isn't
the right next step. If they do, the path to iPad is clear.
