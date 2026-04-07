# Mac Hotkey and System-Wide Listener APIs Evaluation

**Research Date:** 2026-04-06
**Researcher:** speakr_alternative team
**Status:** Complete

## Executive Summary

This document evaluates three primary approaches for implementing system-wide hotkey functionality on macOS for push-to-talk/toggle recording. After comparing native APIs (`NSEvent.addGlobalMonitorForEvents`, `CGEventTap`) and third-party libraries (`KeyboardShortcuts`, `Magnet`), we recommend **CGEventTap as the primary implementation** with the **KeyboardShortcuts library as an alternative for simpler use cases**.

---

## 1. Implementation Approaches Comparison

### 1.1 NSEvent.addGlobalMonitorForEvents (Foundation Framework)

**API Documentation:** `NSEvent.addGlobalMonitorForEvents(matching:handler:)`

#### Overview
The `NSEvent.addGlobalMonitorForEvents` API is a high-level Foundation framework method that monitors global keyboard events outside the app's key window. It's the simplest approach but has limitations for complex hotkey scenarios.

#### Pros
- ✅ Simplest implementation - minimal code required
- ✅ No need for manual event loop integration
- ✅ Automatic memory management via block-based callbacks
- ✅ Good for basic key press detection (e.g., Esc key monitoring)
- ✅ Thread-safe event delivery

#### Cons
- ❌ **Cannot consume/swallow events** - events always pass through to other apps
- ❌ Cannot detect key combinations that include system keys
- ❌ Limited to key events only (no modifier-only detection)
- ❌ Events delivered asynchronously (may have slight latency)
- ❌ Cannot differentiate between left/right modifier keys
- ❌ No key repeat information available

#### Code Example
```swift
import Cocoa

class GlobalHotkeyManager {
    var eventMonitor: Any?
    
    func startMonitoring() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // Check for Command+Space
            if event.modifierFlags.contains(.command) && event.keyCode == 49 {
                print("Command+Space detected")
                // Note: Cannot prevent system Spotlight from opening
            }
        }
    }
    
    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
```

#### Suitability Assessment
| Use Case | Suitability |
|----------|-------------|
| Push-to-hold recording | ⚠️ Partial (cannot suppress original key) |
| Toggle recording | ⚠️ Partial (cannot use exclusive hotkeys) |
| Simple key monitoring | ✅ Good |
| Complex hotkey combinations | ❌ Poor |

---

### 1.2 CGEventTap (Core Graphics Framework)

**API Documentation:** `CGEvent.tapCreate`

#### Overview
`CGEventTap` is a low-level Core Graphics API that creates an event tap in the system event stream. It provides full control over event handling, including the ability to consume events (prevent them from reaching other applications).

#### Pros
- ✅ **Can consume/suppress events** - prevent original hotkey from reaching other apps
- ✅ Supports both keyboard and mouse events
- ✅ Access to raw event data (key codes, modifiers, timestamps)
- ✅ Can differentiate between left/right modifier keys
- ✅ Synchronous event processing (lower latency)
- ✅ Can be used at session or HID level (see Security section)
- ✅ Supports all key combinations including system keys
- ✅ Real-time key repeat detection

#### Cons
- ❌ More complex implementation
- ❌ Requires CFRunLoop integration
- ❌ Manual memory management of tap reference
- ❌ Requires accessibility permissions (see Security)
- ❌ Must handle event tap invalidation (e.g., when user switches Secure Input)
- ❌ Needs proper cleanup to avoid memory leaks

#### Code Example
```swift
import CoreGraphics

class CGEventHotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Key codes for common keys
    private let kVK_Space: CGKeyCode = 49
    private let kVK_Control: CGEventFlags = 0x000008
    
    func startMonitoring() {
        // Create event tap for key down and key up events
        let eventMask = (1 << CGEventType.keyDown.rawValue) | 
                        (1 << CGEventType.keyUp.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,           // Monitor session events
            place: .headInsertEventTap,         // Insert at front of queue
            options: .defaultTap,               // Default filtering
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                return CGEventHotkeyManager.handleEvent(proxy: proxy, type: type, event: event, refcon: refcon)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("Failed to create event tap - check accessibility permissions")
            return
        }
        
        self.eventTap = tap
        
        // Create run loop source and add to current run loop
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        self.runLoopSource = runLoopSource
        
        // Enable the event tap
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    static let handleEvent: CGEventTapCallBack = { proxy, type, event, refcon in
        // Retrieve manager instance
        let manager = Unmanaged<CGEventHotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
        
        // Check for Control+Space
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        if type == .keyDown && flags.contains(.maskControl) && keyCode == 49 {
            manager.handleHotkeyPressed()
            return nil // Consume event (return Unmanaged.passRetained(event).toOpaque() to pass through)
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func handleHotkeyPressed() {
        print("Control+Space hotkey detected!")
        // Trigger recording toggle
    }
    
    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}
```

#### Suitability Assessment
| Use Case | Suitability |
|----------|-------------|
| Push-to-hold recording | ✅ Excellent (can suppress key) |
| Toggle recording | ✅ Excellent |
| Complex multi-key combinations | ✅ Excellent |
| System-wide exclusive hotkeys | ✅ Excellent |

---

### 1.3 Third-Party Libraries

#### 1.3.1 KeyboardShortcuts (Recommended Library)

**GitHub:** [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
**License:** MIT
**Swift Version:** Swift 5.7+
**Platform:** macOS 10.11+

##### Overview
KeyboardShortcuts is a mature, well-maintained Swift library by Sindre Sorhus that wraps `CGEventTap` with a clean, Swift-friendly API. It's the de facto standard for global hotkeys in modern Mac apps.

##### Features
- Native Swift API with Combine support
- NSUserDefaults integration for persistence
- Visual shortcut recorder component for settings UI
- Automatic accessibility permission handling
- Proper error handling and invalidation recovery
- Supports push-to-hold and toggle modes

##### Pros
- ✅ Production-ready and battle-tested (used by 500+ apps)
- ✅ Clean Swift API vs. raw CGEventTap
- ✅ Automatic hotkey persistence
- ✅ Built-in UI component for recording shortcuts
- ✅ Proper memory management
- ✅ Handles Secure Input state automatically
- ✅ Well-documented with examples

##### Cons
- ❌ Additional dependency (but SPM makes this manageable)
- ❌ Still requires accessibility permissions
- ❌ Cannot differentiate left/right modifier keys (CGEventTap limitation)

##### Integration
```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.11.0")
]

// Info.plist
<key>NSAccessibilityUsageDescription</key>
<string>This app needs accessibility access to listen for global hotkeys.</string>
```

##### Usage Example
```swift
import KeyboardShortcuts

// Define shortcut names (used as keys in UserDefaults)
extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording")
    static let pushToTalk = Self("pushToTalk", default: .init(.space, modifiers: .control))
}

class HotkeyManager {
    func setupHotkeys() {
        // Register toggle mode hotkey
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            self?.toggleRecording()
        }
        
        // Register push-to-talk hotkey
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            self?.startRecording()
        }
        
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            self?.stopRecording()
        }
    }
    
    func showSettings() {
        // Built-in shortcut recorder view
        let view = KeyboardShortcuts.RecorderCocoa(for: .toggleRecording)
        // Add to settings panel...
    }
    
    private func toggleRecording() { /* ... */ }
    private func startRecording() { /* ... */ }
    private func stopRecording() { /* ... */ }
}
```

##### Suitability Assessment
| Use Case | Suitability |
|----------|-------------|
| Push-to-hold recording | ✅ Excellent |
| Toggle recording | ✅ Excellent |
| Settings UI integration | ✅ Excellent |
| Quick implementation | ✅ Excellent |

---

#### 1.3.2 Magnet (Event Monitoring Library)

**GitHub:** [Clipy/Magnet](https://github.com/Clipy/Magnet)
**License:** MIT
**Swift Version:** Swift 5.0+
**Platform:** macOS 10.10+

##### Overview
Magnet is a Swift library for global hotkey handling maintained by the Clipy team. It provides a more traditional API compared to KeyboardShortcuts.

##### Features
- Support for multi-hotkey registration
- KeyCombo abstraction for easy shortcut definition
- NSUserDefaults support
- Cocoa binding support

##### Pros
- ✅ Mature and stable
- ✅ Supports complex multi-hotkey scenarios
- ✅ Good KeyCombo abstraction

##### Cons
- ❌ Less maintained than KeyboardShortcuts (last update 2023)
- ❌ No built-in UI component
- ❌ More verbose API

##### Usage Comparison
```swift
import Magnet

// Define hotkey
let keyCombo = KeyCombo(keyCode: 49, cocoaModifiers: .control)
let hotKey = HotKey(identifier: "ToggleRecording", keyCombo: keyCombo) { _ in
    print("Hotkey pressed!")
}
hotKey.register()
```

##### Recommendation
While functional, **KeyboardShortcuts is preferred** due to better maintenance, superior API design, and built-in UI components.

---

#### 1.3.3 Other Libraries

| Library | Status | Recommendation |
|---------|--------|----------------|
| MASShortcut | Legacy Objective-C | ❌ Use KeyboardShortcuts instead |
| HotKey | Swift wrapper | ⚠️ Simpler but less flexible |
| ShortcutRecorder | Objective-C | ❌ Legacy, use KeyboardShortcuts.RecorderCocoa |

---

## 2. Sandbox Restrictions and Accessibility Permissions

### 2.1 Sandbox App Store Compatibility

**Critical Constraint:** Global hotkey APIs (`CGEventTap`, `NSEvent.addGlobalMonitorForEvents`) **require disabling App Sandbox** in the entitlements file. This makes apps using global hotkeys **ineligible for Mac App Store distribution**.

#### Workarounds
1. **Direct Distribution** (Recommended)
   - Distribute via GitHub releases
   - Use Sparkle for auto-updates
   - Notarize with Apple for security

2. **Helper App Pattern**
   - Main app stays sandboxed
   - Separate non-sandboxed helper app for hotkeys
   - Communicate via XPC
   - *Note:* Complex and may still face App Store rejection

3. **App Store Without Hotkeys**
   - App Store version uses menubar only
   - Direct-download "Pro" version includes global hotkeys

#### Entitlement Configuration
```xml
<!-- Required: Disable sandbox for global hotkeys -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN">
<plist version="1.0">
<dict>
    <!-- REMOVE or set to false: -->
    <!-- <key>com.apple.security.app-sandbox</key> -->
    <!-- <true/> -->
    
    <!-- Required permissions -->
    <key>com.apple.security.temporary-exception.mach-register.global-name</key>
    <array>
        <string>com.apple.coregraphics.eventTap</string>
    </array>
</dict>
</plist>
```

### 2.2 Accessibility Permissions

All global hotkey implementations require **Accessibility permissions** (`kAXTrustedCheckOptionPrompt`).

#### Permission Flow
```
User launches app
    ↓
App checks accessibility trust status
    ↓
If NOT trusted:
    - Prompt user to grant permission
    - Open System Settings → Privacy & Security → Accessibility
    - Show instructional overlay
    ↓
User grants permission in System Settings
    ↓
App restarts or checks trust again
    ↓
Hotkeys become active
```

#### Implementation
```swift
import Cocoa

class AccessibilityPermissionManager {
    static func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    static func openAccessibilitySettings() {
        // Open the exact settings pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    static func requestPermission(completion: @escaping (Bool) -> Void) {
        if checkAccessibilityPermission() {
            completion(true)
            return
        }
        
        // Show permission dialog
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "This app needs accessibility permissions to detect global hotkeys. Please grant permission in System Settings."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
        
        completion(checkAccessibilityPermission())
    }
}
```

#### User Experience Considerations
- **First Launch:** Show onboarding explaining why permission is needed
- **Permission Denied:** Graceful degradation to menubar-only mode
- **Settings Pane:** Direct link to exact settings location
- **Visual Indicator:** Show lock icon in UI when permission pending

### 2.3 Permission Prompt Strings

Add to `Info.plist`:
```xml
<key>NSAccessibilityUsageDescription</key>
<string>WhisperFlow needs accessibility access to detect your push-to-talk hotkey from anywhere in the system, even when the app is not focused.</string>
```

---

## 3. System Hotkey Conflicts

### 3.1 Common Conflict Areas

| Modifier Combination | System Usage | Risk Level |
|---------------------|--------------|------------|
| ⌘ + Space | Spotlight Search | 🔴 High |
| ⌘ + Tab | App Switcher | 🔴 High |
| ⌘ + ⌥ + Esc | Force Quit | 🔴 High |
| ⌃ + Space | Input Source Switch | 🟡 Medium |
| ⌃ + ⌘ + Space | Emoji Picker | 🟡 Medium |
| ⌥ + Space | Various | 🟢 Low |
| ⌃ + ⌥ + [key] | Generally safe | 🟢 Low |
| Fn + [key] | Generally safe | 🟢 Low |

### 3.2 Conflict Detection Strategy

```swift
import Foundation

class HotkeyConflictDetector {
    static let systemHotkeys: [Hotkey] = [
        Hotkey(key: .space, modifiers: [.command], name: "Spotlight Search"),
        Hotkey(key: .tab, modifiers: [.command], name: "App Switcher"),
        Hotkey(key: .space, modifiers: [.control], name: "Input Source Switch"),
        // ... more system hotkeys
    ]
    
    static func checkForConflicts(key: Key, modifiers: Set<Modifier>) -> [String] {
        return systemHotkeys
            .filter { $0.key == key && $0.modifiers == modifiers }
            .map { $0.name }
    }
    
    static func suggestAlternatives(for desiredModifiers: Set<Modifier>) -> [Hotkey] {
        // Suggest alternatives that don't conflict
        let safeModifiers: Set<Modifier> = [.control, .option, .function]
        // ... logic to suggest safe combinations
    }
}
```

### 3.3 Runtime Conflict Detection

Even if we avoid known system hotkeys, users may have custom shortcuts defined:

```swift
// Warn if hotkey registration appears to fail
func registerHotkey() {
    KeyboardShortcuts.onKeyUp(for: .toggleRecording) {
        // Handle hotkey
    }
    
    // Set up a timer to check if hotkey is actually working
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        if !isHotkeyResponsive() {
            showConflictWarning()
        }
    }
}
```

### 3.4 Conflict Resolution UI

When a conflict is detected:
1. Show warning icon in settings
2. Offer alternative combinations
3. Link to System Settings to disable conflicting shortcut
4. Provide "Test Hotkey" button to verify functionality

---

## 4. Recommended Implementation Approach

### 4.1 Primary Recommendation: CGEventTap via KeyboardShortcuts Library

**Rationale:**
1. **Production-Ready:** KeyboardShortcuts is well-tested in production apps
2. **Developer Experience:** Clean Swift API vs. raw C API
3. **Maintenance:** Active development and community support
4. **Features:** Built-in UI components and persistence
5. **Performance:** Thin wrapper over CGEventTap with minimal overhead

### 4.2 Architecture Recommendation

```
┌─────────────────────────────────────────────────────────┐
│                    Hotkey Layer                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  KeyboardShortcuts Library (SPM Dependency)     │   │
│  │  - Event tap management                         │   │
│  │  - UserDefaults persistence                     │   │
│  └─────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────┤
│                  Service Layer                          │
│  ┌─────────────────────────────────────────────────┐   │
│  │  HotkeyService (Protocol-based wrapper)         │   │
│  │  - Abstracts library implementation             │   │
│  │  - Defines hotkey configurations                │   │
│  │  - Handles mode switching (toggle vs push)      │   │
│  └─────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────┤
│                 Core Layer                              │
│  ┌─────────────────────────────────────────────────┐   │
│  │  TranscriptionCoordinator                     │   │
│  │  - Receives hotkey events                       │   │
│  │  - Manages recording state machine              │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 4.3 Implementation Pattern

```swift
// HotkeyService.swift
import KeyboardShortcuts
import Combine

protocol HotkeyServiceProtocol {
    var recordingStatePublisher: AnyPublisher<RecordingState, Never> { get }
    func setupHotkeys(mode: HotkeyMode)
    func updateConfiguration(_ config: HotkeyConfiguration)
}

enum HotkeyMode {
    case toggle      // Press to start, press to stop
    case pushToTalk  // Hold to record, release to stop
}

enum RecordingState {
    case idle
    case recording
    case processing
}

class HotkeyService: HotkeyServiceProtocol {
    private let stateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    var recordingStatePublisher: AnyPublisher<RecordingState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    
    func setupHotkeys(mode: HotkeyMode) {
        switch mode {
        case .toggle:
            setupToggleMode()
        case .pushToTalk:
            setupPushToTalkMode()
        }
    }
    
    private func setupToggleMode() {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            self?.toggleRecording()
        }
    }
    
    private func setupPushToTalkMode() {
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            self?.startRecording()
        }
        
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            self?.stopRecording()
        }
    }
    
    private func toggleRecording() {
        switch stateSubject.value {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .processing:
            // Cancel current processing
            cancelProcessing()
        }
    }
    
    private func startRecording() {
        stateSubject.send(.recording)
        // Notify audio service...
    }
    
    private func stopRecording() {
        stateSubject.send(.processing)
        // Notify transcription service...
    }
    
    private func cancelProcessing() {
        stateSubject.send(.idle)
    }
    
    func updateConfiguration(_ config: HotkeyConfiguration) {
        // Update KeyboardShortcuts settings
        KeyboardShortcuts.userDefaults = config.userDefaults
    }
}
```

### 4.4 Alternative: Raw CGEventTap

If avoiding dependencies is a hard requirement, implement raw CGEventTap using the pattern in section 1.2, with:
- Proper event tap invalidation handling
- Secure Input state detection
- Left/Right modifier differentiation via `CGEventSource` inspection

---

## 5. Recommended Default Hotkey Combinations

### 5.1 Primary Recommendations

Based on analysis of system conflicts and user ergonomics:

| Function | Default Hotkey | Rationale |
|----------|---------------|-----------|
| **Toggle Recording** | `⌃⌥Space` (Ctrl+Opt+Space) | Safe from system conflicts, easy to reach |
| **Push-to-Talk** | `⌃Space` (Ctrl+Space) | Mimics walkie-talkie, commonly used in apps |
| **Cancel Recording** | `Esc` | Universal cancel action |
| **Quick Settings** | `⌃⌥S` (Ctrl+Opt+S) | S for Settings, avoids conflicts |

### 5.2 Alternative Configurations

| Profile | Toggle Hotkey | Push-to-Talk | Notes |
|---------|--------------|--------------|-------|
| **Standard** | `⌃⌥Space` | `⌃Space` | Recommended for most users |
| **Whisper Flow Compatible** | `FnSpace` | `Fn⌥Space` | Uses Function key |
| **Advanced** | `⌃⇧R` | `⌃R` | R for Record |
| **Minimal** | `F13` | `F14` | Function keys only |

### 5.3 Hotkey Selection Guidelines

When selecting hotkeys:

1. **Avoid these combinations:**
   - Anything with `⌘` alone (reserved for system/app shortcuts)
   - `⌘Space` (Spotlight)
   - `⌃Space` in non-English locales (input switching)
   - `⌘⇥` (App switcher)
   - `⌃⌘Space` (Emoji picker)

2. **Safer patterns:**
   - `⌃⌥[key]` combinations
   - Function keys (`F13` - `F19` are typically unused)
   - `⌃⇧[key]` combinations
   - Include `Fn` key for guaranteed safety

3. **Ergonomics:**
   - Prefer keys reachable without looking
   - Avoid combinations requiring two hands
   - Consider users with different keyboard layouts

### 5.4 Platform-Specific Notes

| Keyboard Layout | Considerations |
|-----------------|----------------|
| US/ANSI | Standard recommendations apply |
| ISO (European) | Left ⌥ key position differs |
| JIS (Japanese) | Extra keys may be available |
| Compact (Laptop) | No F13-F19 keys available |

---

## 6. Security and Privacy Considerations

### 6.1 Event Tap Security

Event taps can capture all keyboard input, creating potential security risks:

#### Mitigations:
1. **Minimal Privilege:** Only register events actually needed
2. **User Consent:** Clear onboarding explaining why access is required
3. **Audit Trail:** Log hotkey events (optional, user-configurable)
4. **Secure Input Detection:** Pause recording when secure input is active

```swift
// Detect secure input state
func isSecureInputActive() -> Bool {
    return CGEventSource.flagsState(.combinedSessionState)
        .contains(.maskEventSuppression)
}

// Disable hotkeys when secure input detected
if isSecureInputActive() {
    hotkeyService.pause()
    showSecureInputWarning()
}
```

### 6.2 Privacy Best Practices

- Never log keystrokes outside of registered hotkeys
- Process hotkey events locally, never transmit
- Clear keyboard buffers after use
- Document hotkey handling in privacy policy

---

## 7. Testing Strategy

### 7.1 Test Matrix

| Test Case | CGEventTap | KeyboardShortcuts | NSEvent |
|-----------|------------|-------------------|---------|
| Basic hotkey detection | ✅ | ✅ | ✅ |
| Modifier combinations | ✅ | ✅ | ✅ |
| Event consumption | ✅ | ✅ | ❌ |
| Secure Input handling | Manual | ✅ (auto) | N/A |
| Permission denied | ✅ | ✅ | ✅ |
| System hotkey conflict | ✅ | ✅ | ⚠️ |
| Performance/latency | ✅ | ✅ | ⚠️ |

### 7.2 Accessibility Testing

```swift
// XCUITest example for permission flow
func testAccessibilityPermissionFlow() {
    let app = XCUIApplication()
    app.launch()
    
    // Verify permission prompt appears
    XCTAssertTrue(app.buttons["Open Settings"].exists)
    
    // Note: Cannot automate system settings interaction
    // Requires manual testing or mocked accessibility state
}
```

---

## 8. Summary and Decision Log

### 8.1 Final Recommendations

| Aspect | Recommendation |
|--------|---------------|
| **Primary API** | CGEventTap via KeyboardShortcuts library |
| **Fallback API** | Raw CGEventTap (if no dependencies allowed) |
| **Default Toggle** | `⌃⌥Space` (Ctrl+Option+Space) |
| **Default Push-to-Talk** | `⌃Space` (Ctrl+Space) |
| **App Store Strategy** | Direct distribution (not App Store) |
| **Minimum macOS** | 11.0 (Big Sur) for best SwiftUI support |

### 8.2 Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-06 | Choose KeyboardShortcuts over raw CGEventTap | Reduces implementation complexity, built-in UI, battle-tested |
| 2026-04-06 | Recommend `⌃⌥Space` as default | Avoids system conflicts, good ergonomics |
| 2026-04-06 | Target direct distribution, not App Store | Global hotkeys incompatible with sandbox |
| 2026-04-06 | Support both toggle and push-to-talk modes | User preference varies by workflow |

### 8.3 Next Steps

1. Add KeyboardShortcuts SPM dependency to project
2. Implement HotkeyService wrapper with protocol abstraction
3. Create settings UI with KeyboardShortcuts.RecorderCocoa
4. Implement accessibility permission onboarding flow
5. Test on different keyboard layouts (US, ISO, JIS)
6. Profile performance to ensure no latency in hotkey response

---

## References

- [Apple Documentation: CGEventTap](https://developer.apple.com/documentation/coregraphics/cgeventtap)
- [Apple Documentation: NSEvent Global Monitors](https://developer.apple.com/documentation/appkit/nsevent/1535471-addglobalmonitorforevents)
- [KeyboardShortcuts GitHub](https://github.com/sindresorhus/KeyboardShortcuts)
- [sindresorhus/KeyboardShortcuts - API Reference](https://sindresorhus.github.io/KeyboardShortcuts/)
- [Apple HID Documentation](https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/HID/intro/intro.html)
- [macOS Event Architecture](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/Introduction/Introduction.html)

---

*Document Version: 1.0*
*Last Updated: 2026-04-06*
