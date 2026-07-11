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
- **Recognition over generation; lead with signal, never bury the rest (locked July 4 2026).** The AI's job is to *reduce the cost of starting*, not to organize for the user. Present **recognizable proposals**, never a blank prompt — approving a cluster is far cheaper than creating one from scratch. But a proposal is only calming if it's trustworthy: a confident *wrong* proposal is worse than none (it converts recognition back into detect-and-undo). So **under-suggest** — Honest-Label discipline applies to every AI proposal. And **surface the signal without hiding the rest**: a filter the user trusts is *additive* ("here's what stood out"), a filter they fear is *subtractive* ("I decided what you don't need to see"). The escape hatch ("nothing's lost, it can wait") is the precondition that makes signal-forward feel calm instead of controlling. Applies to every AI surface — Sort, draft-organize, find-the-thread. *Origin: the Captured Clips workbench / Sort resolution — see `Captured Clips · session-first · spec.md` v3.*

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
- **One affordance vocabulary, three signals, each with one meaning (locked June 8 2026).** On any given surface, an interactive element's *look* must map to exactly one job: **(1) a real button** (filled or clearly bordered, ≥44px) is *the action* — there is one primary action per moment and it is the loudest interactive thing; **(2) a solid filled pill** with a small leading dot is *managed content* (topics, mentions) — tap to manage; **(3) a quiet label** (icon + text, no border, no pill) is *status/information* — it never looks tappable. **Status is never dressed as a button**, and **the real action is never disguised as a text link.** Reserve **dashed borders for "add / incomplete / provisional" only** (e.g. `+ Edit`, a flagged *New* topic) — never for status. *Origin: the Memory-detail "Draft organized" cluster shipped three weak fragments (dashed status pill + hollow-dot label + underlined link) that collided with the dashed `+ Edit` button; resolved by demoting status to a label and promoting review to one full-width button.*
- **44px hit-target floor, no exceptions.** Every tappable element — chips, mentions, add/edit affordances, glyph buttons — clears 44px (visible ≥38px with separating gap is acceptable; smaller is not). Reflective surfaces especially: the interactive layer should be *more* generous than the read-only content, never less. A chip you must aim for is a bug.
- **Button & action colour code — colour maps to who acts and what's destroyed (revised June 8 2026, supersedes the morning "all buttons ochre" lock).** The user learns three button meanings once: **ochre button = *you* act** (commit, save, keep), **blue button = invoke *AI*** (organize, reorganize, run, review a draft), **red = destruction (the full-width Delete button — see the deletion rule below).** Blue does double duty — an AI *button* (filled/bordered) and an inline *link* or *status signal* (bare text / quiet label) — but **form** keeps them distinct, so there's no ambiguity. Specifics: **(a)** every real button is ochre **or** blue by that rule; rank is carried by fill+width within each colour — *primary* filled full-width (one per surface, the loudest thing), *secondary* hairline-bordered full-width, *tertiary* bordered pill (filled only when it's the sole action of its card). So `Review draft` / `Reorganize` / `Run` are **blue** buttons (they invoke AI); `Keep this version` / `Save` / `Done` are **ochre** (you commit). The AI **sparkle** glyph belongs on blue AI buttons (reinforces the meaning) and is **dropped from ochre user buttons** (redundant there). **Blue AI buttons name the AI** — a verb that names it (the promise) + a **trailing** sparkle (the marker), sparkle *after* the label: `Organize with AI ✦`, `Reorganize with AI ✦`, `Transcribe with AI ✦`, or a named feature (`Find the thread ✦`). Two signals, one honest meaning — the user always knows when work is being handed to the AI. Never ghost an AI button low-contrast (it shouldn't read as disabled); it stays a legible blue. **Each AI surface owns ONE named action; never mint a generic synonym.** A *memory*'s AI re-run is **Reorganize with AI ✦** (re-runs the organize pass — title/summary). A *project*'s AI action is **Find the thread ✦**, and its re-run is **Find the thread again ✦** — the named feature, run and re-run, one verb for that surface. **Never label either "Regenerate"** (generic LLM-product slop) and never borrow "Reorganize" onto a project (it's the memory verb, different semantics — projects *synthesize across*, they don't *organize*). **(b)** bare-text actions exist in **one place only — the nav/sheet top bar** (`Cancel` plain ink left, `Done`/`Save` ochre right); everywhere else a text-link is **blue** (`Review ›`, `Retry transcription`, edit links) and anything needing more weight becomes a button, not a louder link. **(c)** destruction is a **full-width Delete button at the bottom of an opened item** (memory, clip, project), below all content — danger red, hairline-bordered, ≥50px. **Swipe-to-delete is retired everywhere (June 12 2026):** the user opens the item and scrolls past everything to reach Delete, and that scroll *is* the deliberation, so there is **no confirm dialog**. Recoverability (Recently Deleted, 30 days) is the safety net. One affordance, one place, every object type. **Trash** = deletes the memory/clip; **Recycle/Remove from project** = a parallel full-width button that removes a memory from a project (the memory survives). Never a floating circle, never a list-row swipe, never a toolbar trash. **(d)** AI status (Draft organized, Summary eyebrow) is blue but a **quiet label, never a button**. **(e)** **toggle/switch on-state is ochre, never iOS green** — green is semantic-only (confirmed/success); an enabled setting is a user state, not a success. Canonical reference: `HiMem · Buttons & Actions.html`.
- **Touch-target floor is two-tier (June 8 2026).** 44px is the floor for *interactive-management* contexts (Memory-detail topic row, manage sheets — where the chip is the thing you aim at). In *dense/scan* contexts (memory cards, filter bars) a chip may be **28px visible / 38px tap zone with a guaranteed separating gap**. Below 38px is always a bug. Scope-selectors and non-topic pills (e.g. the **"All" filter**) are **dotless** — the leading dot means "a topic with a palette colour," and a scope selector isn't a topic.
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

### Memory perishability (locked first principle, June 17 2026)

**Memories are perishable. Context-triggered memories are even more perishable. Never make the user carry a memory while navigating.**

This is the product's reason to exist, stated as a design constraint — not a UI preference. A thought worth keeping decays by the second, and the decay accelerates when the thing that triggered it (a place, a photo, a conversation, a passing feeling) is still present and about to pass. If capture costs the user even a few seconds of *navigation* — find the app, pick a mode, choose a destination, name a thing — we have asked them to **hold the memory in working memory while they operate the UI**, and that is precisely when it evaporates. The interface is competing with the very thing it's trying to save.

Consequences that bind design everywhere:
- **Capture is always one action from anywhere it could plausibly be wanted.** The Watch landing page *is* capture; the phone FAB is direct-to-record; "on a roll" keeps the next clip one tap away. Never gate capture behind a mode-picker, a destination prompt, or a naming step — structure is decided *later*, on a reflective surface, never at the moment of catching.
- **Defer every decision that isn't "record now."** Title, topic, project membership, which-memory-this-joins — all of it waits. The capture moment asks the user for nothing but the thought itself. (This is the spine under the two-capture-paradigms model and the Captured-Clips consolidation seam below.)
- **Never interrupt a capture to ask a question.** No "where should this go?", no permission prompt mid-record, no "are you sure?". Wrist-off auto-saves; the app never discards a thought the user walked away from.
- **Navigation is the enemy of the trigger.** Any flow that requires the user to remember *what they were about to capture* while tapping through screens has already failed. When in doubt, capture first and sort later — the consolidation ladder exists exactly so that "catch it now" never has to mean "file it now."

When a design decision trades a few seconds of capture friction for tidier structure, perishability wins. Always.

### Two capture paradigms

HiMem has *two distinct capture modes*. These are properties of **intent**, not platform — a surface can host either, though each surface has a current default.

**Structured capture** — The user *intentionally* creates a Memory. They enter a reflective space. Clips and media flow into a container that already exists or is created on the spot. Memory-oriented from the first tap. *Today: phone direct-voice composer, phone append composer, iPad (when it ships).*

**Ad-hoc capture** — The user catches fragments. Brainstorms. Doesn't organize yet. Session-oriented; structure comes later via consolidation. *Today: watch, **and the phone Clips-tab FAB** (added July 10 2026 — see the context-aware FAB rule below).* *Future possibilities (don't design for these now): a Studio quick-capture button; a phone widget; a Siri shortcut that fires into the session inbox instead of into a new Memory.*

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
- **Three primary objects: Clips · Memories · Projects** (Evidence · Context · Intent), a three-tab segmented control in the capture→shape→build order. *(Decision July 8 2026 — see `HiMem · the shaping model.md` § "The name question — resolved" and `HiMem · evidence and context.md`.)*
- **Cold launch lands on Memories** (reverse-chronological, grouped by the day each memory happened) — what you open HiMem *for*. The last-used tab is remembered **only while the app stays alive** (open *into* Clips after a capture session, return to it minutes later; a cold start is always Memories).
- **Clips is the first-class evidence surface** (retires the standalone "Captured Clips" window). Default view = AI suggestions + everything not-yet-connected (incl. clips still downloading from the phone), no architecture word exposed; reveals to All / Voice / Photos / Notes. **Capture returns to Clips.** Tapping a clip opens the clip as the primary object (transcript · media · date · **Referenced in: [memories]** · Projects).
- **New-arrival status is a dot on the Clips tab, not a banner** (banner retired July 10 2026 — it predated the three-tab model, when Captured Clips was a hidden window; now Clips is an always-visible tab, so a banner pointing at it is redundant chrome on the reflective Memories surface). The dot answers *"should I look?"* — **presence, not a count** (a number implies an obligation to zero-out, the guilt-inbox we reject). The dot represents **new, unseen arrivals** and **clears when the user opens Clips** — it does *not* track all-unplaced (that work is carried by the persistent default **New** filter, which still opens to the unshaped clips after the dot clears). Badge/filter split: badge = *"something arrived"* (transient), New filter = *"what's still unshaped"* (persistent).
- **App-icon badge: none.** iOS only supports a numeric app-icon badge, and a number reintroduces counting — so HiMem shows **no app-icon number**. The passive Channel A notification already carries "something arrived" externally; the in-app dot handles the rest. (This resolves the previously-"under review" badge question: dot in-app, nothing on the home-screen icon.)
- **Active Navigation Tap (status sheet) — required for v1, not optional.** First tap on a tab navigates; tapping the *active* tab scrolls to top if scrolled, and — when already at top — presents a **status sheet** for that section. On Clips the sheet shows *new arrivals by source (Watch / iPhone / Siri), what's processing (downloading / organizing), and what's available to shape (loose count)* plus quick filter shortcuts — **no census/vanity counts** (no "247 referenced"; the sheet is *what needs me*, not *how much I have*). This is a required build; what's optional is only the *user's* discovery of it — status also lives in the dot + default filter, so the app works for someone who never taps twice. See `Kingfisher · North Star.md` · "Calm by default, density on demand."
- **Audio is the source of truth.** Never auto-delete original audio. Transcripts are derivative and regeneratable. *(Where that audio physically lives → see **Media storage** below.)*
- **The FAB is context-aware — the active tab declares capture intent (locked July 10 2026, supersedes "iPhone FAB = direct memory; inbox Watch-only").** On **Clips**, + captures an **ad-hoc clip to the bench and stays on Clips** — the new clip drops into the list already in view (recognition, *no navigation*). On **Memories**, + opens the structured memory composer. On **Projects**, + acts on the unit of the surface you're on: at the **project list** level it creates a **new project** (name + goal sheet — the same sheet the "+ New project" list row opens, a second path to one sheet, not a new capability); **inside a project** it creates a **memory in that project** (in-context capture). The generalizing rule: **+ creates one of whatever you're looking at a collection of** — Clips list → a clip, Memories list → a memory, Projects list → a project, inside a project → a memory-in-that-project. The Projects-list + is the one place + is *not* capturing a thought (it makes an empty container, not a caught thought) — that's fine because no thought is in flight while browsing the project list; CC must **not** force it into the capture pipeline. Rationale: the tab is a *visible, persistent* declaration of headspace, so reading it is not "magic" — teleporting the user to another tab after they capture *is*. Both destinations honor capture-now-decide-later, and nothing is lost across them (bench clips promote to memories; memories accept more clips), so the escape hatch makes context-sensitivity safe. The old lock ("iPhone FAB = direct memory, inbox Watch-only") was made when Clips was a *hidden window* with no tab to stand on; now that Clips is a first-class peer surface, phone ad-hoc capture has a natural home — this catches the lock up to the *intent-is-not-platform* principle, it doesn't break it. **Corollary: the bench is no longer Watch-only** — clips arrive from the Watch *and* the phone Clips FAB, so bench headers/status must be **source-agnostic** ("N new clips", never "N from your Watch"); source is per-clip metadata (a small Watch/phone glyph on the card), never the headline.
- One canonical name: **"Captured Clips"** in app chrome. (The old "X new from Apple Watch" banner copy is retired — arrival status is now the Clips-tab dot; see the arrival-status bullet above.)

### Data custody (locked principle, June 2026)

**No user content ever enters HiMem's custody. Everything authoritative lives in the user's own iCloud; HiMem-the-company runs no server that holds user data and keeps only a local, rebuildable index for speed.** This is the spine the whole product hangs off — "your journal is part of your iCloud, like your photos and contacts," not "your journal is on this phone" and never "your journal is on our servers."

**Where everything lives:**
- **Structured data** — memories, transcripts, topics, mentions, projects — lives in the user's **CloudKit _private_ database**. This is the user's iCloud, Apple-hosted, per-Apple-ID, **developer-unreadable**. It syncs across the user's devices and survives reinstall, but it is *never* in our custody — the private DB is the user's, not ours. (Contrast: CloudKit _public_ DB / any HiMem server = our custody. We use neither for user content.)
- **Media blobs** — voice, photo, video — live in the user's **iCloud Files** (a HiMem container in iCloud Drive, user-visible).
- **The index we keep** — the on-device **Core Data** store — is a *derived, rebuildable cache* for instant search and the Memories list (see `Memories list · spec.md §9`). It is the only thing "HiMem keeps," it contains nothing authoritative, and it can be reconstructed from the user's iCloud. This is the "all we keep are indices" rule, precisely stated.

**Say it accurately.** "No user data leaves the device" is false and we won't claim it — cross-device sync (phone → Studio) *requires* data to leave the device. The true, stronger claim: **data leaves the device only into the user's own iCloud, never into HiMem's custody.** Apple hosts; the user owns; HiMem holds only an index.

**Why this is buildable now, not a rebuild:** there is no backend holding user content to tear down, because there isn't one. CloudKit private DB already syncs and survives reinstall today; the work is (a) moving media into the iCloud Files container and (b) keeping the structured data in the *private* database (Option A — see chat June 2026). Option B (serialize transcripts/projects as files too, drop CloudKit) was rejected: no privacy gain over A — the private DB was never ours — at the cost of CloudKit's sync + query engine.

**Resolves a conflict with `docs/design/Storage architecture · CLAUDE.md` (flagged June 19 2026).** That doc's "v2 direction" section described retiring CloudKit and making every memory a file as a *locked* next step — i.e. Option B — and justified it as "closing the remaining custody surface." **That justification is false and the locked status is killed:** there is no remaining custody surface to close, because the CloudKit private DB was never in our custody (the whole point of Option A). Option A is the single locked storage answer for v1 and beyond. The files-as-source-of-truth idea survives **only** as an explicitly *not-locked* future bet, and **not on privacy grounds** — its real (and only) value is tangible ownership + portability ("a journal the user can open in Files.app and take elsewhere"), a legibility/marketing direction that trades away CloudKit's sync + query engine and has not been costed. CC action: demote the storage doc's v2 section from "locked" to "candidate, portability-not-privacy," so two docs don't both claim "locked" on opposite verdicts.

---

#### Media specifics

**All HiMem-created media lives in the user's iCloud Files, not the app sandbox.** This fixes two real bugs in the current build:

1. **Cross-device availability.** Before: audio recorded/received on the phone never synced onward — unavailable on other devices (e.g. iPad **Studio**). Now: media in the user's iCloud is reachable from every device they're signed into. Studio reads the same voice files the phone captured.
2. **Survives delete + reinstall.** Before: audio lived in the app's storage and was **destroyed when the user deleted the app**. Now: the media is the user's, in their iCloud — deleting the app no longer deletes their recordings, and reinstall restores them (what the Reinstall → *"Bringing your memories back from iCloud"* flow now genuinely delivers, audio included).

**Reference integrity** between the two iCloud stores is the standing architectural concern: a memory's private-DB metadata points at a media file in user-visible, user-mutable iCloud Files.

**Consequences worth holding onto (mostly backend; design-light per current call):**
- **Storage is the user's iCloud quota, not ours.** Economically good (we don't pay to store anything); but a user whose iCloud is full can hit a capture/sync ceiling — a calm "iCloud is full" path is a candidate state, not yet designed.
- **Eviction.** iCloud can purge a local copy to save space; playback may need a download-on-demand (a brief "fetching" state on a clip). Not yet designed; flag if it surfaces.
- **No design change required right now** beyond retiring the old "create a HiMem folder/album in Photos?" implementation prompt (HiMem no longer writes into the Photos library; media goes to its iCloud Files container instead).

**User-mutable files (locked):** because the media is genuinely the user's — visible in the Files app — they can move, rename, or delete it out from under HiMem, and **there is nothing we can or should do to prevent that.** That's the honest cost of the files being theirs, and we accept it. Consequences:
- **The private DB stays authoritative for metadata; the file is authoritative for the bytes.** If the bytes are gone, the memory still exists (title, transcript, topics all live in the user's private CloudKit DB) — only playback of the original is lost.
- **A missing file is a calm, honest state, never an error or a blame.** The clip shows something like *"This recording was moved or deleted"* (Crucible voice: never "you deleted this"). The transcript and everything derived from it remain fully intact and usable.
- **The transcript is what makes the loss survivable.** Voice recordings are transcribed (and, later, video too) — so even with the source media gone, the *words* are still in the memory: searchable, organizable, readable. We lose the original recording, never the substance. This is precisely why we can afford to let the files be the user's.
- **We don't nag, lock, hide, or duplicate-to-protect.** No "don't touch this folder" warnings, no shadow copy in the sandbox to defeat the point. The transcript being derivative and regeneratable-from-nothing is exactly why losing an original is survivable.

**Durability across uninstall/reinstall (locked):** once media lives in the **public-document-scope ubiquity container** (`NSUbiquitousContainerIsDocumentScopePublic = YES` — the same flag that surfaces the HiMem folder in Files), the bytes have a lifecycle independent of HiMem's install state. Same bundle ID = same container, so uninstall → reinstall (or a brand-new phone signed into the same iCloud) reconnects to the existing folder and everything returns — bytes from iCloud Files, metadata from CloudKit (which already survives reinstall today). The relationship becomes *"your journal is part of your iCloud,"* not *"your journal is on this phone."* The **only** ways media is actually lost: (1) the user deletes the files themselves from Files.app, (2) they sign out of / close their Apple account, (3) they exceed their iCloud quota — which blocks *new* writes, it doesn't destroy existing ones.
- **Migration caveat.** Audio captured *before* this ships (today's `Documents/VoiceEntries/`) is still sandbox-bound and dies with uninstall **until the migration runs on that device.** Durability is a post-migration property; the migration is what earns the resilience story above.

### Naming
- **Memory Box** is the canonical name for the user's archive (not "bin").
- **Captured Clips** is the inbox of unprocessed Watch audio.
- **Memory** is an Entry; a memory references 1–N clips, and **one clip can be evidence in many memories** (Clip↔Memory is many-to-many; the edge carries an optional annotation — "why this matters here"). A clip is *evidence*, stored once; memories/titles/summaries/topics/annotations are *context*. See `HiMem · evidence and context.md` (locked v1 ontology).
- **Project** is an owner-created container of memories with a name and a goal field ("What are you building toward?"). See `Projects · MVP spec.md` for the full ruleset.

### Projects (locked, see `Projects · MVP spec.md`)

> **Pricing:** Project Assist is the **Connect capability — a Plus feature** (the layer that makes projects *grow themselves*). Free builds up to **3 projects by hand**; the growing-itself intelligence is Plus. Full model: `Pricing model · Capture-Connect-Create.md`. The retired assist-quota canvas is in `archive/assist-model/`. The non-pricing rules here (derived topics, Honest-Label, what Project Assist reads, thresholds) remain binding.
- **Topic ⟷ Project is many-to-many.** Topics and projects are orthogonal axes — no nesting. A memory has one topic and belongs to **0–N projects** (Memory × Project is also many-to-many; matches what `JournalEntry.projects: NSSet?` already supports). A project's topic chips are *derived* from its members.
- **Shape:** name + goal + memories. No cover, no date range, no archive state in MVP.
- **Project Assist** is the single AI action on a project. Button label: **Find the thread**. One pass produces **two outputs**: (1) a project summary — one Honest-Label paragraph in second-person voice; (2) a short list of **suggested memories** from elsewhere in the library that may belong here. Suggestions are proposals — nothing auto-adds. ("Coalesce" was the working internal name; dropped — one vocabulary.)
- **Deliberately not in scope:** "currents," "open loops," "important memories," "what's becoming." All violate Honest Label (interpretive, value-laden, surveillant). The paragraph captures the thread; we don't fragment it. Studio (post-MVP) can structure further.
- **What it reads:** for in-project memories — title, topic, date, AI summary. For candidate memories (prefiltered top 20–30 from local match: topics + mentions + dates + similar phrases) — same fields plus one-line excerpt. *Never raw transcripts.* Keeps the payload bounded; Studio is the raw-fragment tier.
- **Trigger:** manual only, even on Plus. The owner decides when to pull the thread — auto-rewriting the paragraph on every new memory would be noise, not help.
- **Threshold:** ≥ 1 memory before Project Assist activates. With one memory the "summary" is closer to a paraphrase than a synthesis — fine; the user gets back what they asked for. Zero memories has nothing to summarize. One is the only structurally defensible threshold; any higher number is arbitrary.
- **Tier:** Project Assist is a **Plus capability** — the Connect layer. Free gets **3 active projects**, built and managed by hand; Plus gets unlimited projects plus the growing-itself intelligence (related memories, suggested membership, find-the-thread synthesis, cross-project). A one-time Free *taste* of Find the thread, if offered, is a trial flag decided in the pricing doc — not a metered starter. Studio (post-launch) reads raw fragments + cross-project + structured output + export.
- **AI blue, always.** AI Summary, the "Organized · review" card, sparkle glyph, confidence chips, suggestion "why" lines — all `#1E5C8E`, never ochre or amber. Shipping iOS code uses ochre/amber across multiple AI surfaces; this is a **uniform sweep, separate PR before TestFlight**, not a footnote on the Projects spec. Half-applied color rules are worse than uniformly-wrong ones. *(The old list-level "App is inferring" prompt is retired — see `AI Organize · spec.md §8.1`. Review is Memory-Detail-only.)*

### Notifications (locked May 2026 · revised · Channel B retired July 7 2026)

**One channel only — Captured Clips arrivals. Passive. No inactivity nudge.** HiMem does not notify you about *absence*.

> **Why Channel B (Inactivity) was retired.** It fired after 24h of no capture — *"It's been a quiet day" / "Three days since you captured anything"* — which is precisely **the app raising the skipped thing**, the one posture `Kingfisher · North Star.md` forbids outright ("The app never raises the skipped thing; the person does… does not send the soft-voiced check-in. The stake is carried silently and surfaced only on pull."). Off-by-default opt-in was the old mitigation; the constitution's rule is absolute, so the channel is gone, not softened. It also contradicted our own App Store promise ("No streaks. No nudges."). The audit that caught it: July 7 2026.

#### Channel A · Captured Clips (the only channel)
- One pending notification at a time, representing the current inbox state.
- **Always passive — never buzzes, never lights up the screen.** Uses `UNNotificationInterruptionLevel.passive` so the notification lands silently in Notification Center / on the lock screen but doesn't vibrate, doesn't fire a banner, doesn't wake the device. It is a tappable handle to jump to Captured Clips, nothing more.
- **App in foreground** → no notification posted at all; the badge alone reflects state.
- **App backgrounded or locked, first clip into an empty inbox** → post the passive notification.
- **Subsequent arrivals while pending** → update the existing notification in place. Same `UNNotificationRequest` identifier, body re-rendered with current count ("4 voice clips waiting" → "5 voice clips waiting"), badge synced. Still passive.
- **User clears the inbox** (review in app, tap notification, Mute action) → notification removed, badge cleared.
- **No arbitrary caps.** Passive + one-pending + in-place-updates is the entire noise budget.
- **The badge is a dot, in-app only (resolved July 10 2026).** Earlier this was "under review." Resolved: the in-app **Clips tab shows a dot** for new unseen arrivals (presence, not a count), clearing when the user opens Clips; the **app icon shows no number** (a numeric badge is the only thing iOS allows there, and counting reintroduces the guilt-inbox). The passive notification is the only external arrival signal. See the Phone · arrival-status bullet.

#### Onboarding · notification setup
- The onboarding notifications screen now presents **one** toggle — Captured Clips arrivals (passive) — defaulted on, shown and confirmed (no silent enrollment). The iOS system permission dialog fires after, only if it's on.
- Settings → Notifications surfaces the same single toggle.

#### Cross-cutting
- **Quiet hours 10pm–7am local.** A first-of-stretch post defers to 7am; arrivals during quiet hours update the deferred payload silently and it lands once at 7am with current state. (Passive already means it never wakes the device — this only governs when it appears.)
- *Mute for today* is an inline `UNNotificationAction` — suppresses through local midnight, clears the pending notification.
- Tap notification → opens Captured Clips. Long-press → Manage → iOS Settings. Focus modes respected.

- **AI Organize (locked, see `AI Organize · spec.md` for full rules)**
- **AI is an organizational helper, not the product.** The summary's job is to give a memory a name its author will recognize six months later.
- **The Honest Label principle.** Summary contains nothing the clips don't contain. Length matches substance. Voice is descriptive, not interpretive. *Describe, don't interpret.*
- **Voice:** stored with "you" baked in (e.g. *"You're exploring…"*). Owner sees this verbatim. On share/export, a simple `replacingOccurrences` swaps "you/You" for the user's first name. **Pronouns are allowed** — owner is *you*, other people are named with pronouns as appropriate; default to singular *they* when a person's pronoun isn't established (never guess from a name). Present for thinking, past for events.
- **Organize is manual on Free, automatic on Plus.** Free: a deliberate **Organize** tap, run on-device (iPhone 15 Pro+/iOS 26, 1.2–1.7s, fully offline) or server-fallback on older devices — no counter, re-run freely. Plus: the same pass happens automatically on capture, on a frontier model, plus `nextSteps` and the connective work. Editing, re-running, and failed passes never penalize — nothing is counted. **On-device validated June 5** (`uploads/foundation-models-spike-findings.md`): ships as an *editable first draft*, not a guarantee — three documented failure classes are hand-editable, so the Free draft is never presented as authoritative.
- **`nextSteps` is Plus-only.** The on-device model fabricates forward actions; proactive "what's next" is the automatic/Plus side. Free describes what's there.
- **Plus organize is offline-graceful, not offline-blocked.** A Plus user capturing offline gets the on-device draft immediately; frontier polish lands silently on reconnect. One pipeline, two backends.
- **v1 sees text + audio only.** Photos and videos referenced by metadata. v1.5+: optional visual-analysis pass (heavier; opt-in per pass, candidate for a higher tier).
- **Provenance** lives in the Organized chip, never on the field. The chip is a **review-state label, not a tier badge**: an unreviewed pass reads *"Draft organized"* (*"Give this a glance"*) on both tiers, becoming plain *"Organized"* only on accept/edit — so the on-device draft is never presented as authoritative, and "Organized" is never claimed before a human confirms. (Full rule: `AI Organize · spec.md` §2b/§9.)

### Power and wake lock (locked)
- **HiMem only prevents sleep during intentional capture.** Recording in progress, photo composer open, video composer active → wake lock on. Browsing, viewing, listening back, editing → wake lock off. The system idle timer is a trust contract we don't override casually.

### In-context capture — "capture where the memory was triggered" (post-v1 consideration, June 17 2026)

*Mostly v1 now. **Project capture ships in v1** (the context-aware FAB, locked July 10 — see this file's FAB rule); **artifact capture remains post-v1.** The section is kept for the shared rationale. A direct consequence of the perishability first principle.*

The insight: a **Project is not a folder you file into — it's a room full of cues.** Once a project exists, browsing it *triggers* recall ("I'm looking at the Naples photo of Dad → oh, the Cozumel sunburn story"). At that moment the fastest path to capture must be **one tap, in place**, because the trigger and the surrounding context are exactly what's about to pass. Forcing the user to leave the project, find global capture, record, then re-file is the canonical perishability violation — it asks them to carry the memory (and often the *associative chain* behind it) while operating the UI.

Three entry points this implies (all preserve "capture first, organize later" — the project association is a *known destination*, not an organizing step):
- **Global capture** — the main FAB / Watch / Memory Box. No project. Most common. *(ships in v1)*
- **Project capture** — a "+ New memory" inside a project; the new memory is auto-associated with that project. The point isn't filing — it's that *the project was the trigger*. ***(ships in v1 — this is the context-aware FAB's "inside a project" behavior, locked July 10 2026 at the top of this file. The "post-v1" it once carried is superseded.)***
- **Artifact capture** — "Remember this" on a photo / video / document; creates a memory linked to that artifact (and its project). The artifact is the memory cue; the workflow is *see → remember → capture*, not *add → annotate*. *(post-v1; connects to the photo-as-cue realization behind the App Store voice-first framing)*

Design caution if/when built: it must feel like *"something else just came back to me while I'm here,"* never *"create memory → choose project"* (task-app behavior). The button protects the memory, it doesn't organize it. Anywhere a memory can be triggered — projects, photos, videos, search results, future collections/publishing surfaces — should support immediate capture. A secondary goal beyond preserving the *memory* is preserving the *momentum*: capture-in-place lets a cascade of associated recollections land one after another without the UI breaking the chain.

### Idle-gap sessioning — "a session is a sitting, not a wrist-raise" (June 30 2026)

*A direct consequence of perishability at the organizing end. The automatic rule is locked for the Captured Clips build; the explicit affordance is a post-v1 candidate. Full detail: `Captured Clips · session-first · spec.md` → Idle-gap sessioning.*

Dogfood (dinner at the CIA, June 30) exposed it: five clips captured 6:09–6:18 PM were obviously *one dinner*, but each wrist-raise became its own session, so the day arrived as 13 one-clip cards and the user had to re-consolidate by hand. That is perishability failing at the *organizing* end — the thing that is one memory arrived as five decisions.

- **Automatic rule (locked, no user action):** clips separated by less than an idle threshold (default 10 min, provisional) are one session; a longer gap closes it. **Silence is the boundary.** `rollGroupId` from On a roll always overrides. Deterministic — a clock, not a classifier — so it ships without the intent parser.
- **Explicit affordance (candidate, post-v1):** *"hold a block open"* — a spoken/one-tap command that keeps one session open across longer-than-threshold gaps (a dinner across courses, a lecture with a break). The idle timer is still the safety net (auto-closes on a longer silence); there is **no mode to get trapped in** and nothing to remember to turn off. Never blocks capture to set up (create any named destination silently, tell the user after). Its voice-command form ("everything for the next hour is one block") is the first spoken *command* that is clearly not content — it forks the intent-parser question, which is the dependency that makes it post-v1.
- The two need each other: strict automatic close would wrongly split a real dinner's between-course lulls; the hold-open affordance is the escape valve for exactly that case. Both are the same principle — **structure forms from the user's rhythm or one spoken breath, never from navigation** — the prospective sibling of retroactive clustering and the voice-declared sibling of in-context capture.

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
- `Pricing model · Capture-Connect-Create.md` — **current pricing direction** (proposal pending on-device Honest-Label prototype). Supersedes the assist-quota model now in `archive/assist-model/`.
- `Memories list · spec.md` — the Memories list surface (one card, contextual density, fallback chain).
- `Memory Detail · long-memory navigation.md` — the Full ⇄ Compact transcript toggle for long memories (>1 clip shows it; size picks the default; Compact rows are single-open accordions with full swipe parity).
- `Memory Detail · unified editing model.md` — one rule per category: text = tap to edit (incl. summary; never reverts Organized→Draft); media = tap to consume (audio demoted, transcript is the working object); rows = red Trash swipe, memory-delete = toolbar Trash; topics = tap chip → sheet, mentions = inline; no pen, no edit mode.
- `Tutorials · triggers spec.md` — the five one-pager tutorials + their automated triggers (capture / organizing / find-the-thread ≥3 / Watch story / Watch discovery via app-level `WCSession.isPaired`), the discovery-vs-usage split, and the once/defer/tier/no-nag rules. Surfaces in `Himem · Tutorials.html`.

### Surface canvases (each is a `Himem · X.html` + accompanying `screens-*.jsx`)

| Canvas | Screens module(s) |
|---|---|
| `Himem · Flow.html` — full Watch → Memory flow + notification spec | inline |
| `Himem · Watch.html` — Watch design canvas | inline |
| `Himem · Voice Composer.html` — phone direct-voice + append composers with on-a-roll parity; **first-run capture tutorial** (shown once before the first recording: teaches capture, the Next/on-a-roll behavior, and that the Watch records too) | `screens-voice-composer.jsx` |
| `Himem · Settings.html` — **canonical Settings canvas** (full menu + Appearance, Edit Topic, Captured Clips empty, **Tutorials hub**). Common settings top → dev-only Debug + Plus-override at bottom. | `screens-settings.jsx` |
| `Himem · Tutorials.html` — the **five tutorial one-pagers** (capture · organizing · find-the-thread · Watch story · Watch discovery). Triggers in `Tutorials · triggers spec.md`. | `screens-tutorials.jsx` |
| `Himem · Memory Detail.html` — Memory detail view (clip headers carry date+time+location; mentions promoted above Organized review) | `screens-memory-detail.jsx` |
| `Himem · Captured Clips.html` — v0, original clip-first design (superseded; kept as reference) | inline |
| `Himem · Captured Clips (session-first).html` — **v1 canonical**, per session-first spec | `screens-captured-clips-sessions.jsx` |
| `Himem · Projects.html` — projects MVP canvas | `screens-projects.jsx` (shared bits), `screens-projects-cards.jsx` (cards), `screens-projects-views.jsx` (5 screen views), `screens-projects-spec.jsx` (annotated dev row spec) |
| `Himem · Pricing.html` — **RETIRED** to `archive/assist-model/` (assist-quota model). New pricing per `Pricing model · Capture-Connect-Create.md`; replacement screens TBD post on-device prototype. | *(archived)* |sx` |
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

## Open todos (June 2026 handoff)

**Pricing model — Capture · Connect · Create** (`Pricing model · Capture-Connect-Create.md`). The assist-quota model is retired (`archive/assist-model/`). **The hard dependency is RESOLVED (June 5):** Apple's on-device organize was validated against the Honest-Label rubric (`uploads/foundation-models-spike-findings.md`) — ships as an editable first draft for Free, 12/15 clean, hand-editable misses. §2/§4/§5 of the pricing doc are now ratifiable. Locked: Free = 3 projects + manual/on-device organize (editable draft, no `nextSteps`); Plus = automatic/frontier + `nextSteps` + offline-grace; Studio = post-launch; prices Plus $4.99–$7.99, Studio $7.99–$14.99. Still open (non-blocking): fallback fair-use cap, Plus "unlimited" ceiling, **Free-draft honesty affordance** (the on-device draft must never read as authoritative — resolve during the Pricing-canvas design pass), offline-grace UX.

**Next:** build the new Pricing canvas against this model — most of it *simplifies* (no exhausted/pack/counter surfaces). The old assist canvas is in `archive/assist-model/`.

Phone-audit work that hasn't shipped yet:
- Audit shipped iOS screens against current Crucible spec.
- Identify gaps for v1 release.
- Build phone v1 screen flow on the design canvas.

Pick one when ready, or take a fresh direction.
