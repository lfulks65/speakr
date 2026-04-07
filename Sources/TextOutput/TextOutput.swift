import AppKit
import Foundation
import ApplicationServices

/// Output modes for transcribed text
public enum OutputMode: String, Sendable {
    /// Copy text to the system clipboard
    case clipboard
    /// Paste text into the currently active application via keyboard simulation
    case paste
    /// Copy to clipboard and attempt to paste
    case clipboardAndPaste
}

/// Handles outputting transcribed text to the user's active application
public final class TextOutput: @unchecked Sendable {

    // MARK: - Public Properties

    public var outputMode: OutputMode = .clipboard

    /// When set, ⌘V is sent directly to this PID via CGEvent.postToPid rather
    /// than to the current frontmost application.  Set to the target app's PID
    /// before calling output(text:completion:) for reliable paste.
    public var targetPid: pid_t = 0

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Output text using the configured output mode.
    /// - Parameters:
    ///   - text: The text to output.
    ///   - completion: Called with `true` if the output succeeded, `false` otherwise.
    public func output(text: String, completion: @escaping @Sendable (Bool) -> Void) {
        switch outputMode {
        case .clipboard:
            copyToClipboard(text)
            completion(true)
        case .paste:
            // Try AX direct insertion first — works without a keypress and is
            // more reliable than ⌘V simulation.  Fall back to clipboard + ⌘V.
            if insertViaAX(text) {
                completion(true)
            } else {
                copyToClipboard(text)
                pasteText(completion: completion)
            }
        case .clipboardAndPaste:
            // Always copy to clipboard as a fallback the user can paste manually.
            copyToClipboard(text)
            if !insertViaAX(text) {
                pasteText(completion: completion)
            } else {
                completion(true)
            }
        }
    }

    // MARK: - Private Methods

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Directly set the selected text in the currently focused AX element.
    /// This inserts at the cursor (or replaces the selection) without a keypress,
    /// and works even when Accessibility is granted but ⌘V simulation is blocked.
    @discardableResult
    private func insertViaAX(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success else { return false }
        // swiftlint:disable:next force_cast
        let element = focusedRef as! AXUIElement
        return AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        ) == .success
    }

    private func pasteText(completion: @escaping @Sendable (Bool) -> Void) {
        guard AXIsProcessTrusted() else {
            completion(false)
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)

        // ⌘V key down then up
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            completion(false)
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        if targetPid > 0 {
            // Deliver directly to the target process — more reliable than posting
            // to the HID tap which goes to whatever happens to be frontmost.
            keyDown.postToPid(targetPid)
            keyUp.postToPid(targetPid)
        } else {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }

        completion(true)
    }
}
