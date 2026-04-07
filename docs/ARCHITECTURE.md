# Speakr Architecture

## Overview

Speakr is a local-first speech-to-text application built with a modular architecture that separates concerns between the core engine and platform-specific UI layers.

## Project Structure

```
Speakr/
├── Sources/
│   ├── SpeakrApp/              # macOS SwiftUI Application
│   │   ├── SpeakrApp.swift     # App entry point
│   │   └── Views/                 # SwiftUI views
│   │       ├── ContentView.swift
│   │       ├── SidebarView.swift
│   │       ├── TranscriptionDetailView.swift
│   │       ├── SettingsView.swift
│   │       └── MenuBarView.swift
│   │
│   └── SpeakrCore/             # Core transcription engine
│       ├── Engine/
│       │   └── TranscriptionEngine.swift
│       ├── Audio/
│       │   └── AudioRecorder.swift
│       ├── Transcription/
│       │   └── WhisperTranscriber.swift
│       ├── Settings/
│       │   └── SettingsStore.swift
│       ├── Models/
│       │   ├── Transcription.swift
│       │   └── RecordingSession.swift
│       ├── Database/
│       │   └── TranscriptionStore.swift
│       └── Utils/
│           ├── AudioUtils.swift
│           └── DirectoryManager.swift
│
├── Tests/                          # Test suites
│   ├── SpeakrAppTests/
│   └── SpeakrCoreTests/
│
├── Resources/                      # Assets, models
│   └── Models/
│
└── Package.swift                   # SwiftPM manifest
```

## Module Descriptions

### SpeakrApp (macOS UI Layer)

**Responsibilities:**
- Main application lifecycle
- Window management
- Menu bar extra
- User interface (SwiftUI)
- System integration (permissions, shortcuts)

**Key Components:**
- `SpeakrApp.swift` - App entry point with WindowGroup, Settings, MenuBarExtra
- Views for displaying transcriptions, settings, and controls

### SpeakrCore (Core Engine)

**Responsibilities:**
- Audio recording and processing
- Speech-to-text transcription
- Data persistence
- Settings management
- Cross-platform compatibility

#### Engine Module
- `TranscriptionEngine` - Main orchestrator coordinating recording and transcription

#### Audio Module
- `AudioRecorder` - Captures audio from microphone using AVFoundation
- Handles 16kHz mono PCM format for Whisper compatibility

#### Transcription Module
- `WhisperTranscriber` - Interface to whisper.cpp
- Model management and inference
- Supports multiple model sizes (tiny → large-v3)

#### Settings Module
- `SettingsStore` - User preferences using UserDefaults
- Observable state for UI binding

#### Models Module
- `Transcription` - Data model for saved transcriptions
- `RecordingSession` - Active or completed recording session
- `TranscriptionSegment` - Timestamped segment data

#### Database Module
- `TranscriptionStore` - SQLite persistence with FTS5 search

#### Utils Module
- `AudioUtils` - Audio format conversion and processing
- `DirectoryManager` - File system operations and path management

## Data Flow

```
┌─────────────────┐     ┌──────────────────────┐     ┌──────────────────┐
│   User Action   │────▶│ TranscriptionEngine  │────▶│  AudioRecorder   │
│  (Start Record) │     │   (Orchestrator)     │     │ (AVAudioEngine)  │
└─────────────────┘     └──────────────────────┘     └──────────────────┘
                                 │                           │
                                 │                           ▼
                                 │                    ┌──────────────┐
                                 │                    │ Audio Buffer │
                                 │                    └──────────────┘
                                 ▼                           │
                        ┌───────────────────┐                │
                        │  WhisperTranscriber│◄──────────────┘
                        │    (whisper.cpp)   │   (File on Stop)
                        └───────────────────┘
                                 │
                                 ▼
                        ┌───────────────────┐
                        │ TranscriptionStore │
                        │     (SQLite)       │
                        └───────────────────┘
```

## State Management

### Modern SwiftUI (@Observable)
- `TranscriptionEngine` uses `@Observable` macro
- Automatic view updates without @Published
- Better performance with fine-grained tracking

### Actor Isolation
- `AudioRecorder` and `WhisperTranscriber` are actors
- Thread-safe concurrent access
- Async/await pattern throughout

## Dependencies

### External Dependencies
- **whisper.cpp** - Integrated as C++ library (no Swift package)
- **SQLite3** - System framework

### System Frameworks
- AVFoundation - Audio recording
- Foundation - Core functionality
- SwiftUI - User interface

## Build Configuration

### Swift Package Manager
- Clean, dependency-minimal build
- Supports Xcode 15+ development
- Cross-platform structure ready for future iOS/Android

### Platforms
- macOS 14.0+ (minimum)
- Architecture: Universal (arm64 + x86_64)

## Security & Privacy

### Local-First Design
- All processing on-device
- No network calls for transcription
- Open source for transparency

### Permissions
- Microphone access (NSMicrophoneUsageDescription)
- Accessibility for global hotkeys (future)

## Future Considerations

### Android Support
- Core engine uses portable C++ (whisper.cpp)
- JVM bindings for Kotlin integration
- Separate UI layer in Jetpack Compose

### Cross-Device Sync
- iCloudKit integration option
- Encryption at rest and in transit
- Conflict-free replicated data types (CRDTs)

### Performance
- Metal GPU acceleration for transcription
- Lazy model loading
- Streaming audio processing
