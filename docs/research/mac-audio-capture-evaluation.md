# Mac Audio Capture APIs and Frameworks Research

## Executive Summary

This document evaluates the primary audio capture APIs available on macOS for building a low-latency microphone input system. The **recommended approach** for this project is **AVAudioEngine** with a custom `AVAudioSinkNode` for most use cases, with **AudioUnit (CoreAudio)** as a fallback for advanced low-latency requirements.

**Quick Comparison:**

| API | Ease of Use | Latency | Control Level | Recommended For |
|-----|-------------|---------|---------------|-----------------|
| AVAudioEngine | ⭐⭐⭐⭐⭐ | Low | Medium | **Primary recommendation** |
| AudioUnit (CoreAudio) | ⭐⭐⭐ | Very Low | High | Ultra-low latency scenarios |
| CoreAudio HAL | ⭐⭐ | Low | Very High | Audio driver development |
| CoreAudioTap | ⭐⭐⭐ | Low | High | System audio capture |

---

## 1. AVAudioEngine (Recommended)

### Overview
`AVAudioEngine` is the modern high-level API introduced in macOS 10.10 (Yosemite). It provides an object-oriented graph-based audio system with Swift/Objective-C APIs.

### Key Characteristics
- **Introduced**: macOS 10.10 (2014)
- **Language**: Swift, Objective-C
- **Abstraction Level**: High (object-oriented graph)
- **Latency**: Low (~5-20ms typical)
- **Thread Safety**: Built-in, queue-based

### Sample Implementation

```swift
import AVFoundation

class AudioCaptureManager {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer: [Float] = []
    
    func startCapture() throws {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode
        
        // Configure format for Whisper: 16kHz, mono, Float32
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )
        
        guard let input = inputNode, let fmt = format else {
            throw AudioError.configurationFailed
        }
        
        // Install tap on input node
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer)
        }
        
        try audioEngine?.start()
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        
        // Copy audio data
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        audioBuffer.append(contentsOf: samples)
    }
    
    func stopCapture() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }
}
```

### Pros
- ✅ **Modern Swift-first API** - Clean, readable, maintainable code
- ✅ **Automatic format conversion** - Handles resampling and format conversion
- ✅ **Built-in thread safety** - Queue-based callbacks prevent audio glitches
- ✅ **Easy configuration** - Simple graph-based setup
- ✅ **Good documentation** - Extensive Apple documentation and WWDC videos
- ✅ **Error handling** - Structured error types
- ✅ **Background audio** - Works with proper audio session configuration
- ✅ **Extensible** - Easy to add effects, mixing, etc.

### Cons
- ❌ **Slightly higher latency** than raw AudioUnit (~5-10ms additional)
- ❌ **Less control** over buffer sizes and timing
- ❌ **Objective-C overhead** in some hot paths
- ❌ **SinkNode limitations** - AVAudioSinkNode (macOS 10.15+) has some restrictions

### Best For
- Most applications requiring < 50ms latency
- Teams with Swift expertise
- Prototyping and rapid development
- Applications needing audio effects/processing chain

---

## 2. AudioUnit (CoreAudio) - Low-Level Option

### Overview
`AudioUnit` is the foundational low-level audio API that powers all other Apple audio frameworks. It provides direct access to audio I/O with minimal overhead.

### Key Characteristics
- **Introduced**: Mac OS X 10.0 (2001)
- **Language**: C, C++, bridged to Swift
- **Abstraction Level**: Low (callback-based)
- **Latency**: Very Low (~2-10ms possible)
- **Thread Safety**: Manual (real-time thread constraints)

### Sample Implementation

```swift
import CoreAudio
import AudioToolbox

class AudioUnitCaptureManager {
    private var audioUnit: AudioUnit?
    private var audioBufferList: AudioBufferList?
    
    func startCapture() throws {
        var audioComponentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        guard let component = AudioComponentFindNext(nil, &audioComponentDescription) else {
            throw AudioError.componentNotFound
        }
        
        var audioUnitRef: AudioUnit?
        let status = AudioComponentInstanceNew(component, &audioUnitRef)
        guard status == noErr, let au = audioUnitRef else {
            throw AudioError.initializationFailed
        }
        audioUnit = au
        
        // Enable input
        var inputEnable: UInt32 = 1
        AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,  // Input bus
            &inputEnable,
            UInt32(MemoryLayout<UInt32>.size)
        )
        
        // Disable output
        var outputDisable: UInt32 = 0
        AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,  // Output bus
            &outputDisable,
            UInt32(MemoryLayout<UInt32>.size)
        )
        
        // Set format: 16kHz, mono, Float32
        var audioFormat = AudioStreamBasicDescription(
            mSampleRate: 16000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        AudioUnitSetProperty(
            au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &audioFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        
        // Set render callback
        var callbackStruct = AURenderCallbackStruct(
            inputProc: renderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        
        AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        
        AudioUnitInitialize(au)
        AudioOutputUnitStart(au)
    }
    
    private let renderCallback: AURenderCallback = { (
        inRefCon,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames,
        ioData
    ) -> OSStatus in
        let manager = Unmanaged<AudioUnitCaptureManager>
            .fromOpaque(inRefCon)
            .takeUnretainedValue()
        
        // Process audio frames here
        // ioData contains the captured audio
        
        return noErr
    }
    
    func stopCapture() {
        if let au = audioUnit {
            AudioOutputUnitStop(au)
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
            audioUnit = nil
        }
    }
}
```

### Pros
- ✅ **Lowest latency** - Direct hardware access
- ✅ **Maximum control** - Full control over buffer sizes, formats, timing
- ✅ **Real-time constraints** - Runs on high-priority audio threads
- ✅ **No abstraction overhead** - Minimal CPU overhead
- ✅ **Battle-tested** - Used by professional audio apps (Logic, Pro Tools)

### Cons
- ❌ **Complex API** - C-based, requires bridging headers
- ❌ **Manual memory management** - Must manage AudioBufferLists
- ❌ **Threading complexity** - Callback runs on real-time thread with restrictions
- ❌ **No ARC in C structs** - Careful memory management required
- ❌ **Harder to debug** - Lower-level errors are cryptic
- ❌ **Deprecated patterns** - Some APIs are being phased out

### Best For
- Applications requiring < 10ms latency
- Real-time audio processing
- Professional audio applications
- Teams with CoreAudio experience

---

## 3. CoreAudio HAL (Hardware Abstraction Layer)

### Overview
The HAL is the lowest-level API for audio device interaction. It provides direct access to audio hardware properties and streams.

### Key Characteristics
- **Abstraction Level**: Very Low (hardware abstraction)
- **Latency**: Low (similar to AudioUnit)
- **Use Case**: Device enumeration, property queries, stream management

### When to Use
- Enumerating available audio devices
- Querying device capabilities (sample rates, formats)
- Setting default input/output devices
- Direct stream management (rarely needed for capture)

### Sample: Device Enumeration

```swift
import CoreAudio

func enumerateAudioDevices() -> [AudioDeviceID] {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var propertySize: UInt32 = 0
    AudioObjectGetPropertyDataSize(
        kAudioObjectSystemObject,
        &propertyAddress,
        0,
        nil,
        &propertySize
    )
    
    let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
    
    AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &propertyAddress,
        0,
        nil,
        &propertySize,
        &devices
    )
    
    return devices
}
```

### Recommendation
**Use HAL only for device enumeration and property queries.** For actual capture, use AVAudioEngine or AudioUnit.

---

## 4. CoreAudioTap

### Overview
`CoreAudioTap` is part of the `CoreAudio` framework that allows interception and recording of system audio (not microphone input specifically).

### Key Characteristics
- **Purpose**: System audio capture (output device recording)
- **Introduced**: macOS 10.10
- **Use Case**: Recording computer audio, not microphone

### Important Note
**CoreAudioTap is NOT suitable for microphone capture.** It's designed for capturing system audio output (e.g., recording what the computer is playing).

### When to Use
- Recording system audio (screen recording with audio)
- Capturing audio from other applications
- Not applicable for microphone input

### Recommendation
**Not recommended for this project** since we need microphone input, not system audio.

---

## 5. Permissions Requirements

### Microphone Permission

macOS requires explicit user permission to access the microphone. This must be handled in two places:

#### 1. Info.plist Configuration

```xml
<!-- Info.plist -->
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to transcribe your speech to text.</string>
```

#### 2. Runtime Permission Request (macOS 10.14+)

```swift
import AVFoundation

func checkMicrophonePermission() {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
        // Permission granted, proceed
        startRecording()
    case .notDetermined:
        // Request permission
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted {
                DispatchQueue.main.async {
                    self.startRecording()
                }
            }
        }
    case .denied, .restricted:
        // Permission denied - show alert with instructions to enable in Settings
        showPermissionDeniedAlert()
    @unknown default:
        break
    }
}
```

#### 3. TCC (Transparency, Consent, and Control)

macOS uses TCC database for permission management:
- Permissions are stored in `~/Library/Application Support/com.apple.TCC/TCC.db`
- Users can modify permissions in System Settings → Privacy & Security → Microphone
- Sandboxed apps must declare microphone entitlement

### Sandboxing Considerations

```xml
<!-- .entitlements file -->
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
```

**Important**: Sandboxed apps with microphone access cannot be distributed on Mac App Store without special justification. Consider not sandboxing for this utility app.

---

## 6. Background Audio Capture

### Background Modes Configuration

For capture when app is not frontmost:

```xml
<!-- Info.plist -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

### Audio Session Configuration

```swift
import AVFoundation

func configureBackgroundAudio() {
    let session = AVAudioSession.sharedInstance()
    
    do {
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try session.setActive(true)
    } catch {
        print("Audio session configuration failed: \(error)")
    }
}
```

### Limitations

| Scenario | Supported | Notes |
|----------|-----------|-------|
| App in background (not quit) | ✅ Yes | Requires audio background mode |
| App not running | ❌ No | Cannot capture without running app |
| System locked/Screen off | ✅ Yes | With proper configuration |
| Push-to-talk global | ✅ Yes | Requires CGEventTap for global hotkeys |

---

## 7. Audio Format Requirements for Whisper

### Whisper Model Specifications

OpenAI's Whisper models expect specific audio input formats:

| Parameter | Requirement | Notes |
|-----------|-------------|-------|
| **Sample Rate** | 16,000 Hz (16 kHz) | Whisper models are trained on 16kHz audio |
| **Bit Depth** | 16-bit or 32-bit | 16-bit PCM or 32-bit float |
| **Channels** | Mono (1 channel) | Whisper processes single-channel audio |
| **Format** | PCM (uncompressed) | Raw audio samples, not MP3/AAC |
| **Duration** | 30 seconds max | Longer audio must be chunked |
| **Preprocessing** | Log-Mel spectrogram | Models convert internally |

### Format Conversion

When using AVAudioEngine, configure the format:

```swift
let whisperFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,  // or .pcmFormatInt16
    sampleRate: 16000,                // 16 kHz required
    channels: 1,                      // Mono
    interleaved: false
)
```

### Sample Rate Considerations

Most Mac microphones support 44.1kHz or 48kHz. Downsampling to 16kHz is required:

```swift
// AVAudioEngine handles resampling automatically when format is specified
// For raw AudioUnit, use AudioConverter or manual downsampling:
// Simple downsampling (naive - use proper resampling for production):
let downsampleFactor = 48000 / 16000  // 3:1 for 48kHz → 16kHz
let downsampledSamples = stride(from: 0, to: samples.count, by: downsampleFactor).map { samples[$0] }
```

### Recommended Audio Pipeline

```
Microphone → AVAudioEngine (48kHz) → AVAudioConverter → 16kHz/16-bit PCM → Whisper Model
```

---

## 8. Recommendations

### Primary Recommendation: AVAudioEngine

**For this project, use AVAudioEngine** as the primary audio capture API because:

1. **Development Speed**: Clean Swift code accelerates development
2. **Sufficient Latency**: ~10-20ms latency is acceptable for dictation
3. **Built-in Conversion**: Automatic resampling to 16kHz for Whisper
4. **Maintainability**: Easier for future contributors to understand
5. **Apple Support**: Modern API with ongoing improvements

### Implementation Approach

```
┌─────────────────────────────────────────────────────────────┐
│                     Audio Capture Module                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │    Input     │───▶│ AVAudioEngine│───▶│ Audio Buffer │  │
│  │   Device     │    │   (16kHz)    │    │   (Ring)     │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│                                │                             │
│                                ▼                             │
│                         ┌──────────────┐                     │
│                         │ Whisper      │                     │
│                         │ Transcription│                     │
│                         └──────────────┘                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Code Structure

```swift
// AudioCaptureManager.swift
import AVFoundation

final class AudioCaptureManager {
    private let engine = AVAudioEngine()
    private var isRecording = false
    
    // 16kHz mono format for Whisper
    private let whisperFormat: AVAudioFormat = {
        AVAudioFormat(commonFormat: .pcmFormatFloat32,
                     sampleRate: 16000,
                     channels: 1,
                     interleaved: false)!
    }()
    
    func startRecording() throws {
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: whisperFormat) { buffer, _ in
            AudioBufferPool.shared.append(buffer)
        }
        try engine.start()
        isRecording = true
    }
    
    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
    }
}
```

### Fallback Option

If AVAudioEngine latency proves insufficient during testing, implement an AudioUnit-based capture module as a fallback with the same protocol interface.

---

## 9. Additional Considerations

### Memory Management

- Use ring buffers to avoid allocation during capture
- Pre-allocate audio buffers
- Avoid retain cycles in capture callbacks

```swift
final class AudioBufferPool {
    static let shared = AudioBufferPool()
    private let bufferSize = 30 * 16000  // 30 seconds at 16kHz
    private var ringBuffer = CircularBuffer<Float>(capacity: bufferSize)
    
    func append(_ buffer: AVAudioPCMBuffer) {
        // Lock-free append for real-time audio
        ringBuffer.append(buffer.floatChannelData![0], count: Int(buffer.frameLength))
    }
}
```

### Error Handling

```swift
enum AudioCaptureError: Error {
    case permissionDenied
    case deviceNotAvailable
    case formatNotSupported
    case engineStartFailed(underlying: Error)
}
```

### Testing Strategy

1. **Latency Testing**: Measure end-to-end latency with known audio signals
2. **Format Validation**: Verify 16kHz output matches Whisper requirements
3. **Buffer Overflow Testing**: Test with long recordings (5+ minutes)
4. **Background Testing**: Verify capture continues when app is backgrounded

---

## 10. References

- [AVAudioEngine Documentation](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- [CoreAudio Overview](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/CoreAudioOverview/Introduction/Introduction.html)
- [AudioUnit Programming Guide](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/AudioUnitProgrammingGuide/Introduction/Introduction.html)
- [OpenAI Whisper Model Card](https://github.com/openai/whisper/blob/main/model-card.md)
- [WWDC 2014 Session 502: AVAudioEngine in Practice](https://developer.apple.com/videos/play/wwdc2014/502/)

---

## Conclusion

**Use AVAudioEngine** for the initial implementation. It provides the best balance of low latency, ease of development, and maintainability. The ~10-20ms additional latency over raw AudioUnit is negligible for dictation use cases and provides significant development productivity gains.

For future optimization, consider implementing an AudioUnit-based capture path behind the same protocol interface, allowing users to choose between "Quality" (AVAudioEngine) and "Low Latency" (AudioUnit) modes.
