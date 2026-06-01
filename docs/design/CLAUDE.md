# CLAUDE.md — Himem & shared design jig

This file is read at the start of every chat in this project.

It has two parts:

1. **Universal "jig"** — the working style and design language I want consistent across *all* my projects. If I start a new project (different product, different app), I copy this whole section into that project's CLAUDE.md verbatim.
2. **Himem-specific** — architecture, naming, and feature decisions that only apply here.

Whenever you finish a substantial piece of work, look at the universal section. If we discovered something that should be true *everywhere*, ask me whether to lift it up.

---

# PART 1 · The universal jig

## How I want you to work

- **Ask good questions up front.** Especially about scope (variations, fidelity, what tweaks), audience, and constraints. One round of focused questions beats five rounds of corrections.
- **Push back honestly.** I'd rather be told my design isn't working than ship something safe. When you disagree, say so — once, clearly, with reasoning.
- **Lo-fi first when exploring.** Fidelity is the last step, not the first.
- **No filler content.** Don't pad designs with placeholder sections or copy-as-decoration. Every element earns its place.
- **One source of truth per concept.** Don't duplicate decisions across multiple files; pick the canonical home and link from there.
- **Document what we decide.** Big architectural calls become rules in the design system, not just chat history.

## Voice (applies to all UI copy and to my docs)

- **Quiet over loud.** A small true thing beats a big vague thing.
- **Specific over clever.** "12 seconds" not "a moment."
- **Warm over neutral.** Like a thoughtful friend, not a product.
- **Never blame the user.** "We couldn't reach…" never "You are offline."
- **No emoji** in copy or design specimens. (Brand-typographic exceptions like a stylized `<em>` letterform are not emoji.)
- **Plain English wins.** No "leverage," no "ecosystem," no "delight."

## Design language — Crucible

My products share a design system called **Crucible**. The full source of truth is `Himem Design System.html` in this project; the same tokens and rules apply to anything else I build until I say otherwise.

### Palette (locked)
- **Cream paper `#EFECE5`** — system background.
- **Warm ink `#1A1612`** — type.
- **Ochre `#C64A1C`** — the only chromatic accent. Used for primary actions, brand moments, and audio. Never for warnings, errors, or success.
- **Confirmed green `#3FA877`**, **warn amber `#B87322`**, **danger red `#B8311E`** — semantic only, never decorative.
- **AI blue `#1E5C8E`** — reserved for AI moments (suggestions, inferences). Distinct from any user-action color.

### Type (locked)
- **Source Serif 4** for editorial display — titles, blockquotes, "first true thing on the page."
- **SF Pro** for everything UI.
- Mono only when showing code or tokens.

### Visual rules
- **No gradient backgrounds.** Flat colors and warm shadows only.
- **No rounded-rect-with-left-accent-stripe containers.** Common AI-slop trope; avoid.
- **No emoji in mockups.** If something needs an icon, use a real glyph or a clean SVG.
- **OLED-first on watch.** Pure black, ochre accent. Brand peeks in via accent, not lighting.

### Crucible's accessibility rules (apply everywhere)
- **One surface per concept.** Use modes (view ↔ edit), not separate screens.
- **Peer actions never sit beside primary actions as equal-weight peers.** Destructive options are demoted (corner ✕, smaller pill, or hidden behind a long-press).
- **Derived content never demotes primary media.** Transcripts, captions, extractions are editable; the audio/photo/video stays first-class.
- **Selection = ring; completion = check.** Don't conflate.
- **Status is never color alone.** Always pair with icon + label.
- **Operational vs reflective surfaces get different visual languages.** Memory Box, Memory detail, Projects, Today — these are *reflective*: Source Serif display, cream paper, generous whitespace, audio-as-hero, "first true thing on the page." Captured Clips, sync state, error recovery, append flows — these are *operational*: throughput-optimized, SF Pro everywhere, no editorial type, denser grids, status more prominent than chrome. The workshop floor isn't the gallery; don't bring gallery aesthetics to the workshop floor. **The unit on operational surfaces is whatever the user is moving through the system** — for Captured Clips that's the *session*, not the clip.

## File conventions (per project)

- **Root** holds top-level artifacts (the main design system, the main flow doc, etc.).
- **`crucible/`** holds the design-system source (tokens, components, patterns, guidelines).
- **New patterns** get added to the design system (`Himem Design System.html` or equivalent) *and* documented as a rule in Accessibility or Voice guidelines.
- **No standalone exports, no print siblings.** I export bundles or PDFs myself when I need to hand them off; don't generate `(standalone).html` or `-print.html` files. If a PDF is needed, generate the print-formatted HTML on demand, export it, and delete it after — it goes stale the moment the source changes.

---

# PART 2 · Himem-specific (this project only)

The project is **Himem**, a memory-keeping app:
- **iPhone** — primary surface; landing app, browsing, search, editing, AI inference.
- **Apple Watch** — capture-only.
- **iPad** — Studio (creator surface, planned).

## Architecture decisions (locked)

### Two capture paradigms

HiMem has *two distinct capture modes*. These are properties of **intent**, not platform — a surface can host either, though each surface has a current default.

**Structured capture** — The user *intentionally* creates a Memory. They enter a reflective space. Clips and media flow into a container that already exists or is created on the spot. Memory-oriented from the first tap. *Today: phone direct-voice composer, phone append composer, iPad (when it ships).*

**Ad-hoc capture** — The user catches fragments. Brainstorms. Doesn't organize yet. Session-oriented; structure comes later via consolidation. *Today: watch.* *Future possibilities (don't design for these now): a Studio quick-capture button; a phone widget; a Siri shortcut that fires into the session inbox instead of into a new Memory.*

The boundary isn't watch-vs-phone. It's "I'm capturing inside a container I'm building" vs "I'm catching something to sort out later." Both modes will exist on multiple surfaces over time. Don't bake "watch = ad-hoc" into anything fundamental.

**Captured Clips is the consolidation seam for ad-hoc captures**, regardless of which surface produced them. The user is at an intake conveyor — deciding which of these raw thought streams become actual Memories. Sessions are proto-memories; that's why they're the right primary unit there.

**The consolidation ladder** — three layers, same dance at each scale:

1. **Clips → Session → Memory.** Done on Captured Clips. Bundling a session is consolidation at the smallest scale.
2. **Memories → Project membership.** Manual tagging. Mid-scale grouping.
3. **Project + Memories → Project summary.** Project Assist. High-scale synthesis.

At each layer: messy input → recognition → structure. Brainstorming is messy; reflection creates structure; memory formation is editorial. The product models that explicitly.

**The normal vs edge inversion on Captured Clips.** Most users, most of the time, see a session and bundle it. That's the normal flow. Clip-level tools (delete one, retry transcription, exclude accidental) are *exception handling*, accessed by expanding a session card. Don't put everyone in granular-management mode by default.

### Watch
- Watch is a **capture queue**, not a Memory Box viewer. No browsing on watch.
- **Audio only.** No text, photo, or video composition on watch.
- **No on-device transcription in MVP.** Audio syncs to phone; transcription is v2+.
- Two pages around capture-as-default (Workout-style): **Capture · Pending**. Capture is the left/landing page; Pending sits one swipe right. (Earlier `Latest · Capture · Pending` model retired — see `Watch · spec.md §6`.)
- **Swipe is locked during recording.** Only exits are *Stop & save* or corner ✕.
- **Wrist-off auto-stops and saves.** We never discard work the user walked away from.
- Hard cap: **5 min per recording**, **50 unsynced clips** local storage.
- **Canonical recording UI** (per `Watch · spec.md §2`): big centered timer + live waveform as visual hero; *Stop & save* cream hero pill paired with the *Next* ochre glyph at bottom-right; Cancel as a top-left ✕ corner glyph. The earlier mic-disc-with-counter-inside design is retired.
- **Next clip (MVP)**: bottom-right ochre glyph paired with Stop & save. One tap commits the current clip and starts a new one — counter resets to 0:00, waveform never pauses, haptic pulse confirms. Persistent `Clip N · on a roll` state line under the timer. Each tap = one new Clip (not a new Memory); clips group into one Memory on phone via existing session rules. Min clip 2s (debounced below). 5-min cap is per-clip, not per-roll. Cancel-after-Next discards only the current unfinished clip — earlier clips already committed. Dims to *Sync soon* at 49/50 unsynced. **Same affordance ships on phone direct-voice composer and phone append composer** in MVP — capture rules must be platform-uniform. See `On a roll · spec.md` for cross-platform model and `Watch · spec.md` for the watch-specific layout.

### Phone
- **Today is always the landing page.** No auto-open of inbox.
- Inbox status surfaces as a **banner card pinned at top of Today** when count > 0.
- **Captured Clips** reachable from Settings always, including count of 0.
- **Audio is the source of truth.** Never auto-delete original audio. Transcripts are derivative and regeneratable.
- **iPhone FAB voice = direct memory** (not inbox-routed). Inbox is Watch-only.
- One canonical name: **"Captured Clips"** in app chrome; **"X new from Apple Watch"** only in banner copy.

### Naming
- **Memory Box** is the canonical name for the user's archive (not "bin").
- **Captured Clips** is the inbox of unprocessed Watch audio.
- **Memory** is an Entry; multiple clips can become media on one Memory.
- **Project** is an owner-created container of memories with a name and a goal field ("What are you building toward?"). See `Projects · MVP spec.md` for the full ruleset.

### Projects (locked, see `Projects · MVP spec.md`)
- **Topic ⟷ Project is many-to-many.** Topics and projects are orthogonal axes — no nesting. A memory has one topic and belongs to **0–N projects** (Memory × Project is also many-to-many; matches what `JournalEntry.projects: NSSet?` already supports). A project's topic chips are *derived* from its members.
- **Shape:** name + goal + memories. No cover, no date range, no archive state in MVP.
- **Project Assist** is the single AI action on a project. Button label: **Find the thread**. One assist per pass produces **two outputs**: (1) a project summary — one Honest-Label paragraph in second-person voice; (2) a short list of **suggested memories** from elsewhere in the library that may belong here. Suggestions are proposals — nothing auto-adds. ("Coalesce" was the working internal name; dropped — one vocabulary.)
- **Deliberately not in scope:** "currents," "open loops," "important memories," "what's becoming." All violate Honest Label (interpretive, value-laden, surveillant). The paragraph captures the thread; we don't fragment it. Studio (post-MVP) can structure further.
- **What it reads:** for in-project memories — title, topic, date, AI summary. For candidate memories (prefiltered top 20–30 from local match: topics + mentions + dates + similar phrases) — same fields plus one-line excerpt. *Never raw transcripts.* Keeps cost flat; Studio is the raw-fragment tier.
- **Cost:** 1 assist per pass for both outputs combined, regardless of project size. Refresh = 1 assist. Accept / edit / dismiss = 0.
- **Trigger:** manual only, even on Plus. No auto-run — new memories arrive often and rewriting the paragraph every time wastes assists.
- **Threshold:** ≥ 1 memory before Project Assist activates. With one memory the "summary" is closer to a paraphrase than a synthesis — fine; the user gets back what they asked for. Zero memories has nothing to summarize. One is the only structurally defensible threshold; any higher number is arbitrary.
- **Tier:** Plus or Founders required *beyond the first run*. Free gets **1 active project + 1 starter Project Assist run** (separate from the 3 starter memory assists). The starter run is **loud, not silent** — the user knows they're spending their one free pass. A small adjacent *"Starter · free"* label sits on the Find the thread button on first use, replaced by *"1 assist"* on subsequent passes (which fire the upsell for free users). *Decision reversed from the original silent-starter design (May 27 2026): silent led to "I wouldn't have used it on that!" regret — see `Open work · pricing flow.md` §1.* Studio (post-MVP) reads raw fragments + cross-project + structured output + export.
- **AI blue, always.** AI Summary, the "Organized · review" card, sparkle glyph, confidence chips, suggestion "why" lines — all `#1E5C8E`, never ochre or amber. Shipping iOS code uses ochre/amber across multiple AI surfaces; this is a **uniform sweep, separate PR before TestFlight**, not a footnote on the Projects spec. Half-applied color rules are worse than uniformly-wrong ones. *(The old list-level "App is inferring" prompt is retired — see `AI Organize · spec.md §8.1`. Review is Memory-Detail-only.)*

### Notifications (locked, May 2026 — revised)

**Two independent channels. One pending notification per channel.** Each channel manages its own `UNNotificationRequest`; they can coexist. Cross-cutting rules at the bottom.

#### Channel A · Captured Clips (default on)
- One pending notification at a time, representing the current inbox state.
- **Always passive — never buzzes, never lights up the screen.** Uses `UNNotificationInterruptionLevel.passive` so the notification lands silently in Notification Center / on the lock screen but doesn't vibrate, doesn't fire a banner, doesn't wake the device. The badge does the reminder work; the notification is just a tappable handle to jump to Captured Clips.
- **App in foreground** → no notification posted at all; the badge alone reflects state. The user is already looking at the app — no interruption surface needed.
- **App backgrounded or locked, first clip into an empty inbox** → post the passive notification.
- **Subsequent arrivals while pending** → update the existing notification in place. Same `UNNotificationRequest` identifier, body re-rendered with current count ("4 voice clips waiting" → "5 voice clips waiting"), badge synced. Still passive.
- **User clears the inbox** (review in app, tap notification, Mute action) → notification removed, badge cleared.
- **No arbitrary caps.** No daily limit, no per-clip fire count, no automatic cooldown. Passive + one-pending + in-place-updates is the entire noise budget; everything that would normally need a cap is solved by never buzzing.
- **Stale (>24h) is obsolete as a separate trigger** — the existing pending passive notification already represents the unreviewed inbox.

#### Channel B · Daily nudge (user opt-in)
- **Trigger:** a user-chosen time-of-day, picked in Settings (`Settings → Notifications → Nudge time`). No default time imposed — the user enables the toggle AND picks a time.
- **Suppression:** fires only if the user hasn't captured anything in the 24h window ending at the chosen time. A capture inside the window cancels the next nudge. The window anchor is the user-chosen time, not midnight — picking 8 PM gives 8 PM-to-8 PM semantics; picking midnight gives the legacy calendar-day semantics for users who want them. One mechanism, user-controlled rollover.
- **Cancel-and-reschedule on every capture.** A watch clip arrival OR a phone memory creation cancels the pending nudge and re-schedules the next one at the next chosen-time tick (today if it hasn't passed yet, tomorrow if it has). Always a concrete fire date — no "wait for the next refresh to handle tomorrow" reliance.
- **Sound + banner on fire** (not passive — this is an active reminder). One `UNCalendarNotificationTrigger` per scheduled fire. Tap routes to Today.
- **Copy is honest-label.** *"Anything to remember from today?"* (shipped). Never *"Come back!"* or *"We miss you!"*
- **User opt-in.** Disabled by default. Surfaced in onboarding (see below) and in Settings.
- **No badge.** Channel A owns the app icon badge.

*(The earlier spec described a 24h-baseline + 7d weekly re-buzz cadence with body re-rendering between milestones. That model never shipped; the daily-nudge-at-user-chosen-time model documented above is what's in `NotificationService.refreshDailyNudge` + `DailyNudgePolicy.nextFireDate` and matches the Settings UI Tom is shipping. Spec revised 2026-06-01 to match reality.)*

#### Onboarding · notification setup
- A single "Notifications" permission prompt during onboarding asks for system-level authorization. Channel A (Captured Clips arrivals) is implicitly active once permission is granted — it's a first-class event the user opted in to by installing HiMem with a watch.
- Channel B (Daily nudge) stays off by default and is enabled in `Settings → Notifications` post-onboarding, where the user also picks the chosen time. No need to surface it during the initial prompt — most users don't decide on a quiet-day reminder during install, and the Settings location keeps the onboarding flow lean.
- The Settings toggle + time picker is the single source of truth for Channel B's enrollment.

#### Cross-cutting (both channels)
- **Quiet hours 10pm–7am local.** Channel A: first-of-stretch push defers to 7am; arrivals/updates during quiet hours update the deferred payload silently and fire once at 7am with current state. Channel B: the user picks a time, so the responsibility for not scheduling inside quiet hours is theirs; the scheduler honors whatever they pick. (A daily nudge at 2 AM is the user's call.)
- *Snooze 4h* and *Mute for today* are inline `UNNotificationAction` controls on Channel A. Snooze suppresses Channel A for 4 hours; Mute suppresses through local midnight. Channel B fires at the user's chosen time and is suppressed naturally by capturing; explicit inline actions aren't shipped for it.
- Swipe-to-dismiss-silences is **NOT implementable** on iOS; don't spec it.
- Foreground app: no push for Channel A (badge only). Channel B's chosen-time fire is allowed in foreground — the user picked the time and expects the reminder.
- Tap notification → opens the relevant surface (A → Captured Clips; B → Today).
- Long-press → Manage → jumps to iOS Settings for that channel.
- Focus modes respected via each channel — user can mute one without the other.

- **AI Organize (locked, see `AI Organize · spec.md` for full rules)**
- **AI is an organizational helper, not the product.** The summary's job is to give a memory a name its author will recognize six months later.
- **The Honest Label principle.** Summary contains nothing the clips don't contain. Length matches substance. Voice is descriptive, not interpretive. *Describe, don't interpret.*
- **Voice:** stored with "you" baked in (e.g. *"You're exploring…"*). Owner sees this verbatim. On share/export, a simple `replacingOccurrences` swaps "you/You" for the user's first name. **No third-person personal pronouns anywhere** (no he/she/they/her/his/them) — other people always referenced by name. Present for thinking, past for events.
- **One assist = one whole-memory pass.** Accept / edit / skip / manual edit / failed pass all cost 0 assists. Refresh after new clips = 1 assist.
- **Exhausted state splits by tier.** Plus users who run out of assists for the month can purchase an assist pack without changing their subscription — the pack is additive, never expires. Free users hitting exhaustion are routed to the subscription paywall (Upgrade Hub). Two destinations from one shared exhausted-state surface. See `Open work · pricing flow.md` §2 for the modal spec — design-complete, ship-blocked on IAP setup (Paid Apps Agreement / tax / banking).
- **v1 sees text + audio only.** Photos and videos referenced by metadata. v1.5+: optional 3-assist tier adds visual analysis.
- **Provenance** lives in the Organized chip, never on the field.

### Power and wake lock (locked)
- **HiMem only prevents sleep during intentional capture.** Recording in progress, photo composer open, video composer active → wake lock on. Browsing, viewing, listening back, editing → wake lock off. The system idle timer is a trust contract we don't override casually.

### Out of MVP (v2+)
- On-device transcription on the watch.
- AI-suggested titles and topic chips (both depend on transcripts).
- iPad Studio.

## Current Himem files

### Design system (the source of truth — every page should match this)

- `Himem Design System.html` — Crucible bundle: foundations, components, patterns, voice + accessibility guidelines. Stitched from `crucible/*.jsx` by hand; if `crucible/` changes, restitch.
- `crucible/` — design-system source (eleven files: `tokens.js`, `_shared.js`, `primitives.jsx`, `components.jsx`, `foundations.jsx`, `components-board.jsx`, `complex.jsx`, `patterns.jsx`, `guidelines.jsx`, `ios-frame.jsx`, `design-canvas.jsx`).

### Shared primitives (every Himem page loads these)

- `crucible-primitives.jsx` — **canonical**. The `PX` token set (`#C64A1C` ochre, cream `#EFECE5`, AI blue `#1E5C8E`), plus `PhoneScreen` and `Sheet`. Every page that mocks Himem screens reads from here.
- `design-canvas.jsx` — pan/zoom canvas wrapper. `<DesignCanvas><DCSection><DCArtboard>…`.
- `ios-frame.jsx` — iOS 26 (Liquid Glass) device frame.
- `tweaks-panel.jsx` — Tweaks shell + form controls.

### Specs (locked rules — defer to these when in doubt)

- `Watch · spec.md` — watch surface (capture, complications, pending, on-a-roll watch-side).
- `Projects · MVP spec.md` — projects + Project Assist.
- `On a roll · spec.md` — cross-platform Next behavior (watch sections superseded by `Watch · spec.md §3`; phone sections canonical).
- `Captured Clips · session-first · spec.md` — Captured Clips v2 (one surface, cards expand in place, no drill-in).
- `AI Organize · spec.md` — Honest Label, prompt rules, QA rubric.
- This file (`CLAUDE.md`) — universal jig + Himem architecture locks.

### Surface canvases (each is a `Himem · X.html` + accompanying `screens-*.jsx`)

| Canvas | Screens module(s) |
|---|---|
| `Himem · Flow.html` — full Watch → Memory flow + notification spec | inline |
| `Himem · Watch.html` — Watch design canvas | inline |
| `Himem · Voice Composer.html` — phone direct-voice + append composers with on-a-roll parity | `screens-voice-composer.jsx` |
| `Himem · Memory Detail.html` — Memory detail view (clip headers carry date+time+location; mentions promoted above Organized review) | `screens-memory-detail.jsx` |
| `Himem · Captured Clips.html` — v0, original clip-first design (superseded; kept as reference) | inline |
| `Himem · Captured Clips (session-first).html` — **v1 canonical**, per session-first spec | `screens-captured-clips-sessions.jsx` |
| `Himem · Projects.html` — projects MVP canvas | `screens-projects.jsx` (shared bits), `screens-projects-cards.jsx` (cards), `screens-projects-views.jsx` (5 screen views), `screens-projects-spec.jsx` (annotated dev row spec) |
| `Himem · Pricing.html` — 15 pricing surfaces, tier-aware tweaks | `pricing-screens-settings.jsx`, `pricing-screens-modals.jsx`, `pricing-screens-tier-states.jsx`, `pricing-screens-memory-detail.jsx` |
| `Himem · Launch.html` / `Onboarding.html` / `Search.html` / `Location.html` / `Append.html` — supporting phone flows | inline |
| `Himem Studio · iPad Wireframes.html` — iPad Studio (lo-fi only) | `studio/wireframes.jsx` |
| `Himem · App Store.html` — App Store marketing frames (6 portrait frames) | `frames/appstore-frames.jsx` |

### Auxiliary files

- `scraps/` — sketches, screenshots, notes.
- `uploads/` — reference materials I've dropped in (screenshots, specs, etc.).

### Rules of thumb for handoff

- **Token set:** `crucible-primitives.jsx` `PX` object is authoritative. Anything else (e.g. inline tokens in App Store frames) should mirror it.
- **Design-canvas wrapper:** root `design-canvas.jsx` is the canonical canvas every surface canvas loads.
- **No `tokens.js` at root.** It existed pre-Crucible with the wrong accent (`#F26A1F`) and is gone. The `crucible/tokens.js` mentioned inside the design-system bundle is a different file.

## Open todos (May 2026 handoff)

**Pricing flow + free tier state map** — handoff doc at `Open work · pricing flow.md`. Builds a decision tree of paywall moments and a state map of free-tier surfaces. Two locked decisions (May 27): starter Project Assist is loud not silent; Plus users out of assists can buy packs without changing subscription. Several specced gaps to close. Read the handoff doc first.

Phone-audit work that hasn't shipped yet:
- Audit shipped iOS screens against current Crucible spec.
- Identify gaps for v1 release.
- Build phone v1 screen flow on the design canvas.

Pick one when ready, or take a fresh direction.
