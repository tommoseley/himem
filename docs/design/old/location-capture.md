# Location Capture — TODO

## What
Capture the user's location when a memory is created. Stored as latitude/longitude on the entry, not shown in the feed but available for:
- Search by location ("memories from the garden" / "what did I capture at work")
- Map view (future)
- Location-based grouping in Studio (future)
- Context signal for AI inference (place adds meaning)

## Core Data Changes
- Add `latitude` (Double, optional) and `longitude` (Double, optional) to JournalEntry
- Add `locationName` (String, optional) — reverse-geocoded place name, cached at capture time

## Implementation
- Request location permission in onboarding (Permissions screen — add as 4th row)
- `CLLocationManager` — request "When In Use" authorization
- On entry creation: grab current location if authorized
- Reverse geocode to a place name via `CLGeocoder` (async, store when available)
- If not authorized: silently skip, no error

## Privacy
- Permission is optional (Skip honored)
- Location never sent to the API — stays on device + CloudKit
- User can disable in Settings
- Privacy description: "Hi Mem tags your memories with where you were, so you can find them by place later."

## Not in Scope
- Map view UI
- Location-based search (comes with Search feature)
- Geofencing or background location
