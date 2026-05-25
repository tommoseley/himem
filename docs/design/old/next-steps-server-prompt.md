# Server-side prompt addition — `nextSteps`

**Status:** draft for the `api.thecombine.ai/himem/analyze` endpoint. Client-side wiring already shipped (2026-05-17) — the `ClaudeAPIService.AnalysisResult` decodes an optional `nextSteps: [String]?` field. When this prompt change lands server-side, the Next steps row in the v5 `AISuggestionsCard` will start populating automatically; no client release required.

**Related:**
- `docs/design/summary-voice-server-prompt.md` — sibling prompt change for the `summary` field (reflective voice, name-aware)
- `docs/design/mentions-server-prompt.md` — sibling prompt change for the `entities` field (cap + dedup)

Three independent server-prompt updates; can ship in any order.

## Why we're adding it

Tom's framing (2026-05-17): an assist needs to feel like real organizing labor — *"I named this · I summarized this · I filed this · I found the people/places/projects · I noticed possible next actions · I connected it to related memories."* Four of those six surface in the Review card today. **"I noticed possible next actions"** is the gap this prompt change closes.

## The contract

Response JSON gains an optional field:

```json
{
  "entities": [...],
  "topics": [...],
  "summary": "...",
  "title": "...",
  "nextSteps": [
    "Call Sarah about the garden",
    "Pick up tomatoes Tuesday"
  ]
}
```

Field omitted entirely when there are no next steps. Empty array also acceptable. The client decoder treats both as "Next steps row hides."

## Hard guardrails

These are the non-negotiables. Violating any of them produces the "AI invented filler" failure mode that erodes the assist's perceived value.

1. **Only suggest next steps that are explicitly present in the memory** as a concrete action, commitment, reminder, follow-up, or unresolved task. The memory must already contain the intent — the AI's job is to extract it, not to imagine what the user *should* do.
2. **No invented filler.** Specifically: never produce next steps like *"consider reflecting on…"*, *"think about whether…"*, *"perhaps revisit…"*, *"explore the idea of…"*. If the memory doesn't contain a concrete action, return no next steps.
3. **Past tense events with no follow-up = no next step.** "Met with Sarah about the garden" is a recorded fact, not a next action. Only flag it if the memory ALSO says something like "need to send her the photos" or "she's going to email me back."
4. **Reflections, observations, and descriptions = no next step.** "The pear tree finally fruited" is a noticing, not a todo.
5. **Verb-first, imperative, short.** "Call Sarah about the garden" not "I should probably call Sarah about the garden when I get a chance." These strings will eventually flow into iOS Reminders and Calendar titles (per the parked memory `project_reminders_integration.md`), so they need to read well as standalone item titles.
6. **No trailing punctuation.** "Call Sarah" not "Call Sarah." — matches Reminders/Calendar conventions.
7. **Max ~10 items.** Most memories have 0–3 next steps. A memory generating more than 10 is almost certainly the AI inventing. Cap server-side.

## Worked examples — when to extract

| Memory excerpt | nextSteps |
|---|---|
| "Need to call Sarah about the garden before the weekend." | `["Call Sarah about the garden"]` |
| "Should pick up tomatoes from market Tuesday. Also email Mike about the lease." | `["Pick up tomatoes Tuesday", "Email Mike about the lease"]` |
| "Reminded myself to follow up on the loan paperwork." | `["Follow up on loan paperwork"]` |
| "Mike said he'd send me the contract by Friday. I need to review it before signing." | `["Review Mike's contract"]` |
| "Forgot to RSVP for the wedding — do this today." | `["RSVP for the wedding"]` |

## Worked examples — when to skip

| Memory excerpt | nextSteps |
|---|---|
| "The pear tree finally fruited. Three pears, the size of fists." | omitted (observation, no action) |
| "Watched the rain for an hour. Felt peaceful." | omitted (reflection) |
| "Met with Sarah about the garden. She had good ideas about the back fence." | omitted (past event, no stated follow-up) |
| "The light hit the kitchen at sunset and everything felt amber." | omitted (description, no action) |
| "Had a great workout this morning. Two miles, faster than last week." | omitted (recorded fact, no committed next action) |

## Suggested prompt addition

If your current analyze prompt is a single instruction block, this is a paste-ready addendum to drop in. If your current prompt is structured as multiple message turns, adapt accordingly.

````
ADDITIONAL OUTPUT: next steps

In addition to the existing fields (entities, topics, summary, title), produce a `nextSteps` array.

Rules:

1. Only include items the user explicitly mentioned as a concrete action,
   commitment, reminder, follow-up, or unresolved task. Do NOT invent next
   steps the user didn't suggest themselves.

2. Skip the field entirely (or return []) when the memory contains no
   concrete action. Reflections, observations, descriptions, and past-tense
   recordings with no stated follow-up do NOT qualify.

3. Reject filler phrasing: "consider …", "think about …", "perhaps …",
   "explore …", "reflect on …". If your candidate item starts with any of
   these, drop it.

4. Format each item as a verb-first imperative, ≤ 8 words, no trailing
   punctuation. These will surface as iOS Reminders / Calendar item titles.

5. Maximum 10 items. If more than 10 candidates exist, the memory is
   probably being over-interpreted; pick the most explicit and stop.

Examples (extract):
- "Need to call Sarah about the garden" → ["Call Sarah about the garden"]
- "Email Mike about the lease before Friday" → ["Email Mike about the lease"]
- "Pick up tomatoes from market Tuesday" → ["Pick up tomatoes Tuesday"]

Examples (skip):
- "The pear tree finally fruited" → omit (observation)
- "Met with Sarah about the garden" → omit (past event, no follow-up)
- "Watched the rain for an hour" → omit (reflection)
````

## Verification — what to test once server ships

1. Run analyze against a memory with explicit todos → `nextSteps` populated with verb-first short items.
2. Run analyze against a pure reflection ("the pear tree finally fruited") → `nextSteps` absent or `[]`.
3. Run analyze against a past-tense event ("met with Sarah") → `nextSteps` absent.
4. Confirm the client receives the field, writes to `OrganizePass.nextStepsMarkdown` (existing test: `processEntry_withNextSteps_writesMarkdownBullets`), and the Next steps row appears in the AISuggestionsCard.
5. Spot-check 10–20 real memories from your own backlog. If you see "consider reflecting on…" type filler appearing, the guardrails are leaking — tighten with explicit forbidden-phrase examples.
