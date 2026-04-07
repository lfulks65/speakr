import Carbon
import AppKit
import Foundation
import Settings


/// Errors that can occur during hotkey registration
public enum HotkeyError: Error, CustomStringConvertible {
    case registrationFailed(String)
    case hotkeyAlreadyRegistered
    case invalidKeyCombination
    case accessibilityPermissionDenied
    
    public var description: String {
        switch self {
        case .registrationFailed(let reason):
            return "Failed to register hotkey: \(reason)"
        case .hotkeyAlreadyRegistered:
            return "Hotkey is already registered."
        case .invalidKeyCombination:
            return "Invalid key combination."
        case .accessibilityPermissionDenied:
            return "Accessibility permission required. Please grant access in System Settings > Privacy & Security > Accessibility."
        }
    }
}

/// Protocol defining the hotkey service interface
public protocol HotkeyServiceProtocol: AnyObject {
    /// Whether the hotkey service is active
    var isActive: Bool { get }
    
    /// Current registered hotkey
    var currentHotkey: Hotkey? { get }
    
    /// Register a global hotkey
    func registerHotkey(_ hotkey: Hotkey) async throws
    
    /// Unregister the current hotkey
    func unregisterHotkey()
    
    /// Check accessibility permissions
    func checkAccessibilityPermission() -> Bool
    
    /// Request accessibility permissions
    func requestAccessibilityPermission()
    
    /// Set the handler for hotkey events
    func setHandler(_ handler: @escaping @Sendable () -> Void)
}

/// Global hotkey service using Carbon Event APIs
@available(macOS 14.0, *)
public final class HotkeyService: HotkeyServiceProtocol {
    
    // MARK: - Public Properties
    
    public private(set) var isActive: Bool = false
    public private(set) var currentHotkey: Hotkey?
    
    // MARK: - Private Properties
    
    private var eventHandler: (@Sendable () -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let settings: SettingsStore?
    
    // MARK: - Initialization
    
    public init(settings: SettingsStore? = nil) {
        self.settings = settings
        NSLog("▶ HotkeyService.init() — deferring Carbon registration to startListening()")
    }

    /// Call this after the app has fully launched (e.g. from a .task modifier).
    /// Registers the saved or default hotkey with the OS.
    public func startListening() {
        NSLog("▶ HotkeyService.startListening() begin — thread: \(Thread.isMainThread ? "main" : "bg")")
        let hotkey: Hotkey
        if let saved = settings?.shortcutHotkey, saved.modifiers >= 256 {
            NSLog("  using saved hotkey: keyCode=\(saved.keyCode) mods=\(saved.modifiers)")
            hotkey = saved
        } else {
            NSLog("  using default hotkey (⌥Space)")
            settings?.shortcutHotkey = nil
            hotkey = .default
        }
        NSLog("  calling registerHotkeySync...")
        do {
            try registerHotkeySync(hotkey)
            NSLog("  registerHotkeySync succeeded")
        } catch {
            NSLog("[ERROR] " + "  registerHotkeySync failed: \(error)")
        }
        NSLog("▶ HotkeyService.startListening() complete")
    }
    
    deinit {
        unregisterHotkey()
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
    
    // MARK: - Public Methods
    
    public func registerHotkey(_ hotkey: Hotkey) async throws {
        // Check accessibility permission
        guard checkAccessibilityPermission() else {
            throw HotkeyError.accessibilityPermissionDenied
        }
        
        // Unregister any existing hotkey
        unregisterHotkey()
        
        try registerHotkeySync(hotkey)
        
        // Save the hotkey
        settings?.shortcutHotkey = hotkey
    }
    
    public func unregisterHotkey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        isActive = false
        currentHotkey = nil
    }
    
    public func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrustedWithOptions(nil)
    }
    
    public func requestAccessibilityPermission() {
        // "AXTrustedCheckOptionPrompt" is the string backing kAXTrustedCheckOptionPrompt
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
    
    public func setHandler(_ handler: @escaping @Sendable () -> Void) {
        self.eventHandler = handler
    }
    
    // MARK: - Private Methods
    
    private func registerHotkeySync(_ hotkey: Hotkey) throws {
        NSLog("    registerHotkeySync: installing event handler...")
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        
        // Install event handler
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyCallback,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
        
        guard status == noErr else {
            NSLog("[ERROR] " + "    InstallEventHandler failed: \(status)")
            throw HotkeyError.registrationFailed("Failed to install event handler")
        }
        NSLog("    InstallEventHandler OK, registering hotkey...")
        let carbonHotKeyID = EventHotKeyID(
            signature: OSType(fourCharCode(from: "wispr")),
            id: 1
        )
        
        let registerStatus = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            UInt32(hotkey.modifiers),
            carbonHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        guard registerStatus == noErr else {
            NSLog("[ERROR] " + "    RegisterEventHotKey failed: \(registerStatus)")
            RemoveEventHandler(eventHandlerRef!)
            eventHandlerRef = nil
            throw HotkeyError.registrationFailed("Failed to register hotkey with OS")
        }
        NSLog("    RegisterEventHotKey OK — hotkey active")
        currentHotkey = hotkey
        isActive = true
    }
    
    fileprivate func handleHotkeyEvent() {
        let handler = eventHandler
        DispatchQueue.main.async {
            handler?()
        }
    }
}

// MARK: - Carbon Callback

private func hotkeyCallback(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event else { return OSStatus(eventNotHandledErr) }
    
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    
    guard status == noErr else { return status }
    
    if let userData = userData {
        let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
        service.handleHotkeyEvent()
    }
    
    return noErr
}

private func fourCharCode(from string: String) -> FourCharCode {
    let utf8 = string.utf8
    var result: FourCharCode = 0
    for (index, byte) in utf8.enumerated() where index < 4 {
        result <<= 8
        result |= FourCharCode(byte)
    }
    return result
}

// MARK: - Hotkey Display Extension

public extension Hotkey {
    /// Display string for UI (e.g. "⌥Space")
    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt(shiftKey) != 0 { parts.append("⇧") }
        parts.append(keyCodeToString(keyCode: keyCode))
        return parts.joined(separator: "")
    }

    private func keyCodeToString(keyCode: Int) -> String {
        switch keyCode {
        case Int(kVK_Space): return "Space"
        case Int(kVK_Return): return "↵"
        case Int(kVK_Delete): return "⌫"
        case Int(kVK_ForwardDelete): return "⌦"
        case Int(kVK_Tab): return "⇥"
        case Int(kVK_Escape): return "⎋"
        case Int(kVK_UpArrow): return "↑"
        case Int(kVK_DownArrow): return "↓"
        case Int(kVK_LeftArrow): return "←"
        case Int(kVK_RightArrow): return "→"
        default: return String(keyCode)
        }
    }
}
