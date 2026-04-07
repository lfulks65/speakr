# Speakr Project Structure

## Overview

This document describes the modular architecture of the Speakr macOS application.

## Module Structure

The project uses **Swift Package Manager** with a modular architecture consisting of 6 main modules:

### 1. AudioCapture
**Purpose:** Audio recording from microphone

- Uses `AVFoundation` for low-level audio capture
- Records at 16kHz mono (optimal for Whisper)
- Provides audio level visualization data
- Handles permission requests

**Key Files:**
- `Sources/AudioCapture/AudioCapture.swift`

**Linked Frameworks:**
- AVFoundation
- Foundation

---

### 2. TranscriptionEngine
**Purpose:** Converts audio to text using Whisper

- Will integrate with whisper.cpp for local transcription
- Supports multiple model sizes (tiny to large-v3)
- Provides streaming and batch transcription modes
- Manages model loading and caching

**Key Files:**
- `Sources/TranscriptionEngine/TranscriptionEngine.swift`

**Dependencies:**
- AudioCapture

**Linked Frameworks:**
- Foundation
- Combine

---

### 3. HotkeyService
**Purpose:** Global keyboard shortcuts

- Registers global hotkeys using Carbon Event APIs
- Default shortcut: Option + Space
- Handles accessibility permissions
- Persists hotkey preferences

**Key Files:**
- `Sources/HotkeyService/HotkeyService.swift`

**Dependencies:**
- Settings

**Linked Frameworks:**
- Carbon
- AppKit
- Foundation

---

### 4. TextOutput
**Purpose:** Text insertion into applications

- Three output modes: clipboard, type simulation, paste
- Clipboard: Copies to system pasteboard
- Type: Simulates keystrokes character by character
- Paste: Inserts into focused text field using Cmd+V

**Key Files:**
- `Sources/TextOutput/TextOutput.swift`

**Linked Frameworks:**
- AppKit
- Foundation

---

### 5. Settings
**Purpose:** User preferences and configuration

- UserDefaults-backed storage
- Codable settings model
- Supports import/export
- Observable for SwiftUI integration

**Key Files:**
- `Sources/Settings/Settings.swift`

**Linked Frameworks:**
- Foundation

---

### 6. AppUI
**Purpose:** Main application entry point and UI

- Executable target
- SwiftUI-based interface
- Menu bar extra + main window
- Integrates all other modules

**Key Files:**
- `Sources/AppUI/SpeakrApp.swift` - App entry point
- `Sources/AppUI/AppState.swift` - Global state management
- `Sources/AppUI/Views/MenuBarView.swift` - Menu bar UI
- `Sources/AppUI/Views/MainWindowView.swift` - Main window UI
- `Sources/AppUI/Views/SettingsView.swift` - Settings panels

**Dependencies:**
- AudioCapture
- TranscriptionEngine
- HotkeyService
- TextOutput
- Settings

---

## Dependencies Graph

```
AppUI (executable)
├── AudioCapture
├── TranscriptionEngine (depends on AudioCapture)
├── HotkeyService (depends on Settings)
├── TextOutput
└── Settings
```

## Resources

- `Resources/Info.plist` - App metadata and permissions
- `Resources/Speakr.entitlements` - Security entitlements
  - Microphone access
  - Accessibility permissions
  - App sandbox
- `Resources/Models/` - Whisper model files (downloaded at runtime)

## Tests

Each module has corresponding tests:

- `Tests/AudioCaptureTests/`
- `Tests/TranscriptionEngineTests/`
- `Tests/HotkeyServiceTests/`
- `Tests/TextOutputTests/`
- `Tests/SettingsTests/`

## Build Configuration

### Swift Compiler Settings
- Minimum Swift version: 5.9
- StrictConcurrency enabled for all modules
- Target platform: macOS 14.0+

### Code Signing
- Entitlements file: `Resources/Speakr.entitlements`
- Required capabilities:
  - Audio input (microphone)
  - Accessibility (global hotkeys)
  - User-selected file access

## Future Module Additions

Planned modules for future features:

1. **TranscriptionHistory** - SQLite-based storage for transcription history
2. **SyncService** - iCloud/CloudKit sync support (future)
3. **AudioProcessing** - Noise reduction and audio enhancement
