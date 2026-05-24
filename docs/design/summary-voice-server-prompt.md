# Server-side prompt — summary voice

**Status:** Locked 2026-05-18. Paired with `ai-organize-spec.md` (§3 = source of truth for the voice rules) and siblings `next-steps-server-prompt.md`, `mentions-server-prompt.md`. All three are independent improvements to the same analyze endpoint and can ship in any order.

## What the AI must produce

Every summary stored as a string with **`<User>` (capitalized at sentence start) or `<user>` (lowercase elsewhere)** in place of the journal owner. Verb forms after the token are **third-person singular** (*is*, *has*, *was*, *does*) — never contractions, never second-person.

The client substitution layer transforms the token at render time:

- **Owner UI:** *`<User>` is exploring* → *You are exploring*
- **External (share/export):** *`<User>` is exploring* → *Tom is exploring*

Both transformations are pure regex. Storage stays canonical; what the user sees depends on who they are.

## The prompt block

Drop this verbatim into the summary section of the analyze prompt.

````
SUMMARY VOICE

Refer to the journal owner as <User> (capitalized at the start of a
sentence) or <user> (lowercase elsewhere) — never their actual name,
never with pronouns. Always use third-person singular verb forms
(is, has, was, does) with the token. Do not use contractions —
write "is" not "'s" (when meaning "is"), write "has" not "'ve",
write "will" not "'ll".

EXAMPLES (good):
  "<User> is exploring how HiMem could capture creative fragments
  across watch, phone, and iPad."
  "<User> appreciated pears."
  "<User>'s favorite recipe involves pears, and <user> noted that
  the harvest was good."

EXAMPLES (bad):
  "Tom is exploring how HiMem could capture…"           ← actual name
  "<User>'s exploring how HiMem could capture…"         ← contracted "is"
  "You are exploring how HiMem could capture…"          ← "you" baked in
  "<User> is exploring how he could capture…"           ← personal pronoun
  "The user is exploring how HiMem could capture…"      ← literal "The user"
  "The user identified an action to source trees."      ← literal "The user"
  "the user's favorite recipe involves pears."          ← literal "the user"

NEVER WRITE "THE USER" OR "the user" AS LITERAL ENGLISH

The token is the substitution surface. If you write the literal
phrase "The user" or "the user" (or possessive "The user's" /
"the user's"), the substitution layer can't tell whether you meant
the journal owner or you were writing about a generic user. ALWAYS
emit the token <User> / <user> — never the literal English phrase.

THIRD PARTIES

For any other person mentioned, use that person's name on every
reference. Do not use third-person personal pronouns (he, she, they,
him, her, them, his, hers, theirs) or reflexives (himself, herself,
themself, themselves) anywhere. Restructure to avoid awkward
repetition. Non-personal pronouns (it, this, that) are fine.

EXAMPLES (good):
  "Sarah brought a camera and used it to photograph the pears."
  "<User> and Sarah talked. Sarah said the harvest was good."

EXAMPLES (bad):
  "Sarah brought her camera."                ← her
  "Sarah said the harvest was good and she was happy."  ← she
  "<User> blamed himself for the dead tree." ← himself

REFLEXIVES

Restructure the sentence rather than using a reflexive.

  ❌  "<User> blamed <user> for the dead tree."   (reads "Tom blamed Tom")
  ❌  "<User> blamed himself for the dead tree."  (forbidden pronoun)
  ✅  "<User> blamed the dry season for the dead tree."
  ✅  "<User> regretted not watering more during the heat wave."

TENSE AND VOICE

- Present tense for thinking: "<User> is exploring how to capture…"
- Past tense for events: "<User> captured three audio clips."
- Plain English. Specific nouns. Active verbs.
- One sentence preferred, two if the memory is dense. Never more
  than four.
- Concrete subjects over abstract concepts.
- Pure observation clips (sunset photo, no audio): leave the subject
  out entirely. "A sunset over the ridge." No token needed.
- Multi-person memories: use other people's first names where known.
  If a co-subject's name isn't known, use "someone" or omit.

PROHIBITED INVENTIONS

Never claim what the user feels or thinks beyond what the clips
literally say. "<User> seems excited about…" / "<User> is anxious
that…" / "<User> reflects on the deeper meaning of…" — all of these
are inventions. Echo what's in the clips. Don't grade or
editorialize.

NO INTERPRETIVE FLOURISH

The clips contain nouns and events. They do not contain "approach,"
"philosophy," "vision," "innovation," "process," "framework," or
other meta-labels for what the user is doing — unless the user
literally used that word in a clip. Do not add interpretive
qualifiers that describe the *meaning* of the clips.

EXAMPLES (bad — interpretive drift):
  ❌ "…that represent her approach to kitchen innovation."
  ❌ "…showcasing his commitment to sustainable gardening."
  ❌ "…reflecting an exploration of urban photography."
  ❌ "…that demonstrate a thoughtful methodology."

EXAMPLES (good — echo the clips):
  ✅ "You captured Judy's cooking ideas: tomato oil; hush puppies
     with shrimp and remoulade; lemons in a tar vinaigrette;
     espresso powder over crème brûlée."
  ✅ "You photographed three urban scenes: a fire escape, a
     storefront at dusk, and a stack of milk crates."

If you find yourself writing "that represent X" or "showcasing Y"
or "reflecting Z" — stop, delete the trailing clause, and let the
concrete nouns stand on their own. The reader can interpret.

ZERO TOLERANCE — THIRD-PERSON PRONOUNS

This rule is repeated because output 2026-05-18 contained "her" in
a load-bearing position ("…that represent her approach"). The
restructure required isn't optional: if you would naturally write
"his/her/their/them," REWRITE the sentence to use the person's name
again, or drop the clause entirely.

EXAMPLES (bad — pronoun in load-bearing position):
  ❌ "Judy's cooking ideas — her approach blends…"
  ❌ "Sarah painted three walls — she chose ochre for the trim."

EXAMPLES (good — name repeated, or clause dropped):
  ✅ "Judy's cooking ideas — Judy blends…"  (if the clip warrants)
  ✅ "Judy's cooking ideas: tomato oil, hush puppies, vinaigrette."
     (drop the interpretive clause — let the nouns do the work)
````

## Verification

After this lands server-side, the client team can verify mechanically:

1. Run analyze on a reflective memory. Storage form should contain `<User>` or `<user>` tokens; never the actual user's name.
2. Storage form should never contain contracted forms (`<User>'s` meaning "is", `<user>'ve`, `<user>'ll`).
3. Storage form should never contain third-person personal pronouns or reflexives. Grep the output:

   ```bash
   grep -E "\\b(he|she|they|him|her|them|his|hers|theirs|himself|herself|themself|themselves)\\b" output.txt
   ```

   Any hit is a prompt-engineering failure.

4. Pass the storage form through the client's `SummaryRenderer.renderForOwner(_:)` and check the result reads as second-person English with no broken verb agreement.
5. Pass the storage form through `SummaryRenderer.renderForExternal(_:name:)` with a name like *Tom* and check the result reads as third-person English with the name in subject and possessive positions correctly.

## Related

- **Spec:** `docs/design/ai-organize-spec.md` §3 (full voice rules)
- **Sibling prompt docs:** `next-steps-server-prompt.md`, `mentions-server-prompt.md`
- **Client renderer:** `MemoryStream/Services/AI/SummaryRenderer.swift`
- **Tests:** `MemoryStreamTests/SummaryRendererTests.swift`
