# Hi Mem — Architecture & Implementation

## Overview

Hi Mem is a native iOS journaling app that captures thoughts via voice or text and automatically extracts structured data using AI. It preserves the original input while quietly building a searchable, tagged knowledge base.

The core experience: capture a thought in the moment, and the app organizes it for you.

## Platform

- **iOS 17+**, Swift, SwiftUI
- **Local storage:** Core Data (SQLite-backed)
- **Cloud AI:** Anthropic Claude API (Sonnet)
- **Local AI:** Apple NaturalLanguage framework
- **Voice:** iOS Speech Framework (SFSpeechRecognizer)
- **Secrets:** iOS Keychain Services

## Architecture Layers

```
┌─────────────────────────────────────────────┐
│                   Views                      │
│  JournalView · EntryCardView · InputBarView  │
│  SearchView · SettingsView · EntryEditorView │
├─────────────────────────────────────────────┤
│                ViewModels                    │
│  JournalViewModel · SearchViewModel          │
│  DisplayModels (lightweight view structs)    │
├─────────────────────────────────────────────┤
│                 Services                     │
│  StorageService · ClaudeAPIService           │
│  ProcessingEngine · SpeechService            │
│  LocalEntityExtractor · SearchEngine         │
│  ConnectivityMonitor · TopicApprovalService  │
│  AudioPlayerService · KeychainService        │
├─────────────────────────────────────────────┤
│              Core Data Models                │
│  JournalEntry · ExtractedEntity · Topic      │
│  ProcessingTask · InferenceSummary           │
│  MediaReference                              │
└─────────────────────────────────────────────┘
```

## Data Models

### JournalEntry
The primary record. One entry per captured thought.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| title | String? | AI-inferred title (e.g., "Garden bed composting") |
| content | String | Original text — never altered by AI |
| inputType | String | `siri`, `voice_in_app`, or `typed` |
| audioFilePath | String? | Filename of saved voice recording |
| createdAt | Date | Capture timestamp |

**Relationships:** extractedEntities (1:many), processingTasks (1:many), inferenceSummary (1:1), topics (many:many), mediaReferences (1:many)

### ExtractedEntity
A structured tag extracted from an entry by AI.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| entryId | UUID | FK to JournalEntry |
| entityType | String | `project`, `person`, `issue`, `idea`, `next_action` |
| value | String | Short label (1-4 words, normalized) |
| confidenceScore | Double | 0.0-1.0 |
| textRangeLocation | Int32 | Position in original text |
| textRangeLength | Int32 | Length in original text |
| processingMethod | String | `local` or `cloud` |

### Topic
User-controlled categories for organizing entries.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| name | String | Display name (e.g., "Garden") |
| slug | String | Normalized key for filtering |
| inferredAt | Date | When first suggested |

Topics are many-to-many with entries. New topics suggested by AI require user approval via dialog.

### ProcessingTask
Tracks the AI processing lifecycle for an entry.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| entryId | UUID | FK to JournalEntry |
| status | String | `pending`, `processing`, `completed`, `failed` |
| progressDescription | String? | User-visible status text |
| processedAt | Date? | Completion timestamp |
| errorMessage | String? | Error details if failed |

### InferenceSummary
Natural-language explanation of what the AI concluded.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| entryId | UUID | FK to JournalEntry |
| summaryText | String | Human-readable inference |
| feedbackState | String? | `confirmed`, `edited`, `ignored`, or nil (pending) |
| userCorrection | String? | User-provided correction text |

## Processing Pipeline

```
User Input
    │
    ▼
┌──────────┐     ┌────────────────┐     ┌──────────────────┐
│  Entry   │────▶│ ProcessingTask │────▶│ ProcessingEngine  │
│  Saved   │     │  (pending)     │     │                   │
└──────────┘     └────────────────┘     └─────────┬────────┘
                                                   │
                                        ┌──────────┴──────────┐
                                        │                     │
                                   Connected?            Offline?
                                        │                     │
                                        ▼                     ▼
                                 ┌─────────────┐    ┌──────────────┐
                                 │ Claude API   │    │ Local NER    │
                                 │ - Entities   │    │ (NL Framework)│
                                 │ - Topics     │    │ - Names      │
                                 │ - Summary    │    │ - Places     │
                                 │ - Title      │    └──────────────┘
                                 └─────────────┘
                                        │
                                        ▼
                              ┌───────────────────┐
                              │ Results Stored     │
                              │ - ExtractedEntity  │
                              │ - InferenceSummary │
                              │ - Topic (approved) │
                              │ - Entry title      │
                              └───────────────────┘
                                        │
                                        ▼
                              ┌───────────────────┐
                              │ UI Updates Live    │
                              │ (Core Data observe)│
                              └───────────────────┘
```

### Hybrid Processing

- **Online:** Claude API handles entity extraction, topic inference, inference summaries, and title generation in a single API call. Entities are normalized (digits for numbers, singular form, 1-4 words max).
- **Offline:** Apple NaturalLanguage framework provides basic NER — person names, places, organizations. No topics, summaries, or titles without cloud.

### Topic Approval Flow

When Claude suggests a topic that doesn't already exist:
1. Existing topics → auto-assigned to the entry
2. New topics → queued in `TopicApprovalService`
3. User sees a dialog: "Add [topic]?" → Add / Not Now
4. Approved topics are created and linked; rejected suggestions are discarded

### Edit & Re-inference

When the user edits entry text (swipe right → edit):
- Old entities, inference summary, topics, and processing tasks are cleared
- New processing task is created
- Entry is re-processed through the full pipeline
- Tag-only edits (removing entity chips) don't trigger re-processing

## Voice Input

### Capture
- `SpeechService` uses `AVAudioEngine` + `SFSpeechRecognizer` for real-time transcription
- Audio is simultaneously written to a `.caf` file in the app's `Documents/VoiceEntries/` directory
- Configurable via "Save voice entries" toggle in Settings
- If saving is off, the audio file is deleted after transcription

### Playback
- `AudioPlayerService` wraps `AVAudioPlayer` for in-app playback
- Play/stop button shown on entry cards with saved audio
- Share button exports the audio file via `UIActivityViewController`
- Audio can be discarded from the edit screen

## Siri Integration

App Intents framework provides Siri shortcuts:
- "Capture in Hi Mem" / "Log in Hi Mem" / "Save to Hi Mem"
- Siri asks "What do you want to remember?"
- Response is saved as a `siri` input type entry and processed

## Search

`SearchEngine` supports:
- Full-text search on entry content and titles
- Entity-type filtering (project, person, issue, idea, next_action)
- Topic-based filtering via the tab bar
- Relevance scoring based on match frequency and proportion

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| SwiftUI over UIKit | Greenfield iOS 17+ app; declarative UI maps naturally to the card-based design |
| Core Data over SwiftData | More mature, better background context support for processing pipeline |
| Single Claude API call | Entity extraction + topics + summary + title in one request reduces latency and cost |
| API key in Keychain | Never in source code; iOS Keychain encrypted, device-only |
| Topics user-controlled | AI suggests, user approves — builds trust and prevents topic sprawl |
| Optimistic UI updates | Feedback and delete update the display model immediately, persist async |
| Mock data mode | `useMockData` flag in ViewModel for UI development without Core Data |

## File Structure

```
MemoryStream/
├── MemoryStream.xcodeproj/
└── MemoryStream/
    ├── App/
    │   ├── MemoryStreamApp.swift          # App entry point
    │   └── HiMemShortcuts.swift           # Siri App Intents
    ├── Assets.xcassets/                    # App icon
    ├── Models/
    │   ├── JournalEntry.swift
    │   ├── ExtractedEntity.swift
    │   ├── ProcessingTask.swift
    │   ├── InferenceSummary.swift
    │   ├── Topic.swift
    │   ├── MediaReference.swift
    │   └── MemoryStream.xcdatamodeld/     # Core Data schema
    ├── ViewModels/
    │   ├── JournalViewModel.swift         # Main journal state
    │   ├── SearchViewModel.swift          # Search state
    │   └── DisplayModels.swift            # View-layer structs
    ├── Views/
    │   ├── Journal/
    │   │   ├── JournalView.swift          # Main screen
    │   │   ├── EntryCardView.swift        # Entry cards + subviews
    │   │   └── EntryEditorView.swift      # Edit screen
    │   ├── Input/
    │   │   └── InputBarView.swift         # Bottom input bar
    │   ├── Search/
    │   │   └── SearchView.swift           # Search screen
    │   └── Components/
    │       ├── SiriShortcutBanner.swift
    │       ├── TopicTabBar.swift
    │       └── SettingsView.swift
    └── Services/
        ├── Storage/
        │   ├── StorageService.swift        # Core Data operations
        │   └── KeychainService.swift       # Secure credential storage
        ├── AI/
        │   ├── ClaudeAPIService.swift       # Anthropic API client
        │   ├── LocalEntityExtractor.swift   # On-device NER
        │   ├── SpeechService.swift          # Voice recording + transcription
        │   ├── AudioPlayerService.swift     # Voice playback
        │   └── SearchEngine.swift           # Core Data search queries
        ├── Processing/
        │   ├── ProcessingEngine.swift       # Hybrid AI orchestrator
        │   └── TopicApprovalService.swift   # New topic approval queue
        └── Network/
            └── ConnectivityMonitor.swift    # Online/offline detection
```

## Build & Deploy

```bash
# Build for simulator
xcodebuild -project MemoryStream.xcodeproj -scheme MemoryStream \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build

# Build for device
xcodebuild -project MemoryStream.xcodeproj -scheme MemoryStream \
  -destination 'id=DEVICE_UUID' \
  -configuration Debug -allowProvisioningUpdates build

# Install on device
xcrun devicectl device install app --device DEVICE_UUID \
  path/to/Build/Products/Debug-iphoneos/MemoryStream.app

# Launch on device
xcrun devicectl device process launch --device DEVICE_UUID com.himem.app
```

**Signing:** Apple Development, Team ID GSZN2G9HR3 (Personal Team). Free signing expires after 7 days.

**Bundle ID:** com.himem.app
