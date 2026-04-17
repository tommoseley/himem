# Changelog

All notable changes to Hi Mem are documented here.

## [0.1.0] - 2026-04-16

Initial build. App runs on device with full capture-to-inference pipeline.

### Added
- **Core Data models:** JournalEntry, ExtractedEntity, ProcessingTask, InferenceSummary, Topic, MediaReference
- **Journal UI:** Entry cards with title, source badge, status badge, content, topic chips, entity tags, inference summary card, feedback controls (confirm/edit/ignore)
- **Input capture:** Unified bottom input bar with text field, microphone button, Siri-ready indicator, save button
- **Voice input:** iOS Speech Framework integration with real-time transcription and simultaneous audio file recording
- **Voice playback:** Play/stop button on entry cards, share button for exporting audio via share sheet
- **Voice settings:** "Save voice entries" toggle in Settings; audio can be discarded from edit screen
- **AI processing pipeline:** Hybrid local/cloud architecture — Claude API (Sonnet) when connected, Apple NaturalLanguage NER when offline
- **Entity extraction:** 5 entity types (project, person, issue, idea, next_action) with confidence scoring, normalized labels (1-4 words, digits for numbers, singular form)
- **Topic inference:** AI-suggested topics with user approval dialog; managed in Settings
- **Inference summaries:** Natural-language explanation of what the AI concluded, shown as "APP IS INFERRING" card
- **Topic tab bar:** Horizontal filter tabs, entries filtered by selected topic
- **Siri shortcut banner:** Onboarding banner with shortcut instructions
- **Siri integration:** App Intents — "Capture in Hi Mem", Siri asks follow-up, entry saved and processed
- **Search:** Full-text search with entity-type filter chips
- **Entry editing:** Swipe right to edit text (triggers re-inference) or remove entity tags (no re-inference)
- **Entry deletion:** Swipe left to delete
- **Settings:** Topics list (add/swipe to delete), voice save toggle, API key management (Keychain-backed)
- **App icon:** hM monogram with memory nodes on white background
- **Branding:** "Hi Mem" display name, "HI MEM" header, com.himem.app bundle ID
- **Connectivity monitoring:** NWPathMonitor for online/offline AI routing
- **Evaluation docs:** EVAL-001 (binder-to-mockup alignment), CR-001 (correction request)

### Fixed
- Core Data threading violation in ProcessingEngine — was accessing viewContext objects inside backgroundContext.perform block; fixed by capturing objectID and using context.existingObject() consistently
