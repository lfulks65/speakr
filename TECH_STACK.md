# Speakr Technology Stack

## Overview
This document defines the technology stack for Speakr, a local-first speech-to-text application for macOS.

## Platform Requirements

### Minimum macOS Version
- **macOS 14.0 (Sonoma)** - Required for:
  - Modern SwiftUI features (@Observable macro)
  - AVFoundation audio improvements
  - Advanced security and privacy controls
  - Background processing capabilities

### Swift Version
- **Swift 5.9+** - Required for:
  - `@Observable` macro (replaces ObservableObject)
  - `if`/`switch` expressions
  - `consume` operator for performance
  - ` borrowing` and `consuming` parameter modifiers

## UI Framework

### Primary: SwiftUI
- Native macOS look and feel
- Built-in accessibility support
- Reactive data flow with `@Observable`
- Efficient view updates

### App Architecture Pattern
- **MVVM (Model-View-ViewModel)** with modern SwiftUI
- `@Observable` classes for state management
- Dependency injection via environment
- Combine for async data streams

## Audio System

### Recording
- **AVFoundation** - Core audio capture
  - `AVAudioEngine` for low-latency recording
  - `AVAudioSession` (when iOS port is added)
  - Support for system audio capture (future feature)

### Audio Processing
- Built-in audio format conversion
- Noise reduction pipeline (optional, post-MVP)
- Sample rate normalization (16kHz for Whisper)

## Transcription Backend

### Whisper Implementation: whisper.cpp
- **Repository**: https://github.com/ggerganov/whisper.cpp
- **Rationale**:
  - Pure C/C++ implementation
  - Optimized for Apple Silicon (ARM NEON, Metal GPU)
  - No external dependencies
  - Supports Core ML models
  - Active community and maintenance

### Model Management
- Models stored in `~/Library/Application Support/Speakr/Models`
- Support for tiny, base, small, medium, large-v3
- Automatic model download and caching
- Core ML conversion for native performance

## Data Storage

### User Preferences
- **UserDefaults** - Simple key-value storage
  - Recording settings
  - UI preferences
  - Keyboard shortcuts

### Transcription History
- **SQLite** - Local structured storage
  - Transcriptions table: id, text, timestamp, audioHash, duration
  - FTS5 for full-text search
  - Indexed for fast queries

### Audio Cache
- Temporary storage in `~/Library/Caches/Speakr/Audio`
- Automatic cleanup (configurable retention)
- Optional permanent storage for important recordings

## Security & Privacy

### Data Handling
- All transcription happens **locally**
- No audio or text sent to external servers
- Sandbox-compliant file access
- Secure Enclave integration for sensitive data (future)

### Permissions
- **Microphone** - Required for recording
- **Accessibility** - Required for global hotkeys
- **Files and Folders** - For saving transcriptions

## Build System

### Swift Package Manager
- Native Swift build tooling
- Clean dependency management
- Cross-platform structure for future iOS/Android

### Xcode Integration
- Package.swift can be opened directly in Xcode
- Supports debugging, profiling, and testing
- App signing and notarization ready

## Testing Strategy

### Unit Tests
- XCTest for core logic
- Isolated component testing
- Mock audio engine for testing

### Integration Tests
- End-to-end transcription flow
- Audio pipeline validation
- Database operations

### UI Tests
- SwiftUI ViewInspector for unit testing views
- XCTest UI testing for critical paths

## CI/CD

### GitHub Actions
- Build on macOS runner
- Run test suite
- Code quality checks (SwiftLint)
- Automated releases with signed binaries

## Performance Considerations

### Memory Management
- Lazy loading of Whisper models
- Streaming audio processing
- Automatic cleanup of resources

### Battery & Thermal
- Efficient audio buffer sizing
- Background task scheduling
- GPU offload for transcription (Metal)

## Future-Proofing

### Cross-Platform Structure
- Core engine (`SpeakrCore`) platform-agnostic
- Platform-specific UI layers
- Shared model definitions

### Sync Architecture (Future)
- iCloudKit integration option
- End-to-end encryption for sync
- Conflict resolution strategies

### Android Considerations
- Whisper.cpp supports Android
- Core logic in portable C++
- Kotlin Multiplatform Mobile (KMM) compatibility

## Dependencies Summary

| Component | Technology | Notes |
|-----------|------------|-------|
| Language | Swift 5.9+ | Modern concurrency, @Observable |
| UI | SwiftUI | Native macOS, Sonoma features |
| Audio | AVFoundation | Core framework, no deps |
| Transcription | whisper.cpp | Git submodule, prebuilt lib |
| Storage | SQLite | GRDB.swift consideration |
| Preferences | UserDefaults | Built-in |
| Build | SwiftPM | No CocoaPods/Carthage |
| CI/CD | GitHub Actions | macOS runners |

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-06 | Swift 5.9 / macOS 14 | @Observable, modern SwiftUI |
| 2026-04-06 | whisper.cpp | Best local Whisper performance |
| 2026-04-06 | SwiftPM | Clean, modern, future-proof |
| 2026-04-06 | SQLite for history | Reliable, searchable, local |
| 2026-04-06 | No external deps for core | Minimize supply chain risk |
