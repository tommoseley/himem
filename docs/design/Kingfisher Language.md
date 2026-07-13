# Kingfisher Language

*How Kingfisher products speak. The sibling to `Kingfisher · North Star.md`: the North Star defines how our products **think**; this defines how they **talk**. Studio-level — it applies to every product, not just HiMem. Where a build spec and this document disagree on wording, this document wins and the spec gets fixed.*

*Version 1 · July 7 2026. Emerged from the North Star audit — the "Make or Add to Memory" label was the thread that unravelled into a whole voice.*

---

## The one idea

**The UI should ask the question the user is already asking themselves.** Nothing else in this document is more than a consequence of that sentence. When the interface and the person are asking the same question, there is no translation tax — the answer is already in mind. When they diverge, the person must first decode what the app wants, and that decoding is *muri* (see North Star).

Most software speaks in **operations** — the verbs of its own data model: *Make, Create, Add, Organize, Manage, Process*. People don't think in operations. They think in **intentions**: *where does this go, what is this becoming, is this useful, what needs my attention.* Kingfisher speaks the second language.

**Language is not voice.** Voice is tone (warm, quiet, never blaming); language is *mental model* (whose question the UI is asking). They're independent: *"Would you like to create a new memory?"* is warm **and** implementation-leaking. Warmth is necessary but not sufficient — a friendly sentence that still names a system operation has fixed the tone and missed the point. This document is about the mental model; the North Star's *Voice* section covers tone.

**This governs verbs and questions, not nouns.** "Memory," "clip," "project" are the user's words for real things they've been taught — keep them. The rule targets the *operations and questions* wrapped around those nouns: start from the user's purpose, then map onto the model. Never let this collapse into "ban all technical words" — a taught noun is not a leak.

---

## The five rules

1. **Ask the question the user is already asking.** The label matches the thought in their head, not the operation in the code. A loose clip → *"Where does this belong?"*, never *"Make a Memory."*
2. **Prefer placement over operation.** "Where does this belong?" not "Assign to container." The user is *placing* a thing, not *performing a function* on it.
3. **State observations before conclusions.** When the AI is uncertain, it reports what it sees and lets the person conclude: *"These seem related — Pennsylvania,"* then a **Review** button — never *"Accept"* or *"Create Memory,"* which claim a confidence the AI hasn't earned.
4. **Explain intent before mechanics.** Why before how. *"Building something over weeks? That's what Projects are for,"* not *"Projects organize your memories."*
5. **Never expose the data model.** "Memory," "clip," "project" are the user's words for real things — fine. "Object," "record," "instantiate," "entity," "item," "process" are the schema leaking through the paint — banned.

---

## Banned words

These are software words, not human words. They name what the *code* does, not what the *person* wants:

- **Make** (except literal: "Make a reservation" is human; "Make a Memory" is not)
- **Create** (except when the user is genuinely, consciously creating something new — "Create a project" at the moment of starting one is fine; "Create memory" from a clip is not)
- **Organize** (the app's job, not a thing we ask the user to do — and on the reflective side it implies the user is disorganized)
- **Manage**, **Process**, **Assign**, **Submit**, **Item**, **Entry**, **Record**

When tempted by one of these, ask: *what is the person actually trying to do?* The answer is the label.

---

## The context map

The same raw material (a captured clip) is addressed by a **different question at each stage**, because the user's intent has changed. This table is the operational core of the document.

| Context | The user's question | What the UI says |
|---|---|---|
| **Loose clip** (workbench) | *Where does this belong?* | **"Where does this belong?"** — sheet title. Options: *New memory · Suggested · Recent · Projects.* Placement, not operation. |
| **Idle-gap session** (already grouped) | *What should this become?* | **"Start a Memory"** / *Review clips · Add to existing · Not yet.* Now it's shaping, not placing — the recognition already happened. |
| **AI cluster** (Sort suggestion) | *Is this useful?* | Observation + **Review**. *"These seem to belong together — Pennsylvania."* The AI states; the human concludes. Never "Accept," never "Create." |
| **The workbench itself** | *What needs my attention?* | **"Review"** the day's raw material. Not "Process," not "Organize," not "Clear." A bench of materials, not a queue to zero. |
| **Memory editor** | *How do I improve this?* | Concrete verbs — **Add clips, Remove clips, Rename, Reflect, Share.** Abstraction is gone; the user is working on a specific thing they can see. |

**The principle under the table:** abstraction near the raw/uncertain end (placement, observation), concreteness near the finished/owned end (editing). The less certain the user's intent, the more the UI asks; the more defined it is, the more the UI just labels the action plainly.

---

## Placement is one primitive, one question

"Where does this belong?" is not only the workbench's opening — it's the **single question behind every clip-placement surface**, and they should share the wording:

- Placing a **loose clip** from the workbench.
- **Relocating** a clip out of one memory (the "Move clip to…" sheet in Memory Detail) — same options: *another memory · a new memory · back to the bench (unfiled).*

These are the same action from two entry points, so they ask the same question. Do **not** ship a "Move clip to…" sheet and a "Where does this belong?" sheet that do the same thing in different words. One primitive, one question. *(Reconciliation flagged July 7 2026: the Memory-Detail relocation sheet built earlier should adopt "Where does this belong?" as its title.)*

---

## Observation vs conclusion — the AI's grammar

This rule is load-bearing enough to restate on its own, because it's where "how we speak" meets the North Star's "the AI has no 'I'" and "count and reflect, never diagnose":

- The AI **observes**: *"A few of these seem to belong together."* / *"These mention Pennsylvania."*
- The AI **never concludes on the user's behalf**: not *"You should group these,"* not *"Accept,"* not *"Here's your new memory."*
- The **button reflects the confidence level**: an uncertain proposal gets **Review** (you look, you decide); only a thing the *user* has confirmed gets a committing verb.
- Stating the *evidence* is what makes the observation trustworthy: *"Review — Pennsylvania"* passes because the reason is visible. *"Review — these felt related"* fails; feeling isn't evidence.

---

## The test

For any label, ask three things:

1. **Is this the user's question, or the system's?** If it names an operation, rewrite it as the intent.
2. **Does it claim more certainty than we've earned?** An observation dressed as a conclusion is a lie with a friendly face.
3. **Would a thoughtful person say it this way?** Not *"What operation would you like to perform?"* but *"Where does this belong?"*, *"These seem related — want to look?"*, *"Still thinking about this?"*

The whole voice, in one line: **HiMem should sound like a conversation with a thoughtful person, not a form with a submit button.**
