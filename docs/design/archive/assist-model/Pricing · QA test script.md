# Pricing · QA test script

**What this is.** The single QA script for HiMem's pricing surfaces. Walks every state of the subscription / assist economy across tiers and exhaustion conditions, with the exact lever changes needed to reach each state and the expected on-screen result. Run top-to-bottom; each block is independent so you can also jump to one.

**Where to run.** Two surfaces under test, same states walked on each:

1. **HTML Pricing canvas** — open `Himem · Pricing.html`. Lever = the **Tweaks panel** ("Pricing state", lower-right). Only the artboards labeled **Live · reflects tweaks** (`ai-live`, `hub-live`, `founders-live`, `supporter-live`) respond — the labeled-state artboards (`hub-free`, `mem-1of3`, `free-mem-exhaust`, `reorg-plus-out`, etc.) are pinned demos and don't move with tweaks; verify those by reading the static screen.
2. **iOS app** — open HiMem on device or simulator → **Settings → Debug · Pricing** (bottom of Settings, DEBUG builds only). Lever = the debug panel controls.

The lever names map to each other; the *Set* lines below name the iOS controls (HTML tweaks use the same keys minus the camel-case — `Starter used` is the `starterUsed` slider; `Tier picker` is the `tier` select).

**iOS setup (do once):**

1. Tap **Reset** at the bottom of the debug panel to clean prior state.
2. Toggle **Use developer override** ON. Pins the tier to whatever you pick, bypassing StoreKit.
3. Have at least one **organized memory** ready (record a voice note as Plus, let it auto-organize, dismiss the review card) — needed for stale-state tests.
4. Have at least one **Captured Clips session** in the inbox — needed for the bundle-sheet tests.

**HTML setup:** load `Himem · Pricing.html`. The Tweaks panel is the lever; no other setup needed.

**Lever vocabulary.**

| Lever (HTML key / iOS control) | Values |
|---|---|
| `tier` / Tier picker | `free` · `plus_monthly` · `plus_yearly` · `founders` |
| `monthlyUsed` / Monthly used slider | `0–50` (Plus included assists used this month) |
| `packBalance` / Pack balance slider | `0` · `20` · `100` · `120` |
| `starterUsed` / Starter used slider | `0–3` (free-tier starter assists used) |
| `foundersRemaining` / Founders remaining slider | `250` · `203` · `100` · `25` · `12` · `0` |
| `tenured` / Mark tenured toggle | on / off (≥1mo + ≥10 memories) |
| `supporter` / Supporter overlay picker | `none` · `monthly` · `yearly` |
| `promptState` / Upgrade prompt state | `not-triggered` · `triggered` · `dismissed` · `converted-plus` |
| Auto-organize threshold (iOS only) | `0–50` |

**On Free tier and the Pack balance slider — read this once.** Per pricing spec (and F5 invariant), **free users have no packs**. Packs are a Plus-only tool. Internally, the iOS implementation stores starter grants in the same `packBalance` field used by Plus pack purchases — storage detail, not spec violation. **For Free testing, treat `Starter used` (0–3) as the lever.** Set both sliders consistently: `Starter used = N` AND `Pack balance = 3 − N`. The relationship is mechanical; this script writes both in each *Set* line for unambiguity. (Follow-up: rename the iOS panel control to a tier-aware label — "Starter remaining" when Tier=Free, "Pack balance" when Tier=Plus.)

**Glossary:**

- **OMC** = OrganizeMemoryCard (the big card on Memory Detail when an entry isn't organized). Rendered on HTML by `OrganizeCard` / `ScrMemoryIdle` / `ScrMemoryExhausted`.
- **ASC** = AISuggestionsCard (the review/organized card shown after AI ran). Rendered on HTML by the stale card in `pricing-screens-reorganize.jsx`.

Reset before each block by re-setting only the levers the block names — leave others at their previous values unless told otherwise.

---

## Part A · Free tier · starter assist lifecycle

The 3 starter assists are the only meter free users have on AI Organize. Walk the full burn-down.

### A1 · Fresh free user (3 of 3)

**Set:** Tier = `Free` · Starter used = `0` · Pack balance = `3` · Monthly used = `0`.

- **Settings → Your AI** shows the onboarding starter card with **3 of 3 starter assists**.
- **Memory Detail** (a fresh memory) shows the **idle OMC**: ochre `1 ASSIST` pill, body "Suggests a title, summary, topics, mentions, and next steps."
- **No** `1 LEFT · FREE` caption yet (cue fires only at exactly 1 remaining).

### A2 · One assist remaining · urgency cue

**Set:** Starter used = `2` · Pack balance = `1` (mechanically: `3 − starterUsed`).

- Idle OMC unchanged otherwise, but **under the `1 ASSIST` pill**, a small warn-color caption reads `1 LEFT · FREE`. Ambient, no banner, no modal.

### A3 · Starter exhausted (Free)

**Set:** Starter used = `3` · Pack balance = `0`.

Open a fresh memory:

- OMC is muted (~92% opacity), sunk-grey icon tile.
- `1 ASSIST` cost pill is **replaced** by a warn-tint **`STARTER USED`** pill.
- Body reads: *"Your **3 free starter assists** are spent. Add a pack or get 50/month with Plus. **See options →**"*
- **No dollar amount** anywhere on this card.
- Tap the card → opens **Upgrade Hub** (subscription paths). NOT the AIPackPurchaseSheet — Free users aren't subscribed yet, so they convert via the hub.

### A4 · Bundle sheet without assists

**Set:** Still `Free` · Starter used = `3` · Pack balance = `0`.

Open **Captured Clips** → tap **Make or Add To a memory** on a session:

- Title field pre-fills with `Voice clips · MMM d, h:mm a` (earliest clip's timestamp).
- Caption below the title field: `Placeholder · edit any time.`
- Below the title field, a small sunk-grey card: AI-blue sparkle tile + **Get AI title** label + "Summarizes the session in a few words." sub-line + **`1 assist →`** accent link on the right.
- Tap **Get AI title** → routes to **Upgrade Hub**. *(Spec decision per `Open work · pricing flow.md` Gap 1 — confirmed. If iOS routes elsewhere, that's the regression to chase, not a script bug.)*
- No "AI" tag on the title field (no AI is staged).

---

## Part B · Free tier · settings + upgrade discovery

### B1 · Settings · Your AI · free

**Set:** Tier = `Free` · Starter used = `2` · Pack balance = `0`.

Open **Settings → Your AI**:

- Counter card reads **1 of 3 starter assists left** (or similar — the math is `3 − starterUsed`).
- **No pack section.** Free users can't buy packs.
- **No "Monthly resets" row.** Free has no monthly bucket.
- **"Upgrade for more" / Upgrade hub** row visible.

### B2 · Upgrade Hub · free

**Set:** Same as B1.

Tap into the Upgrade Hub:

- Three options visible: **Plus · Monthly**, **Plus · Yearly**, **Founders Lifetime** (if `foundersRemaining > 0`).
- Each tier card shows its price.
- **No pack purchase option visible to free users.** Packs are a Plus tool.
- Every dollar amount on the canvas appears on *this* surface, not on the surfaces that pointed here (Memory Detail's exhausted OMC shows `See options →` only, no $).

### B3 · Founders availability sub-states

**Set:** Founders section · Remaining = `12`.

- Founders option in Upgrade Hub shows a warn-tint pill `12 of 250 left`.
- Open the Founders detail screen — same pill visible.

**Set:** Founders remaining = `0`.

- Founders option in Upgrade Hub becomes **inert / hidden** (per spec).

---

## Part C · Plus tier · included-assist lifecycle

### C1 · Plus · fresh month

**Set:** Tier = `Plus · Monthly` · Monthly used = `0` · Pack balance = `0`.

- **Settings → Your AI** shows **50 of 50 assists this month**, plus reset date.
- Memory Detail's idle OMC: ochre `1 ASSIST` pill, no urgency cue, no "from your pack" caption.

### C2 · Mid-month

**Set:** Monthly used = `37`.

- Settings → Your AI reads **13 of 50 left this month** (or equivalent).
- Memory Detail behavior unchanged — `1 ASSIST` pill on every Organize card.

### C3 · Plus exhausted (no pack)

**Set:** Monthly used = `50` · Pack balance = `0`.

Open a fresh memory:

- OMC muted, sunk-grey icon tile.
- Warn-tint pill reads **`MONTHLY USED`**.
- Body: *"This month's 50 assists are used. Resets **[date]**. **Get more →**"*
- **No dollar amount on this card.** Pure `Get more →`.

Open an organized memory with a new clip added (stale):

- The Reorganize card mirror-renders the same swap: muted icon + `MONTHLY USED` badge + identical body + `Get more →`. The STARTER USED / MONTHLY USED swap must read identically on both the first-pass (idle) and reorganize (stale) cards.
- Tap either card → opens **AIPackPurchaseSheet** (NOT Upgrade Hub). Plus stays Plus; pack is additive.

### C4 · Pack purchase modal · price reveal

Tap from C3 to open the **AIPackPurchaseSheet**:

- Two pack options visible: **20 assists / $4.99** and **100 assists / $19.99**. The 100 carries a **`Better value`** tag per `ScrPlusPackModal`. *(Note: the iOS `AIPackPurchaseSheet` may render this as a `20% off` chip instead of `Better value` — that's a copy mismatch with the JSX spec. Flag as a follow-up if seen; not a blocker.)*
- Each pack shows its price and per-assist math.
- **Three reassurance bullets** are present (checkmark + line each), copy verbatim from `ScrPlusPackModal`:
  1. **Packs never expire. They roll over month to month.**
  2. **Your $4.99/month Plus plan keeps going, untouched.**
  3. **Used after the included 50 each month — never before.**

  **This is copy parity, not visual polish — blocker if iOS ships without it.** These three lines aren't decoration; they answer the two specific uncertainties a Plus-user-out-of-monthly carries into this modal ("am I being charged twice?" and "what happens to my unused pack assists?") that the spec was explicitly designed to defuse before the buy tap. A modal that takes the money without answering those questions is doing less work than the spec asks. If the iOS `AIPackPurchaseSheet` lacks the bullets entirely, lacks any of the three, or paraphrases the copy in a way that loses the load-bearing words (`never expire`, `untouched`, `after`), file as a release blocker — not a polish backlog item.
- Primary action shows the price: `Buy 100 assists · $19.99` (or selected pack).
- **This is the first surface in the flow where dollar amounts appear.** Confirm no `$` on Memory Detail OMC, no `$` on the stale Reorganize card.

### C5 · Pack purchased

**Set:** Monthly used = `50` · Pack balance = `100`.

Open a fresh memory:

- OMC returns to **idle** (not exhausted) — total assists remaining = 0 monthly + 100 pack.
- Under the `1 ASSIST` pill, a quiet monospaced **`from your pack`** micro-caption appears (telling the user where the next assist comes from).
- Settings → Your AI shows two rows: the monthly counter (50/50 used) AND a **Pack: 100 assists** row.

### C6 · Pack balance only · after month rollover

**Set:** Monthly used = `0` · Pack balance = `100`.

- Settings → Your AI shows both rows: monthly resets to 50/50 available; pack persists at 100.
- Memory Detail's idle OMC is normal — **no `from your pack` caption** when the monthly bucket has capacity (monthly drains first; pack is reserved for when monthly is empty).

---

## Part D · Plus · annual + Founders + Supporter overlay

### D1 · Plus yearly

**Set:** Tier = `Plus · Yearly`.

- Settings → Your AI shows yearly billing label.
- Assist behavior identical to `Plus · Monthly` — same 50/month allowance, same exhaustion treatment.

### D2 · Founders Lifetime

**Set:** Tier = `Founders Lifetime`.

- Settings → Your AI shows Founders status (lifetime, no monthly billing).
- Memory Detail behavior identical to Plus on the AI surfaces.
- Walk A1, A3 equivalents (substituting `Founders` for `Plus · Monthly`) — Founders should never see the Free `STARTER USED` pill; only `MONTHLY USED` if explicitly exhausted (rare given any founders bonus assists).

### D3 · Supporter overlay · pre-tenure (should NOT surface)

**Set:** Tenure section · Mark tenured = OFF · Supporter overlay = `none`.

- **Settings** does not show the Supporter row at all.
- Walk to Upgrade Hub — Supporter doesn't appear.
- Walk to onboarding — Supporter doesn't appear.

### D4 · Supporter · tenured

**Set:** Mark tenured = ON (or set tenure to ≥1mo + ≥10 memories via debug panel).

- **Settings** now reveals a Supporter row.
- Toggle Supporter overlay = `monthly` → row reflects active monthly Supporter state.
- Toggle Supporter overlay = `yearly` → row reflects yearly state.
- Supporter still does not appear in Upgrade Hub or onboarding — it's settings-only by design.

---

## Part E · Lifecycle prompt states

The UpgradePromptSheet has four lifecycle states tracked by `UpgradePromptCoordinator`. The debug panel has a section to scrub these.

### E1 · Not triggered

**Set:** Upgrade prompt section · State = `not-triggered` · Tier = `Free` · Starter used = `0`.

- Idle Memory Detail shows no upgrade prompt overlay.

### E2 · Triggered

**Set:** State = `triggered` (or tap the debug section's **Fire** button after setting the condition).

- The UpgradePromptSheet surfaces in the relevant flow (typically after the user has burned all 3 starters + accumulated ≥5 memories per `UpgradePromptCoordinator` rules).
- It should also be reachable directly from the free OMC exhausted state's `See options →` tap (which routes to Upgrade Hub; the prompt may render as a one-time intercept on the way).

### E3 · Dismissed

**Set:** State = `dismissed`.

- Prompt does not re-trigger.
- Settings → Upgrade Hub remains the entry point.

### E4 · Converted

**Set:** State = `converted-plus` · Tier = `Plus · Monthly`.

- All Plus surfaces active.
- No free CTAs anywhere (the `See options →` / `Get AI title · 1 assist →` paths are gone since the user is now Plus).

---

## Part F · Cross-cutting invariants

After running A–E, sanity-check these globally — they're the system-level rules that shouldn't vary by individual state.

### F1 · No dollar amounts on Memory Detail

Walk the OMC across every tier + state combination from A–E. Confirm:

- No `$` on Memory Detail's idle OMC (any tier).
- No `$` on Memory Detail's exhausted OMC (Free or Plus).
- No `$` on Memory Detail's stale Reorganize card.

Dollar amounts appear **only** on:

- AIPackPurchaseSheet (the pack modal — first reveal).
- Upgrade Hub.
- Founders detail.

### F2 · Cost pill on every active card

Every Organize / Reorganize card in an actionable state (not exhausted, not processing) shows the ochre `1 ASSIST` pill. It's the cost, not a balance.

### F3 · Exhausted state pills always swap

When the OMC or Reorganize card is exhausted:

- `STARTER USED` (free) or `MONTHLY USED` (Plus). Never both, never neither.
- Same pill on first-pass (idle exhausted) and reorganize (stale exhausted) — they must read identically.

### F4 · Capture / storage / search / manual organize never gate

Set Tier = `Free` · Starter used = `3` · Monthly used = `50` · Pack balance = `0`. Verify:

- Recording on phone or watch still works.
- Captured Clips still surfaces.
- Memories still save and store.
- Search still works.
- Manual tap on `Organize with AI` still routes (to Upgrade Hub since Free exhausted) — the surface isn't dead, only the auto path is gated.

**Corollary — exhausted card never mutes into the unreadable.** Per spec the exhausted OMC + Reorganize cards sit at **78–92% opacity** — visibly muted (signaling "not the primary path right now") but never so dim the body copy or the `See options →` / `Get more →` CTA become unreadable. **Every exhausted-state card MUST have a tappable destination** — Upgrade Hub for Free, AIPackPurchaseSheet for Plus. A card that looks tappable but does nothing on tap is a regression to flag immediately.

### F5 · Free users see no pack offers anywhere

Walk Settings, Memory Detail, Project Detail, Bundle Sheet, Upgrade Hub as a Free user (Tier = `Free` · Starter used = `3`):

- No pack tiles, no "Add more assists", no pack copy.
- Free's only path is subscribe (or wait for any refill mechanism — none in MVP).

### F6 · AI color discipline

Walk every AI surface and confirm:

- AI moments (suggestions, sparkles, "App is inferring") render in **AI blue (`#1E5C8E`)** — never ochre, never amber.
- Primary actions (Organize button background, refresh button background) render in **ochre (`#C64A1C`)**.
- `STARTER USED` / `MONTHLY USED` badges render in **warn tint** (warm amber background, warn ink foreground).
- These three colors never mix on a single element.

### F7 · Voice check

Read every CTA, body string, and footer aloud across A–F. Flag any of:

- "Click here" (use "tap" or restate the action).
- "Leverage", "ecosystem", "delight".
- Blame language ("You are offline" → "We couldn't reach…").
- Emoji.
- Exclamation marks anywhere except possibly the Founders "1 of 250 left!" pill.

---

## Part G · Project Assist · starter + paywall (iOS-only addition)

Design's QA script focuses on memory assists; Project Assist has its own starter mechanic that's also worth walking.

### G1 · Starter · free label on Find the thread

**Prereq:** A project with ≥1 memory.
**Set:** Tier = `Free` · Grant flags section · `starterProjectAssistUsed = false`.

Open the project detail screen:

- The **Find the thread** card sub-line reads: *"A short summary across these memories. **Starter · free**."*
- Tap **Run** → consumes the starter (silent first time per spec).
- After running, sub-line flips to *"…1 assist."* on subsequent opens.

### G2 · Second tap → upsell sheet (three paths)

**Set:** Tier = `Free` · `starterProjectAssistUsed = true`.

Tap **Run** on the Find-the-thread card:

- A sheet rises from the bottom titled *"You've used your starter project assist."*
- Three buttons in order:
  1. **Upgrade to Plus · $4.99/mo** (filled, primary)
  2. **Buy an assist pack** (hairline-bordered card, secondary)
  3. **Not now** (ghost, tertiary)
- Tap **Buy an assist pack** → opens AIPackPurchaseSheet.
- Tap **Upgrade to Plus** → opens Upgrade Hub.

### G3 · Plus runs Project Assist (counts against monthly)

**Set:** Tier = `Plus · Monthly` · Monthly used = `0` · `starterProjectAssistUsed = false`.

- Tap **Run** → fires without the upsell.
- After: Monthly used = `1`. Plus assists pay for Project Assist; starter flag is irrelevant for Plus.

---

## Part H · AISuggestionsCard footer label

### H1 · "Accept all" on a fresh pass

**Set:** Tier = `Plus · Monthly` · Monthly used = `0`.

- Create a fresh memory → wait for auto-organize → review card opens.
- Footer: **Re-run · 1 assist** (ochre, left) + **Accept all** (cream pill, right). No row has been individually accepted yet.

### H2 · "Accept remaining" after individual accept

- From H1, tap **Accept** next to the Title row only.
- Footer's right button now reads **Accept remaining**. Other rows still pending.

### H3 · Footer hides when everything committed

- Tap Accept on every row.
- Footer disappears (only re-runs the card if you re-open it). Chip switches to `Organized` (or `Organized · stale` if new clips arrived since).

---

## Part I · Auto-organize · tier gate

### I1 · Free never auto-organizes

**Set:** Tier = `Free` · Pack balance = `3` · Starter used = `0`.

- Create a fresh memory.
- The OMC idle card renders immediately.
- **No "Working…" or "Queued" state appears** — engine gated off for Free. User must tap manually.

### I2 · Plus auto-organizes when budget available

**Set:** Tier = `Plus · Monthly` · Monthly used = `0`.

- Create a fresh memory.
- "Working… / Inquiring with the AI" briefly → review card opens. 1 assist deducted.

### I3 · Plus respects the manual-only threshold

**Set:** Monthly used = `11` · Auto-organize threshold = `40`. Remaining `39 > 40` is `false`.

- Create a fresh memory.
- Auto-organize does **not** fire. OMC stays idle. User must manually tap to spend from the reserve.

### I4 · Plus exhausted entry doesn't stick on Queued

**Set:** Tier = `Plus · Monthly` · Monthly used = `50` · Pack balance = `0`.

- Create a fresh memory.
- Entry saves. OMC switches to exhausted state.
- **No "Queued" badge stays stuck** — pending task is dropped because the engine never runs.

---

## Reset (canvas defaults)

When done testing, restore the baseline — matches Design's HTML `TWEAK_DEFAULTS` exactly so the two scripts converge:

- Tier = `Plus · Monthly`
- Monthly used = `10`
- Pack balance = `0`
- Starter used = `0` *(was `3` in an earlier draft — Design's correction: starter is irrelevant for non-Free tiers, and `3` would represent the depleted-Free state, not a neutral baseline. Setting to `0` so a tier-flip to Free during a later session starts from a clean 3/3.)*
- Project count = `2` (set via debug panel if exposed; otherwise leave projects alone)
- Founders remaining = `203`
- Upgrade prompt state = `not-triggered`
- Tenured = OFF
- Supporter overlay = `none`
- Auto-organize threshold = `0`

Then toggle **Use developer override** OFF if you want to return to real subscription state.

---

## Quick smoke check (5 minutes · pre-TestFlight)

If you only have time for one pass:

1. **Free, 3/3, fresh memory** → idle OMC, ochre `1 ASSIST` pill, no urgency cue.
2. **Free, 1 left, fresh memory** → `1 LEFT · FREE` warn caption under pill.
3. **Free, exhausted, fresh memory** → muted OMC, **`STARTER USED`** badge, body "Your 3 free starter assists are spent…", tap → Upgrade Hub.
4. **Free, exhausted, stale memory** → Reorganize card with **`STARTER USED`** badge, identical copy + route.
5. **Free, exhausted, bundle sheet** → timestamp title pre-fill, "Get AI title · 1 assist →" link → Upgrade Hub.
6. **Plus, exhausted, fresh memory** → muted OMC, **`MONTHLY USED`** badge, body "This month's 50 assists are used. Resets [date]…", tap → AIPackPurchaseSheet.
7. **Plus, exhausted, stale memory** → Reorganize card with **`MONTHLY USED`** badge, identical copy + route.
8. **Plus, monthly=50, pack=100, fresh memory** → idle OMC active again, **`from your pack`** micro-caption under pill.
9. **Free, project assist starter available** → `Starter · free` sub-line on Find the thread.
10. **Free, project assist starter used** → 3-path upsell sheet (Plus / Pack / Not now).
11. **AISuggestionsCard fresh pass** → footer says **Accept all** (not "Accept remaining").
12. **F1 invariant** → no `$` anywhere on Memory Detail across all states.

If all 12 pass, the pricing surfaces shipped 2026-05-27/28 (+ today's idle-exhausted tier-aware refactor) are working.

---

## Coverage map · HTML canvas vs iOS app

Same states; different artifact under test. Both surfaces should pass before TestFlight.

| Part | HTML canvas coverage | iOS app coverage | Notes |
|---|---|---|
| A · Free starter lifecycle | Live ai-live / hub-live + §14 demos | A · same | 1:1 mapping. |
| B · Free settings + upgrade discovery | ai-live + hub-live | B · same | iOS B2 + B3 added Founders sub-states + remaining counter. |
| C · Plus assist lifecycle | ai-live + §15 demos | C · same | C4 is **copy-parity-strict** on the three reassurance bullets — blocker if iOS lacks them. The `Better value` vs `20% off` tag mismatch is a softer call (flag, not block). |
| D · Annual + Founders + Supporter | ai-live, founders-live, supporter-live | D · same | 1:1 mapping. |
| E · Lifecycle prompt states | (limited — prompt overlay not in canvas) | E · same | 1:1 mapping. |
| F · Cross-cutting invariants | All sections | F · same | 1:1 mapping. |
| G · Project Assist | (not in pricing canvas — see Projects canvas) | G · iOS-only | iOS-only addition — Project Assist has its own starter mechanic. |
| H · ASC footer label | (not in pricing canvas — see Memory Detail canvas) | H · iOS-only | iOS-only — covers the "Accept all" vs "Accept remaining" nit. |
| I · Auto-organize tier gate | (engine behavior — not in canvas) | I · iOS-only | iOS-only — verifies the engine doesn't auto-fire for Free and doesn't stick on Queued for exhausted Plus. |
