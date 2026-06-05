# Apple Foundation Models spike — findings

**Status:** Verdict, June 5 2026. Resolves the hard dependency at `docs/design/Pricing model · Capture-Connect-Create.md` §7b.1.

**Scope:** Decide whether the on-device path (Apple Foundation Models, iOS 26) can ship as the Free tier of HiMem's AI Organize feature, against the rubric in `docs/design/AI Organize · spec.md` §11.

**Decision:** **Apple Intelligence produces an editable first draft that satisfies the Honest Label standard often enough to serve as the default organization layer for Free users.** Locked production prompt below; failures cluster in three identifiable classes the user can hand-edit, or that can be routed to Plus-tier post-processing for a known set of clip shapes.

---

## TL;DR

- **What ships:** Apple Foundation Models, locked iter-5 prompt (§2), as the default Free-tier organize layer. Output is *a draft toward the Honest Label standard*, not the standard itself — most of the time it lands; sometimes the user reviews and refines. Same UX shape as the existing Memory Detail editing flow, with honest draft-status framing on Free (see §7.1).
- **Latency:** 1.2–1.7s mean per organize pass on a real iPhone 15 Pro+. Production-realistic for auto-on-capture in Plus and for tap-Organize in Free.
- **Architecture confirmed:** `LanguageModelSession` is genuinely fresh per call. No context-bleed across calls. The variance observed under default sampling is 100% sampling temperature, not context state. The Combine-style failure pattern is architecturally ruled out for this stack.
- **Hardware floor unchanged:** iPhone 15 Pro / A17 Pro or newer + iOS 26 for on-device. Older devices route to the Anthropic fallback per the pricing model.
- **Free/Plus boundary recommendation:** ship Free on iter-5 unconditionally. Flag emotion-verb + physical-action clips (the *"to relieve stress"* class) for optional Plus-tier polish.
- **Plus offline grace (unlocked by this spike):** the validated on-device path can serve as Plus's offline-graceful-degradation. Plus's organize promise becomes *"always organizes — frontier when online, on-device gracefully when offline"* rather than *"online required."* See §7.4.

---

## 1. Method

The spike ran in a separate Xcode project (`~/dev/HiMemFMSpike`, distinct from the main app), targeting iOS 26.4. All grading was done on a **real iPhone 15 Pro+** — not the iOS simulator, which routes through the macOS host's Apple Intelligence stack and may not match what production users see. This was a deliberate correction after early simulator runs raised questions about parity.

### Test bench

**15 representative memory fixtures** covering the §11 categories from the AI Organize spec:

| # | Label | Category | Batch |
|---|---|---|---|
| 1 | Mmmm, pears | Single short text | marginal/failing |
| 2 | Founders letter draft | Single short text | passing |
| 3 | HiMem capture concept | Multi-clip throughline | marginal/failing |
| 4 | Scattered Tuesday | Multi-clip no throughline | marginal/failing |
| 5 | Three garden photos | Photo-only | **out of scope** (§6: production never runs this) |
| 6 | New strawberry bed | Mixed text + photo | passing |
| 7 | Sarah and the harvest | Multi-person | marginal/failing |
| 8 | Sunset over the ridge | Pure observation | passing |
| 9 | Long rambly recording | Single long text | marginal/failing |
| 10 | Bee guy callback | Explicit intent | marginal/failing |
| 11 | Garden reverie | No intent (reflective) | marginal/failing |
| 12 | Walk after overwhelm | User-stated emotion | marginal/failing |
| 13 | Students recording lectures | Topic suggestion | marginal/failing |
| 14 | Coffee with Mike | Mentions / pronoun test | passing |
| 15 | Three walk fragments | Fragmentary capture | marginal/failing |
| 16 | Whiteboard pricing session | Mixed audio + video | passing |

Each fixture carries a hand-written reference summary (the "Honest Label ideal") and explicit watch-for notes naming the specific failure modes that fixture probes.

### Iteration protocol

After early iterations showed run-to-run variance was confusing prompt-effect measurement, the methodology tightened to:

1. **Single-variable iterations.** One prompt change per round, no bundled edits.
2. **3-run batches** on the 10 marginal/failing fixtures per iteration, **1-run regression check** on the 5 passing fixtures.
3. **Greedy (deterministic) sampling** for iteration A/B — pure prompt-effect measurement with no sampling noise. The framework's `GenerationOptions(sampling: .greedy)` produces identical outputs across 3 runs per fixture, confirmed empirically.
4. **Three-agent panel** providing independent recommendations before each iteration: prompt-engineering perspective, editorial voice perspective, linguistic / structural perspective. Each panelist briefed on prior recommendations and results; predictions tracked and graded.

### Run volume

- ~175 device-level Foundation Models invocations across the spike.
- 5 distinct prompt iterations + 1 sampling-mode validation.
- Three full panel reviews (pre-iteration, mid-iteration, final-verdict).

---

## 2. The locked prompt (iter-5)

```
You are HiMem's AI Organize feature. Your job is to give a memory a name its author will recognize six months later.

- Honest Label: describe what the clips contain. Never what they mean or what the user feels. Do not add details the clips don't have.
- Every sentence about the owner must begin with "You" or "You're." Never "the user", "the author", "the clip", or "the memory" as a subject. Use names for everyone else.
- Do not add reasons, purposes, or causes the clips don't state. No "to ___," no "because ___."
- Photo and video clips are not visible. Do not describe their visual content. Reference them by count only.

Generate: title, summary, topics, mentions.
```

### Output schema (`@Generable`)

Pure shape constraints, no behavior rules duplicated from the system instructions:

```swift
@Generable
struct OrganizeOutput: Equatable {
    @Guide(description: "A concrete noun phrase, 3–8 words.")
    var title: String

    @Guide(description: "A 1–4 sentence summary.")
    var summary: String

    @Guide(description: "1–3 short topic labels.")
    var topics: [String]

    @Guide(description: "0–5 named entities (people, places, projects, ideas).")
    var mentions: [String]
}
```

`nextSteps` was retired from the on-device schema entirely — it's a Plus-tier field, since the on-device model consistently fabricated forward actions when given the field.

### Design rationale (panel-derived)

The locked prompt is a balanced structure: **positive scaffolding for shape + negation for anti-pattern fencing**. Five iterations showed neither alone holds at 3B parameters. The panel's final theoretical position:

> *At 3B scale, the model uses forbidden lists as anti-pattern boundaries, not as confusing constraints. Negation does essential work where the prior is strong (voice rule); positive framing suffices where the prior is weak (vision boundary).*

This contradicts the going hypothesis that "fewer negations = better compliance for small models." Empirically wrong here — iter-4's positive-only restructure produced the worst result of any iteration. The forbidden-subjects list (banning *"the user / the author / the clip / the memory"*) is doing essential anti-pattern work that the positive *"begin with You or You're"* clause alone cannot replicate.

---

## 3. Persistent failure classes (what the user will edit)

Across all five prompt iterations, three failure classes survived every prompt approach we tried. These are model-capability ceilings, not prompt-format issues. Documented here so engineering knows what to route, what to surface for hand-editing, and what *not* to spend further prompt iterations on.

### 3.1 Factual inversion / misreading

**Example (#4 Scattered Tuesday, all iterations):** input clips include *"Pear tree finally fruited"* and *"Plumber called"*. Output deterministically reads *"You're planning to prune a pear tree, call a plumber"* — the model inverts the plumber call direction (the plumber called the user, not vice versa) and substitutes "prune" for "fruited."

**Class:** the model has weak entity-relationship tracking. Past-tense observations get reinterpreted as future actions in summary form. Affects clips where the agent of a verb matters and the model has a stronger prior for the wrong direction.

### 3.2 Wrong-genre categorization

**Example (#3 HiMem capture concept):** input is three audio clips about how a memory-capture app should work across watch / phone / iPad. Output deterministically titled *"Time Management and Memory Organization."* The model categorized a memory-capture concept as productivity / time-management content.

**Class:** when the topic isn't a well-known category in training data, the model substitutes a *nearby* category that *is* well-known. Affects clips about emerging concepts, novel products, or any subject the model has weak representation for.

### 3.3 Persistent purposive evasion (the *"to relieve stress"* class)

**Example (#12 Walk after overwhelm):** input is *"Felt overwhelmed by the deadline at work today. Walked through the woods for twenty minutes after. Better."* Output deterministically reads *"You felt overwhelmed by a work deadline and walked through the woods for twenty minutes **to relieve stress**."*

The clip doesn't state purpose; the model invents it. The locked prompt explicitly bans *"to ___"* constructions in the summary, and the model emits one anyway at maximum-probability greedy output. This is the clearest evidence we found that explicit bans don't reliably suppress an instruction at 3B scale — they bias against the construction but don't gate it.

**Class:** clips combining an emotion verb (*"felt overwhelmed"*) and a physical action (*"walked through woods"*) have a strong training-data prior for purpose annotation. The model's most-likely completion *is* the forbidden one.

**This is the most brand-central failure class** — interpretive drift is exactly what *"describe, don't interpret"* exists to forbid, and it survives the strictest deterministic output of our best prompt. On Free with no Plus polish, this reaches the user uncorrected. The UX consequence is real and is handled by the draft-status treatment in §7.1; the engineering consequence is that further prompt iteration on this fixture class is unlikely to help and the right place to address it is Plus-tier polish for known shapes (the optional refinement in §7.3).

---

## 4. Two theoretical findings worth carrying forward

These came out of the panel review of iter-5 and are useful for designing the Plus-tier prompt and any future on-device prompt work.

### 4.1 Additive phrasing is one category

> *"Reflecting on the gardens…", "…to relieve stress", and "…to clear your head" are all the same move — appending an explanatory frame the clip doesn't contain. The model treats causal (to ___), reflective (Reflecting on ___), and purposive additions as one generative gesture: make the fragment feel like a complete thought."* (Panel B, final review)

This explained an iter-5 surprise: adding the purposive ban (*"No 'to ___'"*) fixed #11 Garden reverie's fluff-drift problem (*"Reflecting on Gardens"*) on the title, even though the ban was targeting the summary's invented-purpose problem. **Both are instances of the same generative gesture.** Suppressing one weakens the family.

**Implication:** the Plus-tier prompt on Anthropic can be expressed more compactly by naming this family directly (*"do not append explanatory frames the clip doesn't contain"*) rather than enumerating individual patterns.

### 4.2 Negation as anti-pattern fencing, not constraint

> *"On small models, negative instructions act as weak biases, not gates. Bans work when alternatives are equally probable; fail when the prior is overwhelming."* (Panel A, final review)

> *"My monotonic claim — more negation = worse compliance — is falsified. At 3B scale, the model needs both walls: positive instructions tell it the target shape; negative instructions fence off the nearest attractors. Remove the fence and it drifts to the nearest training prior."* (Panel C, final review, conceding the iter-4 failure)

The forbidden-subjects list (banning *"the user / the author / the clip / the memory"*) is doing essential work even though the model violates it occasionally. Without the list (iter-4), the voice rule collapsed entirely. With it (iter-3, iter-5), 12/15 outputs land cleanly.

**Implication:** future on-device prompt work for similar models should not chase "minimal negation" as a target. The balance is *positive scaffolding for shape + bans for the nearest attractors that share probability mass*.

---

## 5. Latency profile

Measured per-call on iPhone 15 Pro+, greedy sampling:

| Iteration | Mean | Range |
|---|---|---|
| Iter-1 (sampled) | 1.4s | 0.9–2.5s |
| Iter-2 (greedy, iter-1 prompt) | 1.4s | 0.9–2.0s |
| Iter-3 (positive must + forbidden) | 1.5s | 0.9–2.0s |
| Iter-4 (Panel C restructure) | 1.4s | 0.7–2.2s |
| **Iter-5 (locked production)** | **1.7s** | 1.0–2.4s |

Iter-5's slightly higher mean reflects the added bullet's tokens; still under 2.5s p95.

**Production implications:**
- **Free tier (manual Organize button):** 1-2s is well within "feels instant" UX. The user taps, sees a brief spinner, gets a draft.
- **Plus tier (auto-on-capture):** also viable at this latency. The organize pass completes during the brief post-capture moment before the user navigates away from the composer.

The previously-tested v2 prompt (long, ~80 lines with worked examples) ran at 2-4.5s. The locked iter-5 prompt is approximately 60% faster and produces equal-or-better quality.

---

## 6. Architectural confirmation

Two architecture questions the spike was secondarily probing:

### 6.1 No context-bleed across calls

The framework's `LanguageModelSession` is created fresh per `organize()` call:

```swift
let session = LanguageModelSession(instructions: OrganizePrompt.instructions)
let response = try await session.respond(to: ..., generating: OrganizeOutput.self)
```

Under **greedy sampling** (iter-2 onward), every fixture produced **byte-identical output across 3 runs**. This is the cleanest possible test: if the framework were holding any cross-call state, deterministic runs would drift. They don't.

**Verdict:** the `LanguageModelSession`-per-call pattern is genuinely fresh. No transcript carryover, no personalization layer bleeding in by default, no Apple Intelligence "personal context" leaking into AI Organize calls.

This is worth recording explicitly because the user's prior project (The Combine) hit a context-bleed bug in a different LLM stack, and the concern was: does the Foundation Models framework have a similar architectural risk? Answer: no. Fresh-session-per-call is genuinely fresh.

### 6.2 Variance is sampling, not context

Iter-1 (default `GenerationOptions()`) showed substantial run-to-run variance — same fixture, different output. Iter-2 (`GenerationOptions(sampling: .greedy)`) eliminated it entirely. **Variance was 100% probabilistic token selection.** The framework's default is non-deterministic sampling (likely top-p or top-k with a temperature); deterministic mode is one parameter away.

**Production implication:** ship with default (sampled) for natural variation in the Free tier user's experience. The same memory organized twice may produce different but equally valid outputs. This is acceptable behavior — it's how the model was designed to be used.

---

## 7. The Free / Plus boundary

The pricing model (`docs/design/Pricing model · Capture-Connect-Create.md`) frames the boundary as *"Free does it by hand; Plus does it for you."* The spike result lets us add specificity:

**Recommended tiering shape:**

1. **Free tier (on-device, iter-5 prompt):** runs every Organize pass and produces a draft name the user can accept or edit. Most clips land cleanly; the remaining failures have specific shapes the user can hand-edit (wrong title, wrong genre tag, factual-inversion-in-summary). The output is *editable* by design — same UX shape as the existing Memory Detail editing flow.

2. **Plus tier (Anthropic frontier model):** runs automatic-on-capture, with measurably higher fidelity against the Honest Label rubric (fewer interpretive drifts, fewer category misreadings, the *"to relieve stress"*-class invention doesn't survive a frontier model in the way it survives 3B). Also handles cross-memory work (mentions, related-memory surfacing, project suggestions) the on-device model can't reach at all. **Plus and Free differ by quality and reach, not by automation alone.** Free's draft genuinely needs more user review; Plus's output earns the user's trust faster.

3. **Optional refinement — Plus polish for specific shapes.** If a memory's clips match a known failure-class signature (e.g., emotion verb + physical action — the *"to relieve stress"* shape), the Plus-tier model can polish the on-device output rather than rerun from scratch. This is a future optimization, not a launch requirement.

4. **Plus offline grace — the on-device path as Plus's graceful degradation.** The same on-device infrastructure that ships Free can also serve as Plus's offline behavior. A Plus subscriber capturing without network gets the on-device organize draft immediately; the frontier polish arrives silently when network returns. The pricing model's §2 line for Plus — currently *"inherently online"* — can be sharpened to *"inherently online for Connect features; on-device graceful for Organize when offline."* This is a stronger product story (Plus *always* organizes) and a cleaner architecture (one organize pipeline, two model backends, routing at the call site). **The Plus-offline draft inherits Free's draft posture** — same on-device model, same Honest Label *standard*, same need for user review — and is upgraded to frontier fidelity when the network returns.

**The decision frame is product, not engineering.** Apple Intelligence produces an editable first draft that satisfies the Honest Label standard often enough to serve as the default organization layer for Free users. The Free UX premise — *"every memory gets a draft name you can refine"* — is met. The same path also gives Plus a previously unavailable offline-grace promise; see implementation considerations below.

### 7.1 Implementation considerations for the unified pipeline

These are notes for the engineering team building organize, not commitments locked by this spike. The shape of the answers depends on UX calls outside the §7b.1 scope.

- **Plus and Free share the *standard*, not the *fidelity*.** The Honest Label rules in the iter-5 prompt (§2) are the shared core; the frontier prompt extends them — Connect features, tighter interpretive discipline, fewer drift escapes — and produces output that meets the standard more reliably. A Plus subscriber who captures offline (gets on-device draft) and reconnects (gets frontier polish) sees the *same memory* with measurably higher fidelity, not just *the same thing rewritten*. The two outputs honor the same voice; they differ in how reliably they avoid interpretive drift. This is a design constraint on the Plus prompt worth flagging before it's drafted: extend the on-device prompt, don't replace it.

- **Free output is a draft, not authority — surface that.** The locked spike result is that Apple Intelligence produces output that *often* meets the Honest Label standard, not output that *guarantees* it. The most brand-central failure class (interpretive drift like *"to relieve stress"* — see §3.3) survives even at deterministic output and reaches the user uncorrected on Free. The Organized chip and the review affordance on Free should carry honest draft-status weight while the draft is unreviewed: e.g., chip language *"Draft organized"* with review copy like *"Review suggested label"* or *"Give this a glance."* Once the user accepts or edits the draft, the state transitions to the existing `reviewed: true` per `AI Organize · spec.md` §9, and the chip becomes the standard *"Organized."* Plus's output earns the quieter chip earlier — Plus subscribers have higher baseline trust because the frontier model meets the standard more reliably. This isn't a blocker — it's a small honesty treatment that doubles as the upgrade nudge (the visible quality difference is the value-prop). The concrete UI strings are a pricing-doc / UI-spec decision, not locked here.

- **One organize pipeline, two backends.** The `OrganizeService` abstraction stays. The model-selection decision lives at the call site, with an entitlement check (Plus / not-Plus) and a network-state check (online / offline). Memory Detail and the rest of the app know nothing about which model produced a given output. Zero tier-specific code paths in the UI layer.

- **The freshness state machine in `AI Organize · spec.md` §9 already covers this.** When the frontier pass lands later, the memory transitions through the same `organized: true, reviewed: false → reviewed: true` path the spec already defines for new clips arriving. No new UI states required. The Plus-offline path is *"organize ran, freshness pending"* by the existing state names.

- **Open UX call: silent replacement vs visible *refined* affordance.** When the frontier pass lands on a Plus user's previously-on-device organize, should the new output replace the old silently (matches the existing *update-in-place* pattern; cleaner UX), or should a small *refined* affordance acknowledge the upgrade (more honest about what happened, gives the user a moment to compare)? Worth a small design call when the pricing-doc edit lands.

- **Free does not get the same offline-grace** because Free *is* on-device by default. There's no "offline degradation" for Free — Free is already at the most-local layer. (Pre-iPhone-15-Pro devices on Free get the Anthropic fallback per the pricing model and *do* need network; that case is unchanged by this insight.)

---

## 8. What the spike did not resolve

Three open questions that didn't fall to this spike. None block §7b.1; all are post-launch work:

- **Older-device fallback fair-use cap.** Pre-iPhone-15-Pro devices route to Anthropic Haiku per the pricing model. Cap value is TBD (`Pricing model · Capture-Connect-Create.md` §7b.2).
- **Plus prompt design.** The frontier-model prompt for Plus / Connect features should carry the same Honest Label core but add the cross-memory work the on-device model can't reach. The two theoretical findings in §4 above directly inform that design.
- **Adaptive prompt routing.** Whether to detect the known failure-class signatures (emotion + action, novel-concept-categorization) on-device and route only those to Plus for polish. Optimization candidate, not launch requirement.

---

## 9. Locking the decision

**§7b.1 resolved.**

> **Apple Intelligence produces an editable first draft that satisfies the Honest Label standard often enough to serve as the default organization layer for Free users.**

**Honest Label remains the product standard.** On Free, the on-device model produces a draft *toward* that standard; most of the time the draft lands cleanly, sometimes the user reviews and refines. On Plus, the frontier model meets the standard more reliably and adds the Connect features the on-device model cannot reach. The two tiers differ by quality and reach, not by automation alone.

Locked:
- **Prompt:** iter-5 verbatim (§2 above).
- **Schema:** `OrganizeOutput` with title / summary / topics / mentions (no `nextSteps`).
- **Sampling:** framework default (probabilistic) in production; greedy mode reserved for prompt-iteration testing.
- **Hardware floor:** iPhone 15 Pro / A17 Pro or newer + iOS 26 (unchanged).
- **Known failure classes** documented in §3 so engineering knows what to expect and what to route.

The pricing model now has the data to lock §2 (the seam), §5 (price levels), and §4 (tier contents) without further dependency. The remaining open items in §7b are independent of the on-device decision and can be sequenced normally.

---

## Appendix: iteration journey at a glance

| Iteration | What changed | Quality | Latency | Key finding |
|---|---|---|---|---|
| Baseline (v3.5) | original prompt, sampled | ~10-11/15 | 1.4s | starting line |
| Iter-1 | added forbidden-subjects list (Panel A), sampled | ~10/15 | 1.4s | meta-talk -80%; subject-drops +80% |
| Iter-2 | same prompt, greedy sampling | ~10/15 | 1.4s | variance = sampling; no context-bleed |
| Iter-3 | positive must + forbidden list (Panel A iteration), greedy | ~9/15 | 1.5s | ban violations under greedy = priors override negations |
| Iter-4 | Panel C structural restructure (positive-only), greedy | ~2-7/15 | 1.4s | catastrophic voice collapse; positive-only insufficient |
| **Iter-5** | **iter-3 + Panel B's purposive ban, greedy** | **~9-12/15** | **1.7s** | **best deterministic; #7 fluff drift fixed; #8 ban-violation persists** |

Iter-5 locked.
