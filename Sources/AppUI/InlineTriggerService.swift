import AppKit
import ApplicationServices
import SwiftUI

/// Watches for text field focus changes across all apps and shows a small
/// floating mic button near the active field.  Clicking the button starts /
/// stops recording without stealing focus from the field.
@available(macOS 14.0, *)
@MainActor
final class InlineTriggerService {

    // MARK: - Private State

    private weak var appState: AppState?
    private var mouseMonitor: Any?
    private var panel: NSPanel?
    /// The AX element that was focused when the panel last appeared.
    /// Captured here so we can pass it to AppState at the moment the user taps
    /// the mic button — guaranteeing we insert into the right field even if
    /// focus has shifted by the time transcription finishes.
    private var trackedElement: AXUIElement?

    // MARK: - Lifecycle

    func start(with appState: AppState) {
        self.appState = appState

        // Global monitor fires for mouse‑down events delivered to OTHER apps.
        // Our own panel's button receives clicks through the normal SwiftUI
        // responder chain and does NOT trigger this monitor.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            // Wait briefly so the target app can update its focused element.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                self?.refreshForFocusedElement()
            }
        }
    }

    func stop() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        mouseMonitor = nil
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Focus Detection

    private func refreshForFocusedElement() {
        guard AXIsProcessTrusted() else { return }

        let systemWide = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success else { hidePanel(); return }

        // swiftlint:disable:next force_cast
        let element = focusedRef as! AXUIElement

        // Ignore elements belonging to our own process.
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if pid == ProcessInfo.processInfo.processIdentifier { hidePanel(); return }

        // ── Filter: only show for elements the user can actually type into ──

        // 1. Check the AX role — reject things like menus, popups, lists.
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        let typableRoles: Set<String> = [
            kAXTextFieldRole as String,     // single-line native input
            kAXTextAreaRole as String,       // multi-line native input
            kAXComboBoxRole as String,       // editable combo box
            "AXSearchField",                 // Spotlight-style search fields
            "AXWebArea",                     // Electron / web-based editors
        ]
        guard typableRoles.contains(role) else { hidePanel(); return }

        // 2. For web areas (Electron apps like Cursor, Discord), require that
        //    kAXSelectedTextRangeAttribute exists — plain web content won't have
        //    it, but editor textareas and contentEditable regions will.
        if role == "AXWebArea" {
            var rangeRef: CFTypeRef?
            let hasTextRange = AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &rangeRef
            ) == .success
            guard hasTextRange else { hidePanel(); return }
        }

        // 3. Explicitly read-only elements — skip them.
        var editableRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableRef)
        if let editable = editableRef as? Bool, !editable { hidePanel(); return }

        // 4. For native text fields: verify the value attribute is settable
        //    (filters out labels / static text that report as AXTextField).
        if role != "AXWebArea" {
            var settableOut: DarwinBoolean = false
            let err = AXUIElementIsAttributeSettable(
                element, kAXValueAttribute as CFString, &settableOut
            )
            if err == .success && !settableOut.boolValue { hidePanel(); return }
        }

        // Remember this element — the mic button tap will forward it to AppState.
        trackedElement = element

        // Get element bounds in AX screen coordinates.
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        guard let pr = posRef, let sr = sizeRef else { hidePanel(); return }

        var axOrigin = CGPoint.zero
        var axSize = CGSize.zero
        // swiftlint:disable force_cast
        AXValueGetValue(pr as! AXValue, .cgPoint, &axOrigin)
        AXValueGetValue(sr as! AXValue, .cgSize, &axSize)
        // swiftlint:enable force_cast

        showPanel(at: axOrigin, size: axSize)
    }

    // MARK: - Panel Management

    private func showPanel(at axOrigin: CGPoint, size axSize: CGSize) {
        guard let appState else { return }

        let buttonSize: CGFloat = 28
        let gap: CGFloat = 4

        // AX coordinates: (0,0) = top‑left of primary screen, Y increases downward.
        // NS coordinates:  (0,0) = bottom‑left of primary screen, Y increases upward.
        let screenH = NSScreen.main?.frame.height ?? 800

        // Position: just above the top-right corner of the field, outside it.
        let nsX = axOrigin.x + axSize.width - buttonSize
        let nsY = screenH - axOrigin.y + gap
        let frame = CGRect(x: nsX, y: nsY, width: buttonSize, height: buttonSize)

        if panel == nil {
            let p = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .floating
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

            let onTap: @MainActor () -> Void = { [weak self, weak appState] in
                guard let appState else { return }
                if !appState.isRecording {
                    appState.inlineTargetElement = self?.trackedElement
                }
                appState.toggleRecording()
            }
            p.contentView = NSHostingView(
                rootView: InlineMicButtonView(appState: appState, onTap: onTap)
            )
            panel = p
        }

        panel?.setFrame(frame, display: true)
        panel?.orderFront(nil)
    }

    private func hidePanel() {
        trackedElement = nil
        panel?.orderOut(nil)
    }
}

// MARK: - SwiftUI Button

/// A small circular mic button that lives inside the floating non‑activating panel.
/// Shows a "charging up" ring animation when recording starts so users
/// instinctively wait a beat before speaking.
@available(macOS 14.0, *)
private struct InlineMicButtonView: View {
    var appState: AppState
    var onTap: @MainActor () -> Void

    @State private var chargeProgress: CGFloat = 0
    @State private var isCharging = false
    @State private var chargeComplete = false

    private let chargeDuration: Double = 1.2

    private var glowColor: Color {
        if isCharging { return .yellow }
        if appState.isRecording { return .red }
        if appState.isTranscribing { return .orange }
        return .cyan
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            ZStack {
                if isCharging {
                    // Background ring (track)
                    Circle()
                        .stroke(glowColor.opacity(0.2), lineWidth: 2.5)

                    // Animated charge ring
                    Circle()
                        .trim(from: 0, to: chargeProgress)
                        .stroke(
                            glowColor,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: glowColor.opacity(0.9), radius: 6)
                        .shadow(color: glowColor.opacity(0.5), radius: 12)

                    // Pulsing inner glow
                    Circle()
                        .fill(glowColor.opacity(0.12))

                    Image(systemName: "mic.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(glowColor)
                        .scaleEffect(0.8 + 0.2 * chargeProgress)
                } else {
                    Circle()
                        .stroke(glowColor, lineWidth: 1.5)
                        .shadow(color: glowColor.opacity(0.9), radius: 6)
                        .shadow(color: glowColor.opacity(0.5), radius: 12)

                    Circle()
                        .fill(glowColor.opacity(0.08))

                    if appState.isTranscribing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.5)
                            .tint(glowColor)
                    } else {
                        Image(systemName: appState.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(glowColor)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .opacity(isCharging || appState.isRecording ? 1.0 : 0.65)
        .help(appState.isRecording ? "Stop recording" : "Start recording (Speakr)")
        .onChange(of: appState.isRecording) { wasRecording, isNow in
            if isNow && !wasRecording {
                startCharge()
            } else if !isNow {
                isCharging = false
                chargeComplete = false
                chargeProgress = 0
            }
        }
    }

    private func startCharge() {
        chargeProgress = 0
        isCharging = true
        chargeComplete = false
        withAnimation(.easeInOut(duration: chargeDuration)) {
            chargeProgress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + chargeDuration) {
            isCharging = false
            chargeComplete = true
        }
    }
}

