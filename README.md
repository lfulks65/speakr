# Speakr

A local-first, privacy-focused voice-to-text app for macOS. Speak into any text field and your words appear instantly — no cloud, no subscription, no data leaves your machine.

## Features

- **Local transcription** — powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit) running entirely on-device
- **Auto-paste** — transcribed text is pasted directly into whatever app you were using (Cursor, Discord, Chrome, Slack, etc.)
- **Inline mic button** — a floating neon mic icon appears above editable text fields; click to record without switching apps
- **Global hotkey** — press `⌥Space` anywhere to start/stop recording
- **Multiple model sizes** — tiny (~75 MB) through large-v3 (~2.9 GB), selectable in settings
- **Multi-language** — supports 12 languages plus auto-detect
- **Menu bar app** — lives in the status bar, out of your way
- **100% private** — no audio, text, or telemetry ever leaves your device

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1/M2/M3) or Intel Mac
- ~150 MB disk space (base model)

## Install

### From DMG

Download the latest `.dmg` from [Releases](https://github.com/lfulks65/speakr/releases), open it, and drag Speakr to Applications.

### From Source

```bash
git clone https://github.com/lfulks65/speakr.git
cd speakr

# Build and install to /Applications
./build-app.sh

# Or create a distributable DMG
./package-dmg.sh
```

Requires Xcode 15+ and Swift 5.9+.

## Permissions

On first launch, Speakr will prompt for two permissions:

1. **Microphone** — to record your voice
2. **Accessibility** — to paste text into other apps and show the floating mic button

Grant both in **System Settings → Privacy & Security**.

> **Note**: Since the app is ad-hoc signed (not notarized), you may need to right-click → Open on the first launch, or click "Open Anyway" in System Settings → Privacy & Security.

## Usage

1. Click into any text field in any app
2. Press **⌥Space** (or click the floating mic button)
3. Speak
4. Press **⌥Space** again (or click stop)
5. Your words are pasted into the text field

The transcribed text is also always copied to the clipboard as a fallback.

## Architecture

```
Sources/
├── AppUI/                    # SwiftUI app, menu bar, inline trigger
│   ├── WisprFlowApp.swift    # App entry point and scene config
│   ├── AppState.swift        # Observable state, recording/paste logic
│   ├── InlineTriggerService  # Floating mic button over text fields
│   └── Views/                # Settings, onboarding, menu bar UI
├── AudioCapture/             # AVAudioRecorder wrapper
├── TranscriptionEngine/      # WhisperKit integration
├── HotkeyService/            # Global ⌥Space via Carbon events
├── TextOutput/               # Clipboard + ⌘V paste via CGEvent
└── Settings/                 # UserDefaults-backed observable store
```

All modules are separate Swift Package Manager targets with clean dependency boundaries.

## Tech Stack

- **Swift 6** with strict concurrency
- **SwiftUI** with `@Observable` state management
- **WhisperKit** for on-device transcription (Metal GPU accelerated)
- **AVFoundation** for audio capture
- **Carbon/HIToolbox** for global hotkeys
- **Accessibility API** for text field detection and text insertion
- **CGEvent** for keyboard simulation (⌘V paste)

## Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Build .app bundle and install to /Applications
./build-app.sh

# Create distributable DMG
./package-dmg.sh

# Run tests
swift test
```

## Known Limitations

- Auto-paste requires Accessibility permission and works via ⌘V simulation — some apps with non-standard input handling may not receive the paste
- Apps like Krisp that pop modals when the microphone is released can briefly steal focus; the retry logic handles most cases
- The floating mic button only appears for recognized editable text fields (AXTextField, AXTextArea, AXWebArea with text cursor)

## Privacy

Speakr is designed with privacy as a core principle:

- All transcription runs locally via WhisperKit — no network calls for inference
- No audio recordings are uploaded anywhere
- No analytics, telemetry, or tracking of any kind
- Fully open source

Your voice data stays on your machine.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — Swift interface to Whisper models with CoreML acceleration
- [OpenAI Whisper](https://github.com/openai/whisper) — the foundation transcription model
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — high-performance C++ Whisper implementation
