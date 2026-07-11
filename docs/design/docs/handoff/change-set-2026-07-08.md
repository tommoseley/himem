# HiMem · change set for Claude Code (July 8 2026)

A consolidated, implementable summary of everything decided since the last handoff. Each item says **what changes**, **why** (one line), and the **canonical doc** that holds the full rules. Ordered by architectural weight: schema first (it must be right before ship), then surfaces, then copy.

The four architecture docs are the source of truth; where this summary and a doc disagree, the doc wins:
- `Kingfisher · North Star.md` — philosophy (why)
- `Kingfisher Language.md` — UI wording (how it speaks)
- `HiMem · the shaping model.md` — product flow (how it moves)
- `HiMem · evidence and context.md` — ontology (what it's made of)

---

## 0. Do-first / blocking

1. **Data model: Clip↔Memory becomes many-to-many.** This is the one change that must land before any real user data exists, because migrating a shipped base later would be jarring. See §1. Everything else is additive UI.
2. **AI-attribution color sweep to AI-blue `#1E5C8E`** is still an open cross-cutting PR (organize/summary/suggestion surfaces that shipped ochre/amber). Land it as its own pass before TestFlight. Half-applied color rules are worse than uniformly wrong ones.

---

## 1. Ontology — evidence & context (schema)
*Canonical: `HiMem · evidence and context.md`.*

- **Clip↔Memory is many-to-many.** A clip is referenced by **0–N** memories; a memory references **1–N** clips. The join is an **associative entity**, not a bare link: it carries an optional **annotation** ("why this matters here"), the clip's order/role in that memory, and the association timestamp.
- **Evidence stored once.** Joining a clip to a second memory creates a second edge, never a copy. `MediaReference` rows already survive in the user's private CloudKit DB; media blobs live once in iCloud Files.
- **Three deletion acts, distinct:**
  - *Remove from a memory* = delete one **edge**. Clip and other edges survive. Low-stakes, undo toast.
  - *Delete a memory* = delete the narrative + its edges. **Clips survive** (still linked elsewhere, or return to unplaced).
  - *Delete a clip* = destroy **evidence**. If referenced by memories, warn ("evidence in N memories") → Recently Deleted.
- **Transcript edits are corrections, not reinterpretation.** Editing fixes what the recognizer misheard (fidelity); interpretation lives in the memory/summary/annotation, never by rewriting the words.
- **v1 surface is staged, schema is not.** Ship: multi-placement allowed, "Referenced in" visible, annotation field present. Stage (schema-ready, not built): AI-proposed association, cross-appearance "Find the thread," reflection-over-time, Studio.

---

## 2. Primary objects & navigation
*Canonical: CLAUDE.md · Phone; `HiMem · the shaping model.md`.*

- **Three primary objects: `Clips · Memories · Projects`** (Evidence · Context · Intent), a three-tab segmented control in that left-to-right order (capture→shape→build).
- **Cold launch → Memories.** Last-used tab is remembered **only while the app stays alive**; a cold start always lands on Memories.
- **`Clips` replaces the standalone "Captured Clips" window** as a first-class tab. "Captured Clips" as a surface name is retired (it named an event; the page is about what exists). Remove the Settings→Captured Clips entry (it's a tab now).
- **Capture returns to Clips** (was: Captured Clips).
- **Clips default view:** AI suggestions (Sort clusters) on top + everything not-yet-connected below (incl. clips still downloading from the phone). No architecture word ("unplaced"/"workbench") in chrome. Reveals to **All / Voice / Photos / Notes**.
- **Tap a clip → the clip is the primary object:** transcript · media · date · **"Referenced in: [memories]"** · Projects. This is where multi-placement becomes visible without teaching a word.
- **Arrival banner** ("2 new from Apple Watch · Tap to review") stays pinned atop **Memories** when count > 0 and deep-links into the Clips default view — an offer, never an auto-switch of the landing.

---

## 3. Captured Clips → the Clips workbench behaviors
*Canonical: `Captured Clips · session-first · spec.md`.*

- **Idle-gap sessioning (locked).** Clips less than an idle threshold apart = one session; a longer gap closes it. **Silence is the boundary.** Default threshold **10 min (provisional — tune in dogfood)**. `rollGroupId` (On-a-roll) always overrides. Deterministic (a clock, not a classifier); ships without the intent parser. Grouping runs on the phone post-sync so late clips fold in by timestamp.
- **Day-group headers.** The inbox spans multiple days, so partition the list with **Today / Yesterday / Jun 30** headers (matches Memories list). Cards under a header stay time-only; a floated cluster card carries its date in-meta. Rule: every entry unambiguously dateable at a glance.
- **Sort (AI clustering) — the "process 20 clips without dread" surface.**
  - *Free (on-device):* deterministic clusters — time+place (within ~90 min **AND** ~200m, **location required** or don't time-cluster) and **distinctive** word/entity match (proper noun or low-freq term; reject generic bigrams like "little town"). "Why" strings are templates, not LLM prose.
  - *Plus (Connect):* semantic clusters the deterministic pass can't see, cross-day thematic grouping.
  - **One clip set = one candidate (overlap dedup):** never show the same clips in two cards *within a pass*; a clip lands in at most one proposed cluster. (A clip gaining a *second* memory *later* is legitimate — that's the staged association act, not Sort.)
  - **One ochre commit: "Keep these · N memories."** Sort is the moment, not each cluster. One tap makes each cluster its own draft Memory, batched, **no post-commit sheets**. Loose clips stay on the bench.
  - **Set-aside persistence:** `dismissedClusterFingerprints` on `InboxManifest`, fingerprint = hash of sorted clip-IDs, prune on manifest write, suppress only the exact set (a superset/subset is a new proposal).
- **Card density:** kill the per-card ochre pill; the whole card is the tap target (chevron), transcript is the loudest thing. Ochre returns once, on the commit. Compact rows carry a media-type icon (mic/camera/video/note).

---

## 4. Notifications
*Canonical: CLAUDE.md · Notifications.*

- **Channel B (Inactivity) is RETIRED.** No after-a-quiet-stretch nudge — it's the app raising the skipped thing, which the North Star forbids, and it broke our own "no nudges" promise.
- **One channel only — Captured Clips arrivals, always passive** (`UNNotificationInterruptionLevel.passive`): lands silently, never buzzes/banners/wakes. One pending, updates in place, cleared when inbox cleared. Foreground → badge only.
- **Onboarding notifications page = one toggle** (Captured Clips arrivals, on), then the iOS dialog.
- **Badge meaning is under review** — a live count is defensible as "materials on the bench," not "inbox to zero." Decide after the workbench framing beds in; don't treat it as a settled guilt-counter.

---

## 5. Memory Detail
*Canonical: `Memory Detail · unified editing model.md`, `Memory Detail · long-memory navigation.md`.*

- **Unified editing:** text (title · summary · transcript) = tap to edit in place, ochre **Done** / plain **Cancel**; editing summary never reverts Organized→Draft. Media = tap to consume (audio demoted, transcript is the working object). Every clip with an original recording shows a quiet **Original recording** play affordance — must be present in read *and* edit states (was missing in build).
- **Clip relocation — "Where does this belong?"** From the clip's edit state, a two-row bottom: clip-fate row (**Delete clip** destroy · **Where does this belong?** relocate) above the text commit row (Cancel · Done). Destinations: another memory · new memory · **Remove from this memory** (→ back to Clips, unfiled, survives). Same wording/primitive as workbench placement. Moving in/out marks affected memories **stale → Reorganize**. Moving out the last clip offers to **delete the now-empty memory** (recoverable) — *Keep it empty* is the quiet secondary.
- **Long memories:** any memory with >1 clip shows a **Full / Compact** transcript toggle; size picks the default (>6 clips or >1500 words opens Compact). Compact rows are single-open accordions with full swipe/tap parity and a media-type icon.
- **Reorganize:** rethinks **Title + Summary only** (never Topics/Mentions). Both new values require explicit approval (before/after, defaults to current). Replaces the draft, never branches. Re-enters the same review sheet (chip → "Draft organized").
- **Deletion:** memory delete = full-width red **Delete** at the bottom of the opened memory (no swipe, no confirm — the scroll is the deliberation; Recently Deleted is the net).

---

## 6. AI Organize
*Canonical: `AI Organize · spec.md`.*

- **Free = manual + on-device** (iPhone 15 Pro+/iOS 26, or server fallback), no counter, re-run freely. **Plus = automatic + frontier**, plus the connective work. No assist quotas anywhere (metering model fully retired).
- **Chip is a review-state label, not a tier badge:** unreviewed → **"Draft organized"** ("Give this a glance"); becomes plain **"Organized"** only on accept/edit. On-device draft is never presented as authoritative.
- **Honest Label:** summary contains nothing the clips don't; length matches substance; describe, don't interpret; pronouns allowed (owner = "you", others named/they).
- **Affordance vocabulary (44px floor):** real button = the action (one primary/loudest per moment); solid pill+dot = managed content (topics/mentions); quiet label = status. Dashed = add/incomplete only. Status never dressed as a button; action never a bare text link.

---

## 7. Buttons, actions, color
*Canonical: `HiMem · Buttons & Actions.html`, CLAUDE.md accessibility rules.*

- **Color maps to who acts:** ochre = *you* act (commit/save/keep); AI-blue = invoke *AI* (organize/reorganize/find-the-thread/run/review-a-draft); red = destruction.
- **AI buttons name the AI:** verb + **trailing** sparkle — `Organize with AI ✦`, `Reorganize with AI ✦`, `Find the thread ✦`. Sparkle dropped from ochre user buttons. Never label an AI re-run "Regenerate"; each AI surface owns one named action (memory = *Reorganize*, project = *Find the thread* / *Find the thread again*).
- **Deletion = full-width Delete at the bottom of an opened item** (red, ≥50px), below all content, no confirm. **Swipe-to-delete retired everywhere.** Trash = deletes the object; Recycle/Remove-from-project = parallel full-width button that unlinks (object survives).
- **Toggle on-state is ochre**, never iOS green (green is semantic success only).

---

## 8. Copy — Kingfisher Language sweep
*Canonical: `Kingfisher Language.md`.*

- **Ask the user's question, not the operation.** Banned verbs in user copy: **Make, Create** (except literal conscious creation), **Organize, Manage, Process, Assign**. Governs verbs/questions, not nouns ("Memory," "Clip," "Project" stay).
- **"Make a Memory" is retired.** Loose clip → **"Where does this belong?"** (placement); recognized session → **"Create one memory"**; Sort batch → **"Keep these · N memories"**; AI cluster affordance → **"Review"** (observed, not concluded).
- **Learn, not Help** — the ? hub is titled **Learn**.
- **Projects are continuity, not containers** — "Building something over weeks or months? That's what Projects are for," never "Projects organize your memories."

---

## 9. Projects
*Canonical: `Projects · MVP spec.md`.*

- **Free builds up to 3 projects by hand; Project Assist ("Find the thread") is Plus** (the Connect layer). Topic⟷Project and Memory×Project are both many-to-many.
- **Removing a memory from a project:** open the member memory, bottom full-width **Remove from project** (Recycle glyph, memory survives, undo toast). No swipe. Member cards follow the standard Memory-card pattern (same as the Memories list).

---

## 10. Onboarding, tutorials, Siri
*Canonical: onboarding wizard screens; `Tutorials · triggers spec.md`.*

- **Onboarding wizard** (replaces old onboarding): Sign in with Apple → Mic → Speech (these three required) → Photos → Camera → Location → Notifications(one toggle). Denied optional perms show a calm "turn it on later in Settings," continue. Name defaults from Apple auth. No starter Topics.
- **Reinstall** → Apple re-auth then a restore screen ("Bringing your memories back from iCloud"), not the permission wizard again.
- **Two teaching formats:** full-pager (what a page *is*) and anchored coachmark (what controls *do*). **Auto-run is per-product, not doctrine.** HiMem: empty-home hand-off + "Show me around" chip; the screen tour lives under **Learn**.
- **Tutorials (each auto-fires once, replayable under ?):** capture · organizing · find-the-thread (fires on a project with ≥3 memories) · Captured Clips/Watch story · Watch discovery (`WCSession.isPaired`, app-level, with a manual-add fallback if the CTA fails) · **Capturing with Siri** (fires once on Today after `memoryCount ≥ 3`).

---

## 11. Storage / data custody
*Canonical: CLAUDE.md · Data custody; `docs/architecture/foundation-models-spike-findings.md`.*

- **All HiMem media (voice/photo/video) lives in the user's iCloud Files** (public-document-scope ubiquity container), not the app sandbox — survives uninstall/reinstall, available cross-device (iPad Studio). Structured data (memories/transcripts/topics/edges/projects) in the user's **private CloudKit DB**. On-device Core Data is a rebuildable index only. **No user content in HiMem's custody.**
- **User-mutable files accepted:** if the user deletes media from Files.app, the clip shows a calm "This recording was moved or deleted"; transcript + everything derived survives.
- **Migration caveat:** audio in today's `Documents/VoiceEntries/` is sandbox-bound until the ubiquity migration runs on that device.
- **Storage doc reconciliation:** `docs/design/Storage architecture · CLAUDE.md` "v2 = files-as-source-of-truth" must be demoted from "locked" to "candidate, portability-not-privacy" — Option A (private DB + iCloud Files) is the single locked answer.

---

## What is NOT in this change set (deliberately staged)

- Creator cross-reference surface (AI-proposed association, cross-appearance Find-the-thread, reflection-over-time) — schema-ready, not built.
- Studio (iPad).
- In-context capture (project/artifact "remember this"), "hold a block open" explicit sessioning — post-v1 candidates.
- Final chrome name for the Clips default view beyond "Clips" (the workbench-as-state is settled; media/segment sub-labels can dogfood).
