# Pre-launch UX walkthrough — 2026-06-08

Step-by-step verification of every user-facing change in the
2026-06-07 → 2026-06-08 work arc. Run on a real device when you can
(audio session + iCloud Drive behavior differ from the simulator) but
the simulator catches everything else.

Each step has a **set up**, a **do**, and an **expect**. If the
expectation fails, the section header has the file:line to start
debugging.

The auto-tested layer (587 → 629 tests across new suites covering
pure logic) catches the algorithmic regressions; this walkthrough
catches the visual + interaction + state-machine regressions that
only render on a real screen.

**Background — the June 8 affordance vocabulary lock** (`docs/design/CLAUDE.md`)
governs many of the visual changes this walkthrough verifies. The
three signals are:
1. **Real button** (filled or clearly bordered, ≥44pt) = the action.
2. **Solid filled pill with a leading dot** = managed content (topics, mentions); tap to manage.
3. **Quiet label** (icon + text, no border, no pill) = status / information; never tappable.

Dashed borders are reserved for *add / incomplete / provisional* only
(`+ Edit`, `NEW` topic chips). Status is never dressed as a button.
The real action is never disguised as a text link. Selection = ring;
completion = check.

---

## 0. Pre-flight

**Set up.** Cold launch on a device signed into iCloud with iCloud
Drive enabled. Use a memory that already has at least one AI organize
pass that the user hasn't reviewed yet — that puts the section in
**"Draft organized"** state and surfaces the **Review draft** button.

If you don't have one, create a memory with a few voice clips,
then tap **Organize** on the Memory Detail's AI zone (mid-page card)
and wait ~1.5s for the on-device pass.

---

## 1. Topic UI · Memory Detail row
*Source: `EntryExpandedView.swift:topicChipsRow`, `screens-topics.jsx` `ScrMemoryWithTopics`.*

### 1.1 Row position is BELOW the summary

**Do.** Open any organized memory.

**Expect.**
- Order from top: title (serif) → date+time → summary → **TOPICS** row → clip cards.
- Topics row is **under** the summary, not above it.
- Topic chips fit on one line when the labels are short; **wrap to the next line** when there isn't horizontal space (no per-chip text wrapping).

### 1.2 Chip rendering

**Expect for each assigned topic:**
- Ochre dot (~6pt) on the left.
- Label in `ink` color, 13pt.
- `wash1` (light cream) background.
- No border.
- Single-line label — chip widens to fit, never wraps the text.
- Chip is **≥38pt tall** with **≥10pt row spacing**. Per the June 8 affordance lock, "a chip you must aim for is a bug." Use the iOS simulator's Accessibility Inspector's hit-test overlay if you want to confirm visually.

### 1.3 Edit affordance

**Expect.**
- A **"+ Edit"** button sits at the end of the chip row.
- Dashed border in ochre (`#C64A1C`) — per the rule, dashed = *add / provisional* affordance.
- Same height as the topic chips (≥38pt) — the row reads as uniform.
- Always visible — not gated on a global edit mode.

---

## 2. Topic UI · Manage Topics sheet
*Source: `ManageTopicsSheet.swift`, `screens-topics.jsx` `ScrManageTopics`.*

### 2.1 Open the sheet

**Do.** Tap the **+ Edit** affordance from §1.3.

**Expect.**
- A sheet rises from the bottom (`.large` detent).
- Top bar: **Cancel** (ink2) · centered **Topics** (ink bold) · **Done** (ochre bold).
- Body copy: *"Pick from your library, or add a new topic. Picking the right existing one keeps your topics useful as filters."*
- Section header **ON THIS MEMORY** with the entry's current topics rendered as `.pick` chips: **ochre dot + wash1 background + solid 1.5pt ochre selection ring**. Per the June 8 lock — *selection = ring; completion = check; don't conflate.* There is **no trailing checkmark**.
- Section header **FROM YOUR LIBRARY** with every OTHER palette topic as `.off` chips (transparent background + hairline border + ink4 dot + ink3 label).
- An inline **Add a new topic…** field between the two sections.

### 2.2 Pick/unpick interactions

**Do.** Tap a chip in **"From your library"**.

**Expect.** It moves to **"On this memory"** and gains the **solid ochre selection ring** (the `.pick` state's signal).

**Do.** Tap a chip in **"On this memory"**.

**Expect.** It moves to **"From your library"** (ring disappears, returns to `.off` with hairline outline).

### 2.3 Add a new topic — case canonicalization

**Set up.** Pick a memory whose library has a topic named `"Garden"` (capitalized).

**Do.** Type `garden` in lowercase into the **Add a new topic…** field and tap **Add** (or press Return).

**Expect.**
- The new chip lands in **"On this memory"** with the palette's canonical **"Garden"** form (not `"garden"`).
- The field clears.

### 2.4 Add a fresh topic

**Do.** Type a name that's not in the palette (e.g. `"Pottery"`). Tap **Add**.

**Expect.**
- New chip appears in **"On this memory"** in `.pick` state.
- The chip does NOT appear in **"From your library"** below (it's already in the "on memory" section).
- The new topic is held in `selectedNames` but no `Topic` record exists yet — that's deliberate; the record is created on **Done**.

### 2.5 Cancel discards

**Do.** Make changes (pick, unpick, add). Tap **Cancel**.

**Expect.**
- Sheet dismisses.
- Memory Detail chip row reflects the **original** topic set. No write happened.

### 2.6 Done commits

**Do.** Make changes. Tap **Done**.

**Expect.**
- Sheet dismisses.
- Memory Detail chip row reflects your selections.
- **For added new topics:** they appear in the palette and are filterable from the Memories list's topic bar (after navigation).

### 2.7 Empty states

**Set up.** A memory with no topics yet AND an empty palette (a fresh-install test scenario).

**Do.** Open Manage Topics.

**Expect.**
- "On this memory" shows *"No topics on this memory yet."* in ink3.
- "From your library" shows *"Your library is empty. Add a topic above to get started."*

**Set up.** A memory where all palette topics are already on it.

**Expect.** "From your library" shows *"Everything in your library is on this memory."*

---

## 3. Topic UI · Draft review sheet
*Source: `DraftReviewSheet.swift`, `screens-topics.jsx` `ScrOrganizeReviewTopics`.*

### 3.1 Open the review

**Set up.** Memory with an unreviewed organize pass. Memory Detail's AI zone now shows the **"Draft organized"** quiet label + a full-width **Review draft** button beneath it (per the new affordance lock — see §12 for the cluster).

**Do.** Tap the **Review draft** button.

**Expect.**
- Sheet rises. Header has a quiet **"Draft organized"** label (sparkle icon + text in AI-blue, no border, no pill) on the left and an ✕ close button on the right.
- Below, the *"A draft from your device."* serif hero.
- Three field rows: **Title**, **Summary**, **Topics** — in that order with hairline dividers between them.

### 3.2 Topics row chips

**Expect.**
- **TOPICS** eyebrow in AI-blue.
- Chips that were already in the user's palette render as `.set` (ochre dot, wash1 background — same shape as Memory Detail).
- Chips the model coined that don't exist in the palette render as `.new` (sparkle ✦ glyph, AI-blue dashed border, AI-blue text, "NEW" label after the name).
- Both kinds wrap to multiple lines if needed without per-chip text wrapping.

### 3.3 Topics row caption (mixed)

**Set up.** Pass returns at least one palette-matched topic AND at least one new one.

**Expect.** Below the chips, an AI-blue sparkle followed by ink3 text:
> *"Travel and Family from your library. New England new — tap to drop if you'd rather not start a topic."*

(Oxford comma when 3+: *"Travel, Family, and Work from your library."*)

### 3.4 Topics row caption (existing only)

**Set up.** Pass returns only palette-matched topics.

**Expect.** *"Travel and Family from your library."* — no "tap to drop" sentence.

### 3.5 Topics row caption (new only)

**Set up.** Empty palette + pass returns topics.

**Expect.** *"New England new — tap to drop if you'd rather not start a topic."* — no "from your library" sentence.

### 3.6 Drop a NEW chip

**Do.** Tap a `.new` chip.

**Expect.**
- Chip disappears from the row.
- The caption updates (if you dropped the only `.new` chip, the "tap to drop" sentence is gone).

### 3.7 "Looks good" commit

**Do.** With at least one NEW chip not yet dropped, tap **Looks good**.

**Expect.**
- Sheet dismisses.
- Memory Detail chip row gains the **kept NEW chips** as plain `.set` chips (ochre dot, wash1). They are now in the palette.
- The Memory Detail AI zone changes:
  - The **"Draft organized"** label flips to plain **"Organized"** (same quiet-label shape: check glyph + text in AI-blue, no border, no pill).
  - The full-width **Review draft** button is gone. (On the Organized state, the only AI-zone action is **Reorganize** in the row beside the label.)
- A **dropped** NEW chip does NOT appear in the topic row. It was never added to the palette.

### 3.8 "Edit" exits to detail

**Do.** Re-open the review sheet. Tap **Edit** (bottom secondary action).

**Expect.** Sheet dismisses with NO topic / title / summary writes. Existing entry data unchanged.

---

## 4. Topic UI · The popup is gone
*Source: `JournalView.swift:JournalPromptDialogs`, `ProcessingEngine.swift:applyAnalysisResult`.*

### 4.1 No mid-app popup after organize

**Set up.** A fresh memory with no AI organize yet. Make sure the palette already has at least one topic (so we can verify only the popup is gone, not the whole flow).

**Do.** Tap **Organize** on the AI zone. Wait for the pass to finish.

**Expect.**
- The chip flips to **"Draft organized"**.
- **No sheet pops up** mid-app asking you to approve a new topic. The old `TopicApprovalSheet` is retired.
- Any NEW topics the pass returned are only visible inside the DraftReviewSheet (§3) when you tap the chip.

### 4.2 No popup on subsequent organizes either

**Do.** Run a second organize on the same memory (Reorganize button).

**Expect.**
- Reorganize ignores topics entirely (only re-suggests title + summary).
- No popup, no topic row changes.

---

## 5. Voice transcript retry — failure preserves draft
*Source: `AudioPlayerSheet.swift:applyRetryOutcome`, `decideRetryAction`.*

### 5.1 Successful retry overwrites the draft

**Set up.** A voice clip with a transcript. Edit the transcript field to something obviously different (e.g. add `"~~~"` at the end).

**Do.** Tap **Retry transcription**.

**Expect.**
- "Retrying…" with spinner replaces the button.
- On success, the draft updates to the new transcription. The `"~~~"` you added is gone (this is correct — retry succeeded with text).

### 5.2 Failure does NOT blank the draft

**Set up.** Either airplane mode on a non-FM device (forces model unavailable) OR an empty audio file.

**Do.** Tap **Retry transcription**.

**Expect.**
- "Retrying…" → button returns.
- The draft transcript is **unchanged** — your text stays exactly as it was.
- A small message appears under the button: *"Couldn't retranscribe — kept your text"*.
- After ~4 seconds the status line auto-clears.

### 5.3 Genuine silence preserves draft

**Set up.** A clip the recognizer can analyze but contains no speech (rare; you can simulate with a silent audio file).

**Do.** Retry.

**Expect.** Draft preserved. Message: *"Retry returned no speech — kept your text"*.

---

## 6. Photo card — no whole-card tap
*Source: `ChronologicalCaptureStream.swift:MediaCard`.*

### 6.1 Tapping the card does nothing

**Do.** Open a memory with a photo/video clip. Tap anywhere on the photo card.

**Expect.** Nothing happens. No sheet, no viewer, no navigation. The card is read-only at tap.

### 6.2 Swipe Edit opens the editor

**Do.** Leading-swipe (left-to-right) on the photo card.

**Expect.** **Edit** action appears in ochre. Tap it → **PhotoDescriptionEditSheet** opens directly (no intermediate viewer).

---

## 7. Voice clip downloading state
*Source: `ChronologicalCaptureStream.swift:VoiceClipPanel`.*

### 7.1 Genuinely empty transcript

**Set up.** A voice clip whose recognizer ran end-to-end and produced no text (rare). The audio file IS local.

**Expect.** Row shows *"(no transcript)"* in ink4 (faint).

### 7.2 Audio still downloading from iCloud

**Set up.** Fresh second-device install — CloudKit delivers the memory + clip metadata, but the audio file hasn't downloaded yet. The fastest way to reproduce: sign in on a second device and let CloudKit settle, but kill the app before audio downloads complete.

**Expect.** Row shows *"Audio downloading from iCloud…"* (not "(no transcript)").

### 7.3 Audio file gone

**Set up.** Use Files.app to delete the audio file from the HiMem ubiquity container.

**Expect.** Row shows *"Audio no longer in iCloud."* (not blame-y, not "missing").

---

## 8. Empty state on Today
*Source: `JournalView.swift:emptyMemoriesState`.*

### 8.1 Fresh install, no memories

**Set up.** Fresh install, complete the wizard, land on Today.

**Expect.**
- Subhead: *"Your Memory Box is empty"*.
- Below it: *"Tap the orange button in the bottom-right to capture your first memory — voice, photo, video, or text."*
- (The previous "Tap + to create…" copy that referenced a nonexistent "+" is gone.)

---

## 9. Error copy is human
*Source: `JournalView.swift:JournalServiceErrorAlerts`, `SpeechService.swift`, `CameraService.swift`, `ErrorService.swift`.*

### 9.1 Voice error alert

**Set up.** Deny microphone permission in iOS Settings, then try to start a voice recording.

**Expect.**
- Alert title: **"Couldn't record"** (not "Voice Recording Error").
- Body: *"Speech recognition isn't allowed. You can enable it in Settings."*
- Action: **Open Settings** + **OK**.
- No raw `NSOSStatusErrorDomain` codes anywhere.

### 9.2 Camera error alert

**Set up.** Deny camera permission, then try to capture a photo.

**Expect.**
- Title: **"Couldn't open the camera"**.
- Body: humanized; no raw error.

### 9.3 Generic error banner

**Set up.** Trigger a save failure (you may need to add a temporary `throw` in `EntryLifecycleService.append` for testing — revert after).

**Expect.**
- Banner shows: *"Couldn't save that. Try again in a moment."*
- Console has `[HiMem][AppError]` log line with the raw detail for debugging — but the user-facing string is human.

---

## 10. NSFileCoordinator wrapping (visual only)
*Source: `UbiquityStore.swift:copyIntoStore`, `PhotoLibraryPicker.swift`, `WatchSessionDelegate.swift`, `MediaReferenceUbiquityMigration.swift`, `AudioCompressor.swift`.*

The coordinator wrapping is invisible at the user surface — its job is to prevent silent torn-write corruption when iCloud's file-presenter and the app race. There's no UI signal. What you CAN verify is that the user flows still work end-to-end:

### 10.1 PHPicker import still works

**Do.** From a memory's Append flow, pick a photo or video from the library.

**Expect.** Item appears in the memory. Bytes land in the ubiquity container (visible in Files.app under "HiMem").

### 10.2 Watch clip arrives

**Do.** Record a clip on the watch. Wait for sync.

**Expect.** Clip appears in Captured Clips → Memory Box. The audio plays back on the phone.

### 10.3 Voice compression doesn't kill the file

**Do.** Record a long-ish voice clip (15+ seconds) directly on the phone. Save.

**Expect.** Clip plays back correctly. Duration metadata is correct. No 0:00 ghost. On second device after iCloud sync, the clip also plays.

---

## 11. Quick smoke test (5 min)

For a smoke pass before each TestFlight build, the minimum:

1. Cold launch → Today renders within ~400ms.
2. Capture a voice clip from the phone composer. Memory exists in Today.
3. Tap into the memory → it renders. Tap **Organize** → "Draft organized" label + **Review draft** button appear within 2s.
4. Tap **Review draft** → DraftReviewSheet has Title/Summary/Topics. Tap "Looks good".
5. Tap **+ Edit** on the topic chip row → Manage Topics opens. Add a new topic. Done.
6. Pull-to-refresh on Today. No errors.
7. Background, foreground. Memory still there.

If all 7 pass, ship.

---

## 12. Affordance vocabulary cluster (June 8 lock)
*Source: `OrganizedChip.swift`, `OrganizeMemorySection.swift`, `TopicChip.swift`, `docs/design/CLAUDE.md`.*

The June 8 design lock was prompted specifically by the Memory-detail
"Draft organized" cluster — *"three weak fragments (dashed status pill
+ hollow-dot label + underlined link) that collided with the dashed
`+ Edit` button."* This section verifies the resolution and the
broader rule it produced.

### 12.1 Draft state — status reads as status

**Set up.** A memory with an unreviewed organize pass.

**Expect on the AI zone:**
- **"Draft organized" label** — sparkle ✦ glyph + text in AI-blue. **No background, no border, no pill.** Reads as a quiet label, not a button.
- The label is **not tappable** — tapping it does nothing.
- Below the label, a **full-width filled AI-blue button** labeled **Review draft** (with sparkle glyph). This is the one primary action.
- The **Review draft** button is **≥44pt tall**.
- The hollow-dot "unreviewed" indicator from the pre-June-8 layout is **gone**.
- The "Tap to review & keep →" text link is **gone**.

### 12.2 Organized state — status reads as status, action reads as action

**Set up.** Same memory, after reviewing the draft (tap Review draft → Looks good).

**Expect on the AI zone:**
- **"Organized" label** — check glyph + text in AI-blue. Same quiet-label shape as the Draft state, just a different icon + word.
- The label is **not tappable**.
- To the right of the label: the **Reorganize** button — arrow glyph + "Reorganize" in AI-blue, **with a clear AI-blue border**, ≥44pt tall. A real button per the rule (bordered, ≥44pt). Bordered rather than filled because the Organized state is reflective; bordered keeps it tappable without dominating the reading surface.
- The full-width **Review draft** button is **gone** — the draft is no longer the action.
- During an in-flight reorganize: the button stays bordered but the glyph swaps to a spinner and the label reads "Working…".

### 12.3 The vocabulary holds across surfaces

**Do.** Spot-check that the three signals stay consistent everywhere:
- **Real buttons** (filled or clearly bordered, ≥44pt): "Looks good" in DraftReviewSheet, "Review draft" on Memory Detail Draft state, "Reorganize" on Memory Detail Organized state (bordered variant), "Done" in ManageTopicsSheet's top bar (ochre bold ≥44pt tap zone). Each is the loudest interactive thing in its moment.
- **Solid filled pills with leading dots** (managed content): topic chips on Memory Detail. Tap to manage opens ManageTopicsSheet.
- **Quiet labels** (icon + text, no border, no pill): "Draft organized" / "Organized", TOPICS / SUMMARY / TITLE eyebrows, status badges.
- **Dashed borders** appear only on: the **`+ Edit`** affordance (add) and **`.new`** topic chips (provisional). Never on status.

### 12.4 The 44pt hit-target floor

**Do.** On Memory Detail, eyeball every tappable element.

**Expect.** No chip is < ~38pt tall. No tap target is so small you have to aim. Topic chips, the `+ Edit` button, the **Review draft** button, the trash/folder/share/edit toolbar icons in the top bar — all clear the floor with comfortable spacing.

If you want to be rigorous: open the iOS Simulator's **Debug → Highlight Touch Targets** overlay and walk through Memory Detail. Anything < 44pt that isn't separated from neighbors by ≥8pt is a bug.

---

## Test count baseline

Automated tests after this arc: **629 / 72 suites**. Started the arc at 570 / 65.

New suites added during this arc:
- `AudioPlayerSheetRetryDecisionTests` (6)
- `VoiceClipPanelDisplayTextTests` (8)
- `UbiquityStoreTests` (+3 — copyIntoStore)
- `TopicPalettePartitionTests` (10)
- `OnDeviceOrganizerPromptTests` (7)
- `ProcessingEngineCanonicalizeTopicsTests` (8)
- `ManageTopicsSheetDeltaTests` (8)
- `DraftReviewSheetCaptionTests` (11)

The pure-logic surfaces have automated tests. The visual / interaction / state-machine layer is what this walkthrough validates.
