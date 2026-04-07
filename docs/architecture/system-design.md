# Speakr Alternative - System Architecture Design

## Overview

This document defines the system architecture for a local-first Whisper-based transcription application for macOS, with future extensibility for Android and cross-device synchronization.

---

## 1. High-Level Architecture

```mermaid
flowchart TB
    subgraph "Presentation Layer"
        UI[App UI<br/>SwiftUI]
        MenuBar[Menu Bar Icon<br/>Status/Control]
        Shortcuts[Global Shortcuts<br/>Hotkey Manager]
    end

    subgraph "Application Layer"
        AudioManager[Audio Manager<br/>Recording Control]
        TranscriptionService[Transcription Service<br/>Orchestration]
        ConfigManager[Configuration Manager<br/>Settings/Preferences]
        TextInjector[Text Injector<br/>Paste/Type Output]
    end

    subgraph "Domain Layer"
        AudioPipeline[Audio Pipeline<br/>Capture & Preprocessing]
        WhisperEngine[Whisper Engine<br/>Inference]
        SessionManager[Session Manager<br/>History/State]
    end

    subgraph "Infrastructure Layer"
        CoreAudio[Core Audio<br/>AVFoundation]
        WhisperCPP[Whisper.cpp<br/>Local Inference]
        FileStorage[(File Storage<br/>Models & Cache)]
        Keychain[(Keychain<br/>Credentials)]
    end

    subgraph "Future: Sync Layer"
        SyncEngine[Sync Engine<br/>iCloud/Dropbox]
        AndroidBridge[Android Bridge<br/>Future Support]
    end

    UI --> AudioManager
    UI --> ConfigManager
    MenuBar --> AudioManager
    Shortcuts --> AudioManager
    
    AudioManager --> AudioPipeline
    TranscriptionService --> AudioPipeline
    TranscriptionService --> WhisperEngine
    TranscriptionService --> TextInjector
    
    AudioPipeline --> CoreAudio
    WhisperEngine --> WhisperCPP
    WhisperEngine --> FileStorage
    ConfigManager --> FileStorage
    ConfigManager --> Keychain
    
    SessionManager -.-> SyncEngine
    SyncEngine -.-> AndroidBridge
```

### Architecture Pattern: Clean Architecture / Layered Architecture

The system follows a layered architecture with clear separation of concerns:

| Layer | Responsibility | Technology |
|-------|---------------|------------|
| Presentation | User interface, visual feedback | SwiftUI, AppKit |
| Application | Use cases, workflow orchestration | Swift (async/await) |
| Domain | Business logic, audio processing | Swift, AudioToolbox |
| Infrastructure | External systems, hardware | CoreAudio, Whisper.cpp |
| Future: Sync | Cross-device synchronization | CloudKit, FileProvider |

---

## 2. Component Diagram

```mermaid
flowchart LR
    subgraph "Input"
        Mic[Microphone<br/>System Audio]
    end

    subgraph "Processing Pipeline"
        AC[Audio Capture<br/>AVAudioRecorder]
        AP[Audio Preprocessing<br/>Resample/Normalize]
        VAD[Voice Activity Detection<br/>Optional]
        
        AC -->|Raw PCM<br/>44.1kHz/16bit| AP
        AP -->|Normalized<br/>16kHz/16bit| VAD
    end

    subgraph "Inference"
        WE[Whisper Engine<br/>whisper.cpp]
        Lang[Language Detection<br/>Auto/Manual]
        
        VAD -->|Audio Segments| WE
        Lang --> WE
    end

    subgraph "Output"
        TS[Transcription Stream<br/>Incremental]
        TP[Text Processing<br/>Formatting/Punctuation]
        TI[Text Injection<br/>Paste/Type]
        
        WE -->|Raw Text| TS
        TS --> TP
        TP -->|Formatted Text| TI
    end

    subgraph "Control"
        SM[State Machine<br/>Recording States]
        EM[Error Manager<br/>Recovery Logic]
        
        SM --> AC
        SM --> WE
        EM --> SM
    end

    Mic --> AC
```

### Component Responsibilities

| Component | Input | Output | Responsibility |
|-----------|-------|--------|----------------|
| Audio Capture | Microphone stream | Raw PCM buffer | Capture system audio with configurable quality |
| Audio Preprocessing | Raw PCM | Normalized audio | Resample to 16kHz, normalize levels, noise reduction |
| Voice Activity Detection | Audio buffer | Speech segments | Detect voice vs silence (optional, reduces compute) |
| Whisper Engine | Audio segments | Text tokens | Run whisper.cpp inference with configured model |
| Transcription Stream | Text tokens | Complete sentences | Buffer tokens, emit finalized text |
| Text Processing | Raw text | Formatted text | Apply formatting rules, punctuation fixes |
| Text Injection | Formatted text | OS text input | Simulate paste or keystroke injection |
| State Machine | User actions, events | State transitions | Manage recording lifecycle |
| Error Manager | Errors from any stage | Recovery actions | Handle and recover from failures |

---

## 3. Data Flow Diagram

```mermaid
sequenceDiagram
    participant User
    participant UI as App UI
    participant SM as State Machine
    participant AC as Audio Capture
    participant AP as Audio Pipeline
    participant WE as Whisper Engine
    participant TS as Text Stream
    participant TI as Text Injector

    User->>UI: Press Hotkey (Start)
    UI->>SM: requestStartRecording()
    SM->>SM: State: idle → recording
    SM->>AC: startRecording()
    AC->>AC: Initialize AVAudioRecorder
    AC->>AP: Audio Buffer Stream
    
    loop Every 100-500ms
        AP->>AP: Preprocess chunk
        AP->>WE: Send audio segment
        WE->>WE: Run inference
        WE->>TS: Emit partial tokens
    end
    
    User->>UI: Release Hotkey (Stop)
    UI->>SM: requestStopRecording()
    SM->>AC: stopRecording()
    AC->>AP: Final buffer
    SM->>SM: State: recording → processing
    
    AP->>WE: Final audio segment
    WE->>WE: Complete inference
    WE->>TS: Final tokens
    
    TS->>TS: Assemble transcription
    TS->>SM: Transcription complete
    SM->>SM: State: processing → outputting
    
    SM->>TI: injectText(transcription)
    TI->>TI: Copy to clipboard
    TI->>TI: Simulate Cmd+V
    TI->>SM: Injection complete
    
    SM->>SM: State: outputting → idle
    SM->>UI: Update UI (ready)
    UI->>User: Visual feedback (success)
```

### Data Transformation Stages

| Stage | Data Format | Size/Rate | Processing |
|-------|-------------|-----------|------------|
| Raw Capture | PCM 44.1kHz, 16-bit | ~86 KB/s | Direct from microphone |
| Preprocessed | PCM 16kHz, 16-bit | ~32 KB/s | Resampled, normalized |
| Whisper Input | Float32 array | 16k samples/sec | Normalized to [-1, 1] |
| Whisper Output | Token stream | Variable | Word-level timestamps |
| Final Text | UTF-8 string | Variable | Punctuation applied |

---

## 4. Module Boundaries and Interfaces

### Module Structure

```
Speakr/
├── Presentation/
│   ├── MenuBarController      # Menulet, status icon
│   ├── RecordingView          # Recording overlay/window
│   ├── SettingsView           # Preferences UI
│   └── ShortcutManager        # Global hotkey handling
├── Application/
│   ├── RecordingCoordinator   # Recording session orchestration
│   ├── TranscriptionWorkflow  # End-to-end transcription flow
│   ├── SettingsService        # User preferences management
│   └── PermissionManager      # Mic/accessibility permissions
├── Domain/
│   ├── Audio/
│   │   ├── AudioRecorder      # Recording interface
│   │   ├── AudioProcessor     # Preprocessing pipeline
│   │   └── AudioBuffer        # Audio data structures
│   ├── Transcription/
│   │   ├── WhisperEngine      # Inference wrapper
│   │   ├── TranscriptionSession
│   │   └── TextFormatter      # Post-processing
│   └── Models/
│       ├── TranscriptionResult
│       ├── RecordingSession
│       └── AppConfiguration
└── Infrastructure/
    ├── Audio/
    │   └── CoreAudioRecorder  # AVFoundation implementation
    ├── Whisper/
    │   └── WhisperCppWrapper  # whisper.cpp binding
    ├── Storage/
    │   ├── FileStorage        # Local file operations
    │   └── KeychainStorage    # Secure storage
    └── System/
        ├── TextInjector       # Paste/keystroke simulation
        └── AccessibilityHelper
```

### Public Interfaces

#### AudioRecorder Protocol
```swift
protocol AudioRecorder {
    var state: AudioRecorderState { get }
    var audioStream: AsyncStream<AudioBuffer> { get }
    
    func start() async throws
    func stop() async
    func configure(_ config: AudioConfiguration) async
}

enum AudioRecorderState {
    case idle, preparing, recording, stopping, error(AudioError)
}
```

#### WhisperEngine Protocol
```swift
protocol WhisperEngine {
    var isModelLoaded: Bool { get }
    var partialResults: AsyncStream<TranscriptionSegment> { get }
    
    func loadModel(_ model: WhisperModel) async throws
    func transcribe(audio: AudioBuffer) async throws -> TranscriptionResult
    func transcribeStream(audioStream: AsyncStream<AudioBuffer>) async throws
    func stop() async
}

struct TranscriptionResult {
    let text: String
    let segments: [TranscriptionSegment]
    let language: String
    let duration: TimeInterval
}
```

#### TextInjector Protocol
```swift
protocol TextInjector {
    func inject(_ text: String, method: InjectionMethod) async throws
}

enum InjectionMethod {
    case paste           // Simulate Cmd+V
    case type           // Simulate keystrokes
    case clipboardOnly  // Just copy to clipboard
}
```

#### StateMachine Interface
```swift
protocol RecordingStateMachine {
    var currentState: RecordingState { get }
    var stateStream: AsyncStream<RecordingState> { get }
    
    func transition(to event: StateEvent) async throws
}

enum RecordingState {
    case idle
    case recording(startTime: Date)
    case processing(audioData: AudioData)
    case outputting(transcription: TranscriptionResult)
    case error(StateError)
}
```

---

## 5. State Machine Diagram

```mermaid
stateDiagram-v2
    [*] --> Idle: App Launch
    
    Idle --> Recording: Hotkey Pressed
    Idle --> CheckingPermissions: First Launch
    
    CheckingPermissions --> Idle: Permissions Granted
    CheckingPermissions --> Error: Permissions Denied
    
    Recording --> Processing: Hotkey Released / Timeout
    Recording --> Idle: Cancel Signal
    Recording --> Error: Audio Capture Failed
    
    Processing --> Outputting: Transcription Complete
    Processing --> Idle: Cancel / Timeout
    Processing --> Error: Whisper Engine Error
    
    Outputting --> Idle: Text Injected Successfully
    Outputting --> Error: Injection Failed
    
    Error --> Idle: Recover / Retry
    Error --> [*]: Fatal Error / Quit
    
    Idle --> [*]: Quit App
    
    note right of Recording
        Audio capture active
        Visual indicator shown
        Partial transcription possible
    end note
    
    note right of Processing
        Whisper inference running
        Progress indicator
        Blocking operation
    end note
    
    note right of Outputting
        Text being injected
        Brief operation
        Success feedback
    end note
```

### State Transitions Table

| Current State | Event | Next State | Actions |
|---------------|-------|------------|---------|
| Idle | Hotkey Press | Recording | Start audio capture, show UI |
| Idle | Settings Open | Idle | Show settings window |
| Recording | Hotkey Release | Processing | Stop capture, start transcription |
| Recording | Timeout | Processing | Auto-stop after max duration |
| Recording | Cancel | Idle | Discard recording, cleanup |
| Processing | Success | Outputting | Format text, prepare injection |
| Processing | Failure | Error | Log error, notify user |
| Outputting | Success | Idle | Cleanup, show success |
| Outputting | Failure | Error | Log error, copy to clipboard fallback |
| Error | Retry | Previous | Attempt recovery |
| Error | Dismiss | Idle | Clear error state |

---

## 6. Error Handling Strategy

### Error Classification

```mermaid
flowchart TD
    E[Error] --> PE[Permission Errors]
    E --> AE[Audio Errors]
    E --> IE[Inference Errors]
    E --> SE[System Errors]
    
    PE --> Mic[Microphone Access Denied]
    PE --> Acc[Accessibility Access Denied]
    
    AE --> Init[Audio Initialization Failed]
    AE --> Capt[Capture Interrupted]
    AE --> Form[Unsupported Format]
    
    IE --> Load[Model Load Failed]
    IE --> Mem[Out of Memory]
    IE --> Inf[Inference Error]
    
    SE --> Inj[Injection Failed]
    SE --> Sto[Storage Error]
    SE --> Unk[Unknown Error]
```

### Error Handling Patterns

| Error Type | Severity | User Action | Fallback Behavior |
|------------|----------|-------------|-------------------|
| Microphone Denied | Fatal | Grant in System Preferences | Show instructions, disable recording |
| Accessibility Denied | Warning | Grant in System Preferences | Fallback to clipboard-only mode |
| Audio Init Failed | Recoverable | Retry | Show error, return to idle |
| Capture Interrupted | Recoverable | Retry | Auto-restart if possible |
| Model Load Failed | Fatal | Reinstall app | Show error dialog, quit |
| Out of Memory | Recoverable | Close other apps | Use smaller model, retry |
| Inference Error | Recoverable | Retry | Discard audio, return to idle |
| Injection Failed | Recoverable | Manual paste | Copy to clipboard, notify user |

### Error Recovery Flow

```swift
enum ErrorRecoveryStrategy {
    case immediate          // Auto-retry once
    case exponentialBackoff // Retry with delays
    case fallback           // Use alternative method
    case userIntervention   // Show dialog, wait for user
    case fatal              // Log and quit
}

protocol ErrorHandler {
    func handle(_ error: AppError, context: ErrorContext) -> ErrorRecoveryStrategy
    func recover(from error: AppError) async -> Bool
}
```

### Resilience Patterns

1. **Circuit Breaker**: If Whisper fails N times, temporarily switch to fallback mode
2. **Retry with Backoff**: Transient errors retry with exponential delays (100ms, 200ms, 400ms)
3. **Graceful Degradation**: If text injection fails, always fallback to clipboard
4. **Partial Results**: Even on error, return any transcribed text to user

---

## 7. Thread Model and Concurrency

### Concurrency Architecture

```mermaid
flowchart TB
    subgraph "Main Thread"
        UI[UI Updates<br/>SwiftUI]
        SM[State Machine<br/>State Transitions]
    end

    subgraph "Audio Queue"
        AC[Audio Capture<br/>Real-time]
        AP[Audio Preprocessing<br/>Ring Buffer]
    end

    subgraph "Inference Queue"
        WE[Whisper Engine<br/>CPU/GPU Heavy]
        TS[Token Streaming<br/>Callback-based]
    end

    subgraph "I/O Queue"
        TI[Text Injection<br/>System Events]
        FS[File Operations<br/>Model Loading]
    end

    subgraph "Global Concurrent"
        LOG[Logging<br/>Non-blocking]
        MET[Metrics<br/>Analytics]
    end

    UI -->|State Events| SM
    AC -->|Audio Buffers| AP
    AP -->|Processed Audio| WE
    WE -->|Text Tokens| TS
    TS -->|Complete Text| TI
    
    SM -.->|Async| AC
    SM -.->|Async| WE
    SM -.->|Async| TI
```

### Thread/Queue Assignments

| Component | Queue | QoS | Reason |
|-----------|-------|-----|--------|
| UI Updates | Main | User Interactive | SwiftUI requirement |
| State Machine | Main | User Initiated | Coordinates all operations |
| Audio Capture | Dedicated Audio | User Initiated | Real-time requirements |
| Audio Preprocessing | Concurrent | User Initiated | Keep up with real-time |
| Whisper Inference | Dedicated ML | Utility | CPU-intensive, can lag |
| Text Injection | Main | User Initiated | Accessibility API requirement |
| File I/O | Background | Background | Non-blocking operations |
| Logging | Concurrent | Background | Don't block main flow |

### Concurrency Patterns

#### Audio Pipeline (Producer-Consumer)
```swift
actor AudioPipeline {
    private let audioStream: AsyncStream<AudioBuffer>
    private let processedStream: AsyncStream<ProcessedAudio>
    
    func process() async {
        for await buffer in audioStream {
            let processed = await preprocess(buffer)
            await whisperEngine.consume(processed)
        }
    }
}
```

#### Whisper Inference (Actor Isolation)
```swift
actor WhisperEngine {
    private var context: WhisperContext?
    private var isProcessing = false
    
    func transcribe(_ audio: ProcessedAudio) async throws -> TranscriptionResult {
        guard !isProcessing else { throw .alreadyProcessing }
        isProcessing = true
        defer { isProcessing = false }
        
        return try await runInference(audio)
    }
}
```

#### State Machine (Main Actor)
```swift
@MainActor
class RecordingStateMachine: ObservableObject {
    @Published var state: RecordingState = .idle
    
    func transition(to event: StateEvent) async throws {
        // All state transitions on main thread
        // Coordinate async work on other queues
    }
}
```

### Synchronization Points

1. **Audio Buffer Ring**: Lock-free ring buffer between capture and preprocessing
2. **Transcription Queue**: Serialized access to Whisper engine (single inference at a time)
3. **State Access**: All state reads/writes through StateMachine actor
4. **Model Loading**: Exclusive access during model initialization

### Concurrency Safety Rules

1. Never block the audio capture thread
2. Whisper inference can be slow; emit partial results progressively
3. All UI updates on MainActor
4. Use Swift concurrency (async/await) throughout
5. Avoid locks; prefer actors and structured concurrency

---

## 8. Future Considerations

### Android Support Architecture

```mermaid
flowchart LR
    subgraph "Shared Core"
        RustCore[Core Logic<br/>Rust]
        WhisperLib[Whisper Library<br/>C++/Rust]
    end

    subgraph "macOS"
        MacUI[SwiftUI App]
        MacAudio[CoreAudio Bridge]
        MacBridge[Swift-Rust Bridge]
    end

    subgraph "Android"
        AndroidUI[Jetpack Compose]
        AndroidAudio[AAudio Bridge]
        AndroidBridge[JNI Bridge]
    end

    RustCore --> WhisperLib
    MacBridge --> RustCore
    AndroidBridge --> RustCore
    MacUI --> MacBridge
    MacAudio --> MacBridge
    AndroidUI --> AndroidBridge
    AndroidAudio --> AndroidBridge
```

### Sync Architecture (Future)

```mermaid
flowchart TB
    subgraph "Device A (Mac)"
        ALocal[(Local DB<br/>SQLite)]
        AEngine[Sync Engine]
    end

    subgraph "Cloud"
        Cloud[CloudKit / iCloud]
    end

    subgraph "Device B (Android)"
        BLocal[(Local DB<br/>Room)]
        BEngine[Sync Engine]
    end

    ALocal <--> AEngine
    AEngine <--> Cloud
    Cloud <--> BEngine
    BEngine <--> BLocal
```

---

## 9. Technology Stack Summary

| Component | Technology | Alternative |
|-----------|------------|-------------|
| UI Framework | SwiftUI | AppKit (fallback) |
| Audio Capture | AVFoundation | Core Audio (advanced) |
| Whisper Engine | whisper.cpp | Core ML conversion |
| Hotkeys | NSEvent/GlobalMonitor | CGEventTap |
| Text Injection | AXUIElement | AppleScript |
| Persistence | UserDefaults + Files | Core Data |
| Concurrency | Swift Concurrency | Combine |
| Testing | XCTest | Swift Testing |

---

## 10. Security Considerations

1. **Local-First**: All audio processing on-device; no cloud transcription
2. **Sandboxing**: Minimal entitlements; microphone and accessibility only
3. **Data Retention**: Configurable history; auto-delete after N days
4. **Clipboard**: Clear sensitive transcriptions from clipboard after timeout

---

## Appendix: File Organization

```
speakr/
├── Speakr/
│   ├── App/
│   │   └── SpeakrApp.swift
│   ├── Presentation/
│   │   ├── MenuBar/
│   │   ├── Recording/
│   │   └── Settings/
│   ├── Application/
│   │   ├── Services/
│   │   └── Coordinators/
│   ├── Domain/
│   │   ├── Audio/
│   │   ├── Transcription/
│   │   └── Models/
│   └── Infrastructure/
│       ├── Audio/
│       ├── Whisper/
│       ├── Storage/
│       └── System/
├── SpeakrTests/
└── SpeakrUITests/
```
