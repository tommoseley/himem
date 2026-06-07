# Projects · MVP spec

May 2026. Locked for v1.

## Model

- **Project = name + goal + member memories.** Nothing else in MVP. No cover art, no date range, no archive state, no description beyond the goal field.
- **Topic ⟷ Project is many-to-many.** Topics and projects are orthogonal. A memory has one topic and belongs to **0–N projects**. A project's topic chips are derived from the topics of its member memories — there's no project-level topic field.
- **Memory × Project is many-to-many too.** A single memory can sit in multiple projects. Adding to a new project does *not* remove it from existing ones — they're parallel containers, not exclusive folders. (Matches what `JournalEntry.projects: NSSet?` already allows.)
- **Goal field**: "What are you building toward?" Optional placeholder asks "A video? A post? An idea?" Free-text, short. Shows on the detail screen below the title in serif italics. Not interpreted by AI directly; passed as context.
- **Membership is assigned to memories, not the other way around.** A memory is tagged into a project either at memory-creation (chip in the new-memory sheet) or after the fact (Add memory sheet on project detail).
- **Removing a memory from a project.** **Right-to-left swipe** on a memory row in the project's memory list reveals a red **Remove** action — same convention used elsewhere in the app. Tap removes the memory from this project; the memory itself is untouched. A toast appears at the bottom: *"Removed from [project] · Undo"* with a 5-second timeout. No confirmation modal — the undo toast is the safety net.
  - Memory Detail shows project membership as read-only chips in MVP. To remove a memory from a project, the user goes to the project page and swipes. One canonical management surface.
  - Removing a memory marks the project's existing Project Assist summary stale (amber footer `"Project membership changed · Refresh"`, same handoff to AI Organize spec § 8 as adding). Derived topic chips recompute on read.
- **Derived topics**: compute on read for MVP. If a project ever crosses ~50 memories, introduce `derivedTopicsSnapshot` cached on the project and invalidated on member add/remove. Not urgent now.
- **Naming carryover**: Core Data attribute is still `Project.purpose`; UI label is "goal." These can diverge. If the rename is bundled with the pre-TestFlight schema deploy, rename the attribute too — otherwise leave the attribute alone.

## Surfaces

| Surface | What's there |
|---|---|
| Today header | `Memories ⟷ Projects` segmented control. Right side is Projects. |
| Projects tab | Topic-filter strip (filters by *contains-topic*, not *is-topic*). List of project cards (title, derived topic pips, memory count, last-activity date). Single inline `+ New project` row at the bottom of the list. **No FAB.** |
| New project sheet | Two fields: `name` + `goal`. No topic picker. |
| Project detail | Back-to-Projects + (+ / share / edit) cluster. Serif title. Italic serif goal line. Derived topic chips. Memory count. *Find the thread* affordance (or summary card, if a run exists). Memory list below. |
| Settings → Projects | Top-level row, `N active`. Never buried. (Already shipping.) |

## Project Assist · “Find the thread”

> **Project Assist is the Connect capability — a Plus feature.** It's how projects *grow themselves*: a synthesized summary plus suggested memories that may belong. Free builds projects **by hand** (create, add/remove, title, goal, browse, search-within); Plus is what reaches across the library to grow them. Whether Free gets a one-time *taste* of Find the thread is a trial decision in `Pricing model · Capture-Connect-Create.md`, not a metered “starter assist.”

The single AI action on a project. **One pass produces two outputs.**

**Naming.**

- Feature / spec name: **Project Assist**.
- Button label: **Find the thread**.
- Outputs: a **project summary** and a list of **suggested memories**.
- “Coalesce” was the working internal name; dropped. One vocabulary.

### What it produces

**Output 1 — Project summary.**
A single Honest-Label paragraph, 2–4 sentences, in second-person voice. Same rules as the memory-level summary (no third-person pronouns, present for thinking, past for events, describe-don't-interpret).

Example:

> You're building a multi-format capture app for content creators — voice and photo on the watch, organized on the phone. You've settled on watch-only capture and a tiered pricing model with three projects free.

**Output 2 — Suggested memories.**
A short list (target 3–5) of memories from elsewhere in the user's library that may belong in this project. Each suggestion carries:

- Title and date
- One-sentence “why it may belong”, in serif italic, conversational tone (e.g. *“Mentions Studio and project synthesis — the same thread you're pulling on here.”*)
- Confidence band: **Likely** or **Maybe** (green dot / amber dot)

The user reviews suggestions in a bottom sheet. Selection is a ring (Crucible rule). **Nothing auto-adds.** The primary action is “Add N” — the user picks what fits and skips what doesn't.

### What it deliberately does *not* produce

These were considered and rejected for MVP because they violate the Honest Label principle:

- **Currents / themes** as a separate section — the paragraph already captures the thread. Fragmenting into bullets dilutes voice.
- **Open loops / next steps** — interpretive, requires inferring intent, and feels surveillant. The AI doesn't track unfinished business on the user's behalf.
- **Important memories** — a value judgment the AI shouldn't make.
- **“What's becoming” / “what changed over time”** — interpretation dressed up as observation. The LinkedIn-AI tone we built Honest Label to avoid.

Studio (post-MVP) can structure further. MVP stays the size of a paragraph plus a short list.

### Voice rules for the summary paragraph

- Second-person — `you / you're / you've` — baked in at storage time.
- Present tense for ongoing thinking; past for events that happened.
- **No third-person personal pronouns anywhere.** Other people referenced by name.
- Describe, don't interpret. The paragraph's job is to give the owner a recognizable handle six months later.
- On share/export, `replacingOccurrences("you", firstName)` swaps voice.

### Suggestion mechanics

- **Local prefilter first.** Same topics, matching mentions/entities, similar words in title/summary, nearby dates, same location. Embedding match can be added later. The library is *not* sent blindly to the AI.
- **Top 20–30 candidates** go to the AI, which re-ranks and produces the “why” line + confidence per memory.
- **AI returns at most 5 suggestions.** Better to surface 2 strong ones than 5 weak ones; the spec instructs the model to say *“nothing strong this time”* rather than fill space.
- **No auto-add.** Suggestions live in the review sheet until the user taps Add. Skipped suggestions are remembered for ~30 days so the same proposal doesn't come back next run.
- **The AI sees a bounded payload** regardless of how many candidates the prefilter surfaces — the work (and inference cost) is flat at any project size.

### Trigger and what the AI actually reads

- **Manual only.** Owner-initiated, even on Plus. New memories arrive often; auto-rewriting the paragraph on every arrival would be noise, not help — the owner decides when to pull the thread.
- **Re-running is unmetered.** Accept / edit / regenerate-after-edit / dismiss / refresh-after-new-memories all just re-run or commit — nothing is counted (matches the AI Organize spec).
- **Minimum threshold: 1 memory.** With one memory the "summary" is closer to a paraphrase than a synthesis — fine; the user gets back what they asked for. Zero memories has nothing to summarize and the button shows but is disabled, with a quiet reason line. One is the only structurally defensible threshold; any higher number is arbitrary.
- **What it sees**: for memories *in* the project — title, topic, date, and existing AI summary. For *candidate* memories (the prefiltered 20–30) — the same fields plus the memory's existing one-line excerpt if present. **Never raw transcripts or full fragments.** That's Studio's territory.

### States on the detail screen

1. **Never run** (≥1 memory): “Find the thread” card with a single **Run** button, AI blue.
2. **Below threshold** (0 memories): same card, button disabled, sub-line reads “Add a memory first.”
3. **Running**: same card with a pulsing dot or progress strip.
4. **Summarized** (current): AI-blue framed summary card at top. Below it, a quieter “N memories may belong here · Review” card if the AI returned suggestions. Memory list follows.
5. **Stale** (≥1 new memory since last run): summary card stays, plus a small `Refresh — N new` link inline. Tapping re-runs the pass.

### Tier behavior (Capture · Connect · Create)

Project Assist is the **Connect** capability — the intelligence that makes projects grow themselves. It's a **Plus** feature; the gate is intelligence, not a count.

| Tier | Projects | Project Assist (“Find the thread”) |
|---|---|---|
| **Free / Capture** | Up to **3**, built and managed **by hand** | — (build manually; the growing-itself layer is Plus). A one-time *taste* of Find the thread may be offered as a trial — see `Pricing model · Capture-Connect-Create.md`, not a metered starter. |
| **Plus / Connect** | **Unlimited** | Owner-initiated, unmetered. Related memories, suggested membership, find-the-thread synthesis, cross-project. |
| **Studio / Create** (post-launch) | Unlimited | Reads raw fragments. Cross-project synthesis. Structured output. Export. |

No starter counters, no per-run accounting, no `packBalance`. If Free is offered a trial of Find the thread, it's a trial flag (a taste of the Plus magic), decided in the pricing doc — not a quota mechanism specced here.

## Bugs fixed by this design

- **AI Summary** label and **App is inferring** block were ochre/amber on the shipping project detail. Crucible reserves AI blue `#1E5C8E` for AI moments — both move to AI blue.
- Header chrome glyphs (search, collapse, settings) were iOS system blue — they move to warm ink. Reserve blue strictly for AI.
- Duplicate "new project" affordance on the Projects tab (inline row + FAB) collapses to the inline row only.
- "Selection = check" on the Add-memory sheet is a Crucible violation (selection should be a ring; completion is a check). Flagged for a follow-up sweep.

## Out of scope for MVP

Deferred — none block shipping:

- Empty state for the Projects tab.
- Edit / delete project sheet.
- Running and stale-state polish.
- Cancel-Plus regression UX: oldest project stays, newer projects compress to read-only views.
- Share / export of a project.
- Auto-suggest *which* project a new memory should go into at capture time.
- Goal field rephrased or AI-rewritten.
- "Also in: …" affordance on memory cards (showing other projects a memory belongs to). Worth doing eventually so users aren't surprised; not blocking.

## Implementation notes

For the iOS team. These aren't design decisions but they're worth pinning before someone discovers them mid-PR.

- **Reuse `SummaryRenderer.renderForOwner`.** Don't fork the renderer for projects — the `<User>` token substitution and Honest Label voice rules live in one place.
- **Reuse the existing re-rank API path.** The “candidate set + ask AI to re-rank with one-sentence rationale” shape is structurally identical to `existing_mentions` already wired into the memory analyze endpoint. Group these as one *context-aware re-ranking* call on the server; don't grow two divergent paths.
- **Entitlement bucket.** Project Assist is a **Plus capability** in `EntitlementService` — gate it behind the Plus entitlement, not a per-run counter. If a Free trial of Find the thread is offered, it's a single boolean trial flag (`projectAssistTrialUsed`), decided in `Pricing model · Capture-Connect-Create.md` — not a quota counter.
- **AI-blue color sweep is a separate task**, not a footnote on this spec. See [AI attribution color sweep] below.

## Related work (not in this spec)

**AI attribution color sweep.** Crucible reserves `#1E5C8E` for AI moments, but the shipping iOS app uses ochre/amber across multiple AI surfaces: "AI SUMMARY" eyebrow, "APP IS INFERRING" block, the `✦` sparkle glyph, the confidence chip on memory cards, the "AI" tag on suggested titles. This is a uniform sweep — do it all at once rather than fixing surfaces piecemeal. Half-applied color rules are worse than uniformly-wrong ones. Own this as a separate small PR before TestFlight.

## Files

- `Himem · Projects.html` — design canvas: 5 screens + rules panel.
- `screens-projects.jsx` — chrome, topics, segmented control.
- `screens-projects-cards.jsx` — project card, memory card, detail header.
- `screens-projects-views.jsx` — the five screens.
- `screens-projects-spec.jsx` — annotated suggestion-row spec + row states (dev handoff).
- `crucible-primitives.jsx` — `PX` tokens used here.
