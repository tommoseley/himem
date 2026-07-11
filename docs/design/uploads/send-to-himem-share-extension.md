# Send to HiMem (iOS Share Extension) — TODO

## What
Add HiMem to the iOS system Share Sheet. Any app that supports sharing — Safari, Notes, Messages, ChatGPT, Mail, Notion, etc. — can route content into HiMem with one tap, producing a new memory that flows through the normal organize pipeline.

Eliminates the "I had to retype/paste this into HiMem" friction observed 2026-06-01 when capturing a long GPT product-strategy conversation. With the extension, the same flow would have been: tap Share in ChatGPT → tap HiMem → done.

## Accepted Content (v1.x)
- **Plain text** — selection, transcript, message body. Most common case.
- **URLs** — Safari, Reader View, Notes link. Stored verbatim at intake; main app may optionally fetch + extract on first organize pass (post-v1.x).
- **Images / screenshots** — single image at a time, lands as a `MediaReference` on a new entry.

Not in v1.x:
- PDFs (separate work — PDF rendering, text extraction)
- Video / audio attachments (size + processing concerns)
- Multi-item shares (most callers ship a single item anyway)

## Architecture
- **New Xcode target**: `HiMem Share Extension` (NSExtensionPointIdentifier `com.apple.share-services`).
- **App Group** entitlement: HiMem main app does not have one today — add `group.com.himem.app.shared` to both the main app target and the new extension. Provisioning profile regeneration required for both.
- **Shared container** (`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`) holds a single directory: `pending-intake/`.
- **Intake schema**: one JSON file per pending item, named `intake-<UUID>.json`. Schema:
  ```json
  {
    "id": "<UUID>",
    "createdAt": "<ISO8601>",
    "kind": "text" | "url" | "image",
    "source": "<host bundle identifier>",
    "text": "<string, when kind=text or url>",
    "imageFilename": "<sibling file in same dir, when kind=image>"
  }
  ```
- **Main app pickup**: on `didBecomeActiveNotification`, scan `pending-intake/`, drain each item by creating a `JournalEntry` (input type `.shared`, content = the text or a placeholder for image-only), copying any attached image into HiMem's own MediaReference store, deleting the intake file on success. Then the standard organize pass runs as if the user had typed it.
- **Extension UI**: minimal — system `SLComposeServiceViewController` (or SwiftUI equivalent) showing the text being shared and a one-line "Add to HiMem" affordance. No tier checks, no project picker, no organize-now toggle in v1.x — keep the extension light. Triage / organize happens when the user opens HiMem.

## JournalEntry Changes
- Add a new case to `JournalEntry.InputType`: `.shared` (alongside existing `.typed`, `.voice`, `.watch`, …). No new attributes — `inputType` already serializes via the existing string column.
- Optional: cache the host bundle identifier on the entry for analytics ("most users share from Safari and ChatGPT"). Defer — easier to add later than to ship and migrate.

## Privacy
- The Share Extension only sees what the user explicitly hands it via the system share sheet. No silent capture.
- Same provider rules as the main app: if the user later runs an organize pass, that pass uses the standard `tier`/`action` plumbing through `/himem/analyze`. No extension-specific telemetry.
- Intake files live in the app group container — readable only by the main app + extension. Not iCloud-synced (CloudKit syncs the resulting `JournalEntry` after pickup, not the intake JSON).
- Image intake stays on device until the user converts it to a memory; same lifecycle as any other captured photo.

## Failure Modes
- **Extension can't write to shared container**: surface as an error in the extension UI; do not silently swallow. Most likely cause = entitlement missing post-provisioning regeneration.
- **Main app pickup races concurrent intakes**: each intake file is named with a UUID; pickup processes them in file-creation order; partial failure (e.g., MediaReference copy fails) leaves the intake file in place for retry next foreground.
- **User force-quits the main app between intake and pickup**: intake files survive across launches — next foreground drains the queue. Bounded staleness, no data loss.

## Not in Scope (v1.x)
- Background URL fetching at intake time. URLs are stored as text in v1; the user organizes them like any other entry. Server-side URL → article-extraction is a separate feature.
- Apple Pencil scribble / drawing intake.
- Watch share targets (watchOS doesn't model Share Extensions the same way; out of scope).
- Multi-item batched intake.
- A "send to specific project" picker inside the extension (would require the extension to read HiMem's Core Data store, which it can't without significantly more shared-container plumbing). User assigns to a project in the main app after pickup.

## Effort
Roughly 2–3 focused days post-launch:
- Day 1: new target + App Group entitlement + provisioning + shared container scaffolding + intake file write/read.
- Day 2: main app pickup, `JournalEntry.InputType.shared` wiring, image-copy path, organize-pass integration.
- Day 3: extension UI polish, error handling, end-to-end test from Safari + ChatGPT + Notes.

## When
v1.1 candidate — high-leverage, low-coupling, eliminates a friction point that's easy to observe in real use. Defer pre-launch.
