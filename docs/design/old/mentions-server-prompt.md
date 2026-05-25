# Server-side prompt — mentions cap & dedup

**Status:** draft for the `api.thecombine.ai/himem/analyze` endpoint's `entities` field. Third in the v5 server-prompt update set — siblings: `next-steps-server-prompt.md`, `summary-voice-server-prompt.md`. All three can ship independently.

## The problem

The current prompt returns long, redundant entity lists for dense memories. Real example from a memory about AI disruption (2026-05-17 screenshot):

```
• Job displacement from AI automation
• Future employment opportunities post-AI
• Historical workforce transition failures
• Self-employment as adaptation strategy
• Future employment after technological disruption
• Lack of economic transition planning
• Job displacement from AI
• Retraining pathways for displaced workers
• Economic transition during technological shifts
```

Nine entries. Three of them are near-duplicates of others:

- "Job displacement from AI automation" ≈ "Job displacement from AI"
- "Future employment opportunities post-AI" ≈ "Future employment after technological disruption"

The UI gives the user per-mention opt-out so they can reject the dupes, but the underlying problem is **the model is generating duplicates as separate items in the first place**. The cleanest fix is upstream: cap output, enforce uniqueness on a similarity threshold.

## Hard guardrails

1. **Maximum 5 entries** total across all entity types (person + project + issue + idea). Six+ is the model over-extracting concepts.
2. **No near-duplicates.** Reject any candidate that's >70% similar to an already-selected candidate. Similarity = case-insensitive normalized string match plus simple stemming ("displacement"/"displaced"/"displaces" cluster).
3. **Prefer the more specific phrasing.** Between "Job displacement from AI" and "Job displacement from AI automation," keep the latter. Length is a rough proxy for specificity.
4. **No nested concepts.** "AI" and "AI automation" shouldn't both appear — one contains the other.
5. **Entity values are 2–6 words.** Single-word entities ("AI", "jobs") are too thin; 7+ words are summaries masquerading as entities.

## What stays

- The four entity types (person, project, issue, idea) are correct and should stay.
- Confidence scores are useful — keep them; the client uses them to rank when display space is tight.
- The existing rule about extracting only what's literally in the memory text remains.

## Worked examples

| Memory | Bad output (current) | Good output (after change) |
|---|---|---|
| Memory about AI displacement (see above) | 9 entries, 4 dupes | `[{"issue":"Job displacement from AI automation"}, {"issue":"Lack of economic transition planning"}, {"idea":"Self-employment as adaptation strategy"}, {"idea":"Retraining pathways for displaced workers"}]` (4 entries, no dupes) |
| "Met with Sarah about the garden. She's helping with the back fence." | `[{"person":"Sarah"}, {"person":"Sarah"}, {"project":"garden"}, {"project":"back fence garden"}]` | `[{"person":"Sarah"}, {"project":"Garden back fence"}]` |
| "The pear tree finally fruited." | `[{"project":"Pear tree"}, {"project":"Tree"}, {"idea":"Fruit"}]` | `[{"project":"Pear tree"}]` |

## Suggested prompt addition

Drop into the existing analyze prompt where the entities field is described.

````
ENTITIES — extract with care

Extract up to 5 entities total across person, project, issue, and idea
types. Use these strict deduplication rules:

1. MAXIMUM 5 entries. If you have more candidates, pick the 5 most
   specific and stop. Six+ entries means you're over-extracting.

2. NO NEAR-DUPLICATES. Before adding a candidate, compare it to all
   already-selected entries. If the value (case-insensitive, with
   simple stemming) overlaps more than 70%, drop the candidate. Examples
   of duplicates to collapse:
     - "Job displacement from AI" vs "Job displacement from AI automation"
       → keep the more specific one
     - "Future employment opportunities post-AI" vs "Future employment
       after technological disruption" → keep one, drop the other
     - "Pear tree" vs "Tree" → keep "Pear tree"

3. PREFER SPECIFICITY. Between two phrasings that overlap, keep the
   one with more concrete detail (usually longer, sometimes
   contains a qualifier the other lacks).

4. NO NESTED CONCEPTS. "AI" and "AI automation" can't both appear —
   one contains the other. Pick whichever specifically describes
   the entity in this memory.

5. ENTITY VALUES MUST BE 2–6 WORDS. Single-word entities ("AI",
   "jobs", "garden") are too thin to be useful. 7+ words means
   you've extracted a summary, not an entity.

6. EXTRACT ONLY WHAT'S LITERALLY IN THE MEMORY. Same rule as before;
   no invention.

Confidence stays per-entity. The client uses it to rank.
````

## Verification

1. Run analyze on the screenshot's memory (about AI displacement). Expect 4–5 entries, no near-duplicates, no nesting.
2. Run analyze on a sparse memory ("The pear tree finally fruited"). Expect 1 entity max.
3. Run analyze on a memory with multiple distinct people/places. Expect appropriately diverse extraction without redundancy.
4. Spot-check 10 real memories from the backlog. Look for:
   - Same concept appearing twice with different phrasings
   - Single-word entities
   - Counts exceeding 5
5. Once shipped, observe how the per-mention opt-out usage drops — if users were rejecting 3+ mentions per memory before this, that count should fall to 0–1.

## Re-organize passes — reuse existing mentions

**Added 2026-05-18.** A separate failure mode showed up after the entity cap landed: on re-organize passes the model invents fresh paraphrases of mentions the entry already has. A memory about sausage-making, organized three times, accumulated:

- "Sausage making process"
- "Reusable Sausage Process"
- "Create reusable sausage process"
- "Develop Reusable Sausage Process"

Four entries, one concept. The client tightened value-level dedup so cross-type exact matches collapse, but paraphrases slip through.

The fix is to ground the model on what's already attached. The client now sends an `existing_mentions` array on the request — case-folded-deduped values currently on the entry. Empty array on first-organize.

### Request shape

```json
{
  "text": "<entry text>",
  "existing_topics": ["Cooking", "How We Work"],
  "existing_mentions": ["John", "Bob", "Sausage making process"]
}
```

### Prompt addition (drop after the ENTITIES section)

````
EXISTING MENTIONS — refine, don't paraphrase

If `existing_mentions` is non-empty, those values are already attached
to this memory from a previous pass. Treat them as your VOCABULARY for
this pass.

1. REUSE existing values verbatim where they still apply. If the entry
   still mentions Bob, return "Bob" — not "Bob Smith," not "Robert."
   If "Sausage making process" already exists and the new content
   still concerns it, return that exact string — not "Reusable Sausage
   Process" or "Create sausage process."

2. ADD genuinely new mentions only when the entry contains something
   not covered by an existing value. The existing list is a vocabulary,
   not a cap — surface a new concept if the user added one. But don't
   reach for novelty; reach for accuracy.

3. DROP existing values that no longer fit. If the entry has been
   heavily edited and Bob is no longer mentioned, don't keep him in
   the response.

4. The 5-entry cap still applies. If you'd exceed it, prefer the
   existing values over new ones — preserving the user's existing
   curated set is higher signal than fresh extractions.
````

The 5-entry cap above still governs the total. `existing_mentions` constrains the *shape* of returned entries, not the count.

## Related docs

- `next-steps-server-prompt.md` — sibling change for the nextSteps field
- `summary-voice-server-prompt.md` — sibling change for the summary field
