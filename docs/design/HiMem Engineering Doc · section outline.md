# HiMem Engineering Design Doc — section outline (for CC to fill)

> **Purpose:** the skeleton for the comprehensive as-built engineering doc. CC fills each section from the **actual codebase** (source of truth for implementation); the design-intent sections **reference** the existing specs rather than re-deriving them. Where code and spec disagree, record it in § 13 (Divergences) — those are the highest-value findings, not something to smooth over.
>
> **Two-layer rule:** *as-built* facts come from the repo; *intent* comes from `CLAUDE.md`, `HiMem · Locked Decisions.html`, `Kingfisher · North Star.md`, `Kingfisher Language.md`, and the per-surface specs. Cite the spec, don't paraphrase it into a new source of truth.
>
> **Scope:** documentation only, no code changes. Commit to the repo's architecture-doc location.

---

## 0 · Preamble
- One-paragraph what-HiMem-is (capture → shape → build; Clips · Memories · Projects).
- Doc status, date, commit SHA it describes, and the reader it's for (a new engineer / handoff).
- Pointer to the design-authority docs as the intent layer.

## 1 · Product architecture (intent layer — reference, don't re-derive)
- Ontology: Clip = evidence, Memory = context, Project = intent; all many-to-many. (cite `HiMem · evidence and context.md`.)
- First principles that bind engineering: perishability, capture-once-connect-many, no-user-content-in-custody. (cite North Star / CLAUDE.md.)
- The three surfaces + navigation model (Clips · Memories · Projects; cold-launch = Memories).

## 2 · System topology
- Targets/modules: iPhone app, Watch app, shared framework(s), test targets. What each owns.
- Third-party/system dependencies (CloudKit, Foundation Models, AVFoundation, WatchConnectivity, StoreKit).
- Build/scheme layout; anything a new dev needs to build both apps.

## 3 · Data model (as-built — the core of the doc)
- Every Core Data entity: fields, types, optionality, relationships **with delete rules** (Cascade/Nullify), and which are CloudKit-synced.
  - At minimum: `JournalEntry` (Memory), `MediaReference` (clip), `MemoryClipEdge`, `Project`, `Topic`, `Mention`, `ProcessingTask`, `OrganizePass`, plus the `InboxManifest`/`InboxClip` manifest structs.
- The derived/rebuildable local index vs. authoritative iCloud data — what's cache, what's truth.
- Per-device fields (not synced): `reviewed`, `InboxClip.recycledAt`, bench review store — call these out explicitly (they're deliberate exceptions).
- Diagram: entity-relationship.

## 4 · Storage & custody architecture
- CloudKit **private DB** = structured data (developer-unreadable, per-Apple-ID). iCloud **Files** container = media blobs. On-device Core Data = derived cache.
- Reference integrity between the two iCloud stores; user-mutable-files consequences (missing-file calm state).
- Media lifecycle: capture → iCloud Files → download-on-demand/eviction; survives uninstall/reinstall (ubiquity public-document-scope).
- (cite `CLAUDE.md` § Data custody; flag any code that still writes to the app sandbox / Photos library.)

## 5 · Capture pipeline
- Phone capture paths: direct voice composer, append composer, Clips-FAB ad-hoc, notes, photo/video, "on a roll."
- Watch capture: audio-only, queue, wrist-off auto-save, 5-min/50-clip caps.
- `sourceDevice` tagging across paths (and where it's still unthreaded).

## 6 · Watch ↔ phone transfer pipeline
- WatchConnectivity transport; durable-wake kick; the transcode (mono/16k/AAC, whole-file post-stop); `.default` capture-mode gain fix.
- Manifest/ack protocol; redelivery gating; the known ack-storm (§4c) status.

## 7 · The consolidation & organize pipeline
- Bench (loose clips) → session grouping (time+place) → memory; the Sort/cluster-editor path.
- Organize pass: on-device (Foundation Models, iPhone 15 Pro+/iOS 26) vs frontier (Anthropic) fork; the prompt composition (core + palette); Honest-Label; Draft-organized → Organized lifecycle; reorganize.
- `ProcessingEngine`/`EntryLifecycleService` roles; the synthesized-note guard + `[TranscriptWipe]` arbiter (what it asserts, where it's wired).

## 8 · The unified clip model
- `ClipDisplayModel`, `ClipAtomView` (registers: operational / reflective / reflectiveCompact), `ClipEditor`, `ClipEditorModal`, `ClipCollection`. (cite `Clip model · spec.md`.)
- The single-edit-surface invariant (synchronous seed + `ClipEditorCommitDecision`) — the data-loss class it closes.

## 9 · Editing, associations & deletion
- Unified managed-chip model (topics · mentions · projects): read=navigate, one Edit sheet, delete-from-library. (cite `AI Organize · spec.md` § managed-chip.)
- Deletion: full-width Delete, no-confirm (except projects), Trash vocabulary; the last-reference rule (memory delete → unique clips to Recently Deleted); clip-level Recently Deleted (both backings, per-device + `MediaReference.recycledAt`).

## 10 · Subscriptions & tiers
- Capture (Free) · Connect (Plus) · Create (Studio, post-launch). What's gated (intelligence, not counts); no assist quotas.
- StoreKit integration, entitlement gate, restore, paywall routing (Free→Pricing). ASC prerequisite state.
- (cite `Pricing model · Capture-Connect-Create.md`.)

## 11 · Notifications
- Channel A only (Captured Clips arrivals, passive, one-pending, in-place update); Channel B retired. Quiet hours; the Clips-tab dot (presence, not count); no app-icon badge.

## 12 · CloudKit schema versioning & deploy state
- Current schema flag version; the field→version history.
- **What's deployed to Production vs staged on Dev.** The open **V8 `recycledAt`** deploy held for Apple's account migration. The deploy ceremony (Dev → verify → Prod-before-TestFlight).

## 13 · Divergences (code vs spec) — highest-value section
- Every place the as-built code disagrees with a locked spec. For each: what the code does, what the spec says, which is likely right, cost to reconcile. (e.g. stale "Loose"→"Unconnected" doc line at `CLAUDE.md:149`; batch-delete copy; any half-applied AI-blue sweep.)
- Do NOT resolve these here — record them for a ruling.

## 14 · Test topology
- Suites, the money-test discipline, `@Suite(.serialized)` for shared-singleton suites, the on-device calibration harness (env-gated), the Core Data model-instance isolation fix, known flakes.

## 15 · Governance & process
- The design-authority model (design decides *what*, CC decides *how*; raise-don't-deviate); the four-part handoff; Bug-First; additive-then-verify-on-device; branch/commit discipline. (cite `AGENTS.md`, `CLAUDE.md` Part 0.)

## 16 · Known carry-forward / deferred
- The current punch list (P7 fast-follows, P8 status, 3/3b cleanups, §4c ack-storm, §4d skip-if-AAC).
- Post-v1 candidates (voice-register picker, AI alternative summaries, project templates — cite `Project Templates · engineering design.md`).

## 17 · Glossary
- Every HiMem term with its precise meaning: clip, memory, project, session, bench, loose/unconnected, reviewed, organize, reorganize, Find the thread, Let Go, on-a-roll, Sort. (cite `Kingfisher Language.md`.)
