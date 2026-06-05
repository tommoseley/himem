# Pricing model · Capture · Connect · Create

**Status:** proposal / direction. Drafted June 4 2026. Supersedes the assist-quota framing in `archive/assist-model/Open work · pricing flow.md` and parts of CLAUDE.md § AI Organize once ratified. **Not yet locked** — three assumptions need verification (see §7).

This reframes HiMem's pricing from *metered AI assists* to *life-stages of a memory*. The thesis: nobody wants to buy assists; people buy outcomes. The tiers are named for what the user gets, not what we count.

---

## 1 · The spine — three verbs

| Tier | Verb | Promise | Launch? |
|---|---|---|---|
| **Free** | **Capture** | Never lose a good idea — privately, on your device, even offline. | ✅ |
| **Plus** | **Connect** | Your memories start connecting themselves. | ✅ |
| **Studio** | **Create** | Turn what you've captured into something useful. | Later — hidden until real (§7) |

This maps 1:1 onto the product architecture we already locked: capture paradigms → Memory Box → AI Organize → Project Assist → (post-MVP) Studio synthesis. The pricing story is just the architecture, named honestly.

The pricing page is organized around the three verbs. The words "token," "assist," and "quota" never appear.

**The headline above the three verbs — the inversion no server-only competitor can match:** on a supported device, Free runs **entirely on-device and fully offline**. Usually paying buys you privacy; here **Free is the private, offline, on-your-device tier**, and paying buys you *reach* — Plus is the tier that reaches across your library. That inversion is strong enough to lead the page.

---

## 2 · The seam — manual + on-device vs. automatic + frontier

The Free/Plus boundary is **a behavior and an intelligence level**, not a quota. And it is the **same seam applied twice** — to memories and to projects:

> **Free is "you do it by hand." Plus is "it does itself."**
> Memories: Free = manual organize → Plus = automatic. Projects: Free = manually built → Plus = grow themselves.

One coherent line through the whole product. The user learns the boundary once and it holds everywhere. The gate is never "Free can't use X" — it's "Free does X by hand; Plus makes X happen for you."

**Free / Capture — AI organize is a deliberate, manual act.**
- The *Organize* button is always present on a memory. The user taps it when they want it. They feel each one.
- Runs on **on-device intelligence** (Apple Foundation Models, iOS 26). Fast (1.2–1.7s), private, free. Produces an **editable first draft** — title, summary, topics, mentions — that the user accepts or refines. Validated against the Honest-Label rubric by the June 5 spike (12/15 clean; misses are hand-editable, documented in `AI Organize · spec.md`). *No `nextSteps`* — proactive "what to do next" is a Plus field (it's the system acting *for* you).
- **Fully offline on a supported device.** Capture, store, search, topics, *and* organize all run with the radio off — on a plane, in a dead zone, in a basement. Nothing is sent anywhere. The complete Free loop needs no connection.
- No counter, no starter allotment, no "out of assists" wall. The card is never muted. Friction-of-tapping is the only limit.

**Plus / Connect — the same organize, but ambient and deeper.**
- **Automatic** organize on capture. The thing you *did manually* now happens *for you*.
- Runs **server-side on a frontier model** — the depth on-device can't reach: mention extraction, related memories ("what have I already said about this?"), project suggestions ("8 memories may belong here"), cross-memory synthesis.
- Not a faster Free — a *smarter, higher-fidelity* one, plus automatic. **The seam is quality + reach, not automation alone:** the frontier model drifts less, miscategorizes less, and doesn't invent the interpretations the on-device model sometimes does (spike §3.3, §7.2). Don't let the value prop reduce to "skip the tap" — it's "organized more reliably, and connected across your library."
- **Online for Connect; offline-graceful for Organize.** Cross-library Connect features (related memories, project suggestions) reach across the library via server compute, so they need a connection by nature. But **organize itself never blocks offline**: a Plus subscriber capturing without network gets the validated on-device draft immediately, and the frontier polish lands silently when the network returns. Plus *always organizes* — frontier when online, on-device gracefully when offline. (Unlocked by the June 5 spike, §7.4 of its findings: one pipeline, two backends, routed at the call site.)

**Studio / Create — synthesis and generation.** Long-form Sources (lectures, meetings, interviews, sermons, voice journals), Find the Thread, study guides, article/script/outline generation, multi-memory synthesis, project intelligence (supporting + contradictory memories, cross-project). Clearly its own thing.

**The upgrade moment becomes an offer, not a wall.** Instead of "you've hit your limit, pay to continue," it's "you keep tapping Organize — want it to happen automatically, and deeper?" The paywall moves from *frustration* to *recognition of a habit*. On-brand for a reflective product, and aligned with the no-blame voice.

---

## 3 · AI tiering & cost (the engine under the seam)

| Path | Who | Compute | Marginal cost |
|---|---|---|---|
| On-device organize | Free, **iPhone 15 Pro+ / iOS 26** | Apple Foundation Models, local | **Zero** |
| Fallback organize | Free, older devices | Server-side Anthropic (Haiku-class, short context) | Real, but small + **shrinking** |
| Frontier organize | Plus / Studio | Server-side frontier model | Real — paid for by subscription |

**Why the cost curve is benign.** The on-device path is the **majority** case and grows every quarter as the install base rolls forward — so the expensive fallback path *self-extinguishes*. The worst the fallback ever costs is today; it's cheaper every month after. Basic organize is a cheap call regardless.

**Offline is tied to the same device floor.** On-device Free (15 Pro+/iOS 26) is fully offline-capable, organize included. The Anthropic fallback path **needs the network**, so older devices can't organize offline — the offline guarantee is scoped to supported devices. One more reason the device floor is load-bearing, and one more reason marketing must say "on supported devices," never a blanket "HiMem works offline" (which would be a lie for the older tail, and false for Plus's connect features).

**Manual-on-Free does quiet cost work:** it pushes the expensive behavior (high-volume, automatic, frontier) behind the paywall. Free users self-limit by friction; paid users generate the cost and pay for it. This keeps the unit economics honest.

**Decisions (recommended defaults):**
- **Fallback is softly fair-use-capped** (e.g. a generous daily limit), invisible unless clearly abused. On-device users have **no** cap. This is the *only* place the old metering machinery survives — abuse insurance on the minority path, never a visible counter.
- **The user never sees which path ran.** No "on-device" vs "cloud" badges — that's plumbing. The only visible AI distinction is basic (Free) vs. deeper-and-automatic (Plus). Honest-Label provenance applies equally to both.

---

## 4 · Tier contents (working draft)

**Free / Capture**
- Unlimited memories, clips, Apple Watch capture
- Search, topics
- **Projects, built by hand** — create, add/remove memories, titles, goals, browse, search-within. **Up to 3 projects.** The *intelligence* that grows projects is Plus.
- **Manual** organize (on-device, or fallback on older devices)
- 7-day Recently Deleted

**Plus / Connect — everything in Free, plus**
- **Automatic** organize on capture (frontier model)
- Mention extraction, related memories, project suggestions, memory linking
- Unlimited projects, better search

### Projects — the same seam, applied to containers

The boundary is **not** "Free can't use Projects." It's **"Free builds Projects; Plus helps Projects grow themselves."**

| | Free / Capture (manual) | Plus / Connect (automatic) |
|---|---|---|
| Create projects | ✅ manually | — |
| Add / remove memories | ✅ manually | — |
| Browse, search/filter within a project | ✅ | — |
| Titles & goals | ✅ manual | — |
| Find related memories | — | ✅ |
| Suggested project membership ("8 memories may belong here") | — | ✅ |
| Auto-linking | — | ✅ |
| "What have I already said about this?" | — | ✅ |
| Cross-project relationships | — | ✅ |
| Project count | up to 3 | unlimited |

Free gets a *genuinely usable* Projects feature — you can build and manage real projects by hand. Plus is what makes them **grow without you**: the intelligence, not the container.

**Studio / Create — everything in Plus, plus** *(post-launch — see §7)*
- Long-form Sources
- Find the Thread, study guides, flash cards
- Article / script / presentation-outline generation
- Multi-memory synthesis, project intelligence (supporting + contradictory + cross-project)

---

## 5 · Price levels & the break-even rationale

**Plus / Connect: $4.99–$7.99 / month. Studio / Create: $7.99–$14.99 / month. Annual at ~2 months free (10× monthly).**

| Tier | Monthly | Annual (~2 mo free) |
|---|---|---|
| **Plus / Connect** | $4.99 – $7.99 | $49.99 – $79.99 / yr |
| **Studio / Create** | $7.99 – $14.99 | $79.99 – $149.99 / yr |

Final points within each band set against willingness-to-pay once Connect's "magic" and Studio's output quality are real. Recommended opening points: **Plus $6.99/mo ($69.99/yr)**, **Studio $12.99/mo ($129.99/yr)** — high enough to clear the $4.99 break-even trap, low enough to stay impulse-tier.

Break-even @ 3% conversion (illustrative, single-tier):

| Price | Total users needed | Pro subs |
|---|---:|---:|
| $4.99 | ~18,300 | ~550 |
| $9.99 | ~8,000 | ~240 |
| $14.99 | ~5,300 | ~160 |

**What the table says:** break-even is brutally price-sensitive. $4.99 is the trap row — it needs a small city to break even. The defense against pricing Plus near the bottom of its band is **the two-tier stack**: Studio at $7.99–$14.99 drags blended ARPU well above the Plus price, so the *effective* break-even sits below the Plus-only line even if Plus opens at $4.99–$6.99. The Studio tier is what makes a low Plus entry survivable.

**Why outcome-pricing earns these numbers.** "$X for 50 assists" can't credibly move up-band — same commodity, more units. "Your memories organize and connect themselves, privately and offline" is a *different kind of thing*. The Capture/Connect/Create reframe (and the offline/privacy inversion) is the *permission* to price on value, not units.

**Robustness note:** the table is *break-even*, not profit, and 3% blended conversion is the **good** case for a memory app. Design the model to survive **1.5%** (≈ double every number). The two-tier stack + annual prepay (cash up front, lower churn) are the cheapest insurance against soft conversion. If Plus opens at the low end of its band, **lean on Studio attach-rate and annual mix** to carry the economics — don't assume Plus volume alone clears it.

**The price is earned, not assumed.** Each band's *upper* end holds only if the tier feels worth it. Build priority follows: Connect has to be **visibly valuable** on first encounter, and Studio's outputs genuinely useful. A thin tier churns at any price. *(Which specific Plus feature carries that — see §7c, Product strategy.)*

---

## 6 · What this simplifies / retires

- **Exhausted-state surfaces largely disappear.** `STARTER USED` / `MONTHLY USED` muted cards, urgency cues, the "out of assists" wall — all were machinery for *counting*. With Free = "tap the button, on-device, as often as you like," there is no muted state and no counter on the basic plan. *(The Plus pack-purchase / assist-pack model may also retire or shrink — TBD against how Plus fair-use is framed.)*
- **The starter-assist mechanic mostly evaporates** — or becomes a tiny "first few are on us" nicety, not the headline. The loud-vs-silent starter debate is largely moot.
- **Pricing canvas (§14/§15) gets simpler, not bigger.** Likely retire the exhausted/pack artboards in favor of the upgrade-as-offer moment.

---

## 7 · Decisions locked (June 4 2026)

*Architectural facts — true independent of implementation. If a line starts to read "we should…" / "users need…", it belongs in §7c, not here.*

- **Launch is Free + Plus only. Studio ships later** — "coming later," or hidden entirely until it's real. Don't sell Create at launch unless the outputs are genuinely useful; a paid tier that underdelivers poisons trust in the others. The pricing page at launch is two tiers; the economics (§5) therefore lean on **Plus + annual mix** at launch, with Studio as upside, not a launch assumption. *(Resolves old Q3.)*
- **Free = 3 projects.** Free builds and manages up to **three** projects by hand — enough to genuinely use the feature and understand "building toward things," while "unlimited projects" stays a tangible Plus line. (Single-project was too thin to show what Projects *are*.) Reconcile with `Projects · MVP spec.md`, which currently locks 1. *(Resolves old Q4.)*
- **Free Projects = build by hand, not unlock.** The Projects boundary (§4) is the same manual-vs-automatic seam: Free creates and manages projects manually; Plus supplies the intelligence that grows them (related memories, suggested membership, auto-linking, cross-project, and whatever becomes the hero Plus feature).
- **Offline messaging stays scoped.** Always "on supported devices." Never a blanket "HiMem works offline" (false for the older fallback tier and for Plus's connect features).
- **Device floor:** iPhone 15 Pro or newer, iOS 26, for on-device. Older → Anthropic fallback.
- **[RESOLVED June 5 2026] On-device organize ships as the Free layer.** The hard dependency is cleared. The Apple Foundation Models spike (`docs/architecture/foundation-models-spike-findings.md`) returned a product-grade **yes**: the locked iter-5 prompt produces an editable Honest-Label first draft (12/15 clean; documented failure classes are hand-editable), at 1.2–1.7s, with genuinely fresh per-call sessions (no context-bleed). Free organize, the offline story, and Plus's offline-grace all rest on this validated path. **§2, §4, and §5 may now lock with no remaining AI dependency.**
- **`nextSteps` is a Plus-only field.** The on-device model fabricates forward actions, so it was cut from the on-device schema. This fits the seam: proactive "what's next" is the system acting *for* you (automatic/Plus), not describing what's there (manual/Free).

## 7c · Product strategy (guidance, not locked)

*Recommendations and directives — true given a roadmap choice, not given the architecture. The pricing model works regardless of how these resolve.*

- **Plus needs one obvious magic moment.** Connect must have a single demoable thing that is **visibly worth paying for** on first encounter — the hero feature. Strong candidates: *"8 memories may belong here"* (suggested membership), *"What have I already said about this?"* (semantic recall), related-memories. The **architecture is indifferent to which one wins**; the roadmap is not. Picking and polishing the hero is the #1 Plus build priority — a Connect tier without a legible magic moment churns at any price. *(Tightly coupled to §7b.2: the hero feature and the "unlimited vs. cost" ceiling are the same question seen from marketing and engineering.)*

## 7b · Still open / to verify

*(The hard AI dependency — old 7b.1 — is resolved; see §7. These remaining items are independent of the on-device decision and don't block pricing-screen work.)*

1. **Fallback fair-use cap value** — TBD (generous soft daily limit on the older-device Anthropic path only; invisible unless abused). *(Spike §8.)*
2. **Plus "unlimited" vs. cost.** Automatic frontier organize on 500 memories is a real bill. Does "unlimited" carry an invisible fair-use ceiling, and does any pack mechanic survive for the heavy Plus user?
3. **Unsupported-device offline organize.** On an *unsupported* device with no signal, Free organize can't run on-device *or* reach the fallback. Recommended state: the *Organize* action **queues and runs when a connection returns** — no blame, no error, quiet pending affordance, matching the watch's "syncs when near" language. Needs designing.
4. **Free draft honesty treatment.** The on-device model can emit confident *interpretation* it was told to avoid (the *"to relieve stress"* class, deterministic; spike §3.3) — the most brand-central violation possible, reaching Free users uncorrected (no Plus polish). **Resolved in principle** (`AI Organize · spec.md` §2b/§9): the Organized chip is a **review-state label, not a tier badge** — an unreviewed pass reads *"Draft organized"* / *"Give this a glance"* on **both** tiers, becoming plain *"Organized"* only on accept/edit. Never stamps "Free" on a memory; never claims "Organized" before a human confirms. Remaining call is the exact UI strings, settled during the Pricing/Memory-Detail canvas pass. *Design decision, not an architecture gate.*
5. **Plus offline-grace UX:** when the frontier pass lands on a previously-on-device Plus memory, silent replacement (matches update-in-place) vs. a small *refined* affordance? *(Spike §7.1.)*

---

## 8 · Next step

**The AI dependency is resolved (June 5).** §2, §4, §5 are ratifiable now. The path forward:

1. **Lock §2 / §4 / §5** — the seam, tier contents, and price bands have no remaining gate.
2. **Build the new Pricing canvas** against this model — most of it *simplifies* (no exhausted/pack/counter surfaces). Resolve the §7b.4 Free-draft honesty treatment as part of that design pass, since it affects the Memory Detail Organized affordance.
3. **Sequence §7b normally** — fallback cap, Plus ceiling, offline-grace UX are independent and don't block screens.
