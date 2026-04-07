import SwiftUI
import Combine
import AppKit
import ApplicationServices
import AudioCapture
import TranscriptionEngine
import HotkeyService
import TextOutput
import Settings

// MARK: - Models

/// A single transcription entry with timestamp.
public struct TranscriptionEntry: Identifiable, Codable {
    public let id: UUID
    public let text: String
    public let date: Date
    public let durationSeconds: Double
    public let appName: String?

    public init(text: String, durationSeconds: Double, appName: String?) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.durationSeconds = durationSeconds
        self.appName = appName
    }
}

/// A user-defined text expansion snippet.
public struct Snippet: Identifiable, Codable, Equatable {
    public let id: UUID
    public var trigger: String
    public var expansion: String

    public init(trigger: String, expansion: String) {
        self.id = UUID()
        self.trigger = trigger
        self.expansion = expansion
    }
}

/// Global application state managed via SwiftUI's @Observable
@available(macOS 14.0, *)
@Observable
@MainActor
public final class AppState {
    
    // MARK: - Services
    public let settingsStore: SettingsStore
    public let audioCapture: AudioCapture
    public let transcriptionEngine: TranscriptionEngine
    public let hotkeyService: HotkeyService
    public let textOutput: TextOutput
    
    // MARK: - State Properties
    public var isRecording = false
    public var isTranscribing = false
    public var currentStatusMessage = "Ready"
    public var lastTranscription: String?
    public var showAboutPanel: Bool = false

    /// Running history of all transcriptions this session (persisted to disk).
    public var transcriptionHistory: [TranscriptionEntry] = []

    /// User-defined text snippets: when a trigger word appears in the
    /// transcription output it gets replaced with the expansion text.
    public var snippets: [Snippet] = [] {
        didSet { saveSnippets() }
    }

    // MARK: - Menu Bar Controller (injected after init)
    weak var menuBarController: MenuBarController?

    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var recordingTask: Task<Void, Never>?
    private var currentRecordingURL: URL?
    /// The app that was frontmost when the user started recording (hotkey path).
    private var recordingTargetApp: NSRunningApplication?
    /// The exact AX element the user tapped the inline mic button on.
    /// Set by InlineTriggerService before calling toggleRecording(); cleared
    /// after outputTranscription uses it.
    var inlineTargetElement: AXUIElement?
    /// Shows a floating mic button near focused text fields in other apps.
    let inlineTrigger = InlineTriggerService()
    
    // MARK: - Initialization
    public init() {
        wfLog("▶ AppState.init() begin — thread: \(Thread.isMainThread ? "main" : "bg")")

        wfLog("  creating SettingsStore...")
        self.settingsStore = SettingsStore()
        wfLog("  SettingsStore done")

        wfLog("  creating AudioCapture...")
        self.audioCapture = AudioCapture()
        wfLog("  AudioCapture done")

        wfLog("  creating TranscriptionEngine...")
        self.transcriptionEngine = TranscriptionEngine()
        wfLog("  TranscriptionEngine done")

        wfLog("  creating HotkeyService...")
        self.hotkeyService = HotkeyService(settings: settingsStore)
        wfLog("  HotkeyService done")

        wfLog("  creating TextOutput...")
        self.textOutput = TextOutput()
        wfLog("  TextOutput done")

        loadPersistedData()
        setupHotkeyHandler()
        wfLog("▶ AppState.init() complete — scheduling deferred startup task")

        Task {
            wfLog("▶ Deferred startup task: sleeping 200ms...")
            try? await Task.sleep(for: .milliseconds(200))
            wfLog("▶ Deferred startup task: calling hotkeyService.startListening()...")
            hotkeyService.startListening()
            wfLog("▶ Deferred startup task: complete (model load deferred until permissions granted)")
        }
    }

    /// Called by PermissionsGateView once all required permissions are granted.
    /// Loads the Whisper model and starts the inline trigger service.
    public func onPermissionsGranted() {
        guard !didFinishPermissions else { return }
        didFinishPermissions = true
        wfLog("▶ onPermissionsGranted — loading model + starting inline trigger")
        Task {
            await loadInitialModel()
            inlineTrigger.start(with: self)
            wfLog("▶ onPermissionsGranted complete")
        }
    }
    private var didFinishPermissions = false

    // MARK: - Public Methods
    
    /// Toggle recording state (called by hotkey)
    public func toggleRecording() {
        Task {
            if isRecording {
                await stopRecording()
            } else {
                await startRecording()
            }
        }
    }
    
    /// Start recording audio
    public func startRecording() async {
        wfLog("▶ startRecording() begin")
        // Capture the frontmost app now, before any Speakr window can steal focus.
        recordingTargetApp = NSWorkspace.shared.frontmostApplication
        wfLog("  target app: \(recordingTargetApp?.localizedName ?? "none")")
        do {
            wfLog("  requesting mic permission...")
            currentStatusMessage = "Requesting microphone permission..."
            let hasPermission = await audioCapture.requestPermission()
            wfLog("  mic permission: \(hasPermission)")
            
            guard hasPermission else {
                currentStatusMessage = "Microphone permission denied"
                menuBarController?.setError("Mic permission denied")
                return
            }
            
            wfLog("  calling audioCapture.startRecording()...")
            currentStatusMessage = "Recording..."
            let url = try await audioCapture.startRecording()
            wfLog("  audioCapture.startRecording() returned: \(url.lastPathComponent)")
            currentRecordingURL = url
            isRecording = true
            menuBarController?.startRecording()
        } catch {
            wfLog("[ERROR] " + "  startRecording error: \(error)")
            currentStatusMessage = "Recording error: \(error.localizedDescription)"
            isRecording = false
            menuBarController?.setError(error.localizedDescription)
        }
    }
    
    /// Stop recording and transcribe
    public func stopRecording() async {
        wfLog("▶ stopRecording() begin")
        isRecording = false
        currentStatusMessage = "Transcribing..."
        isTranscribing = true
        menuBarController?.stopRecording()
        
        wfLog("  calling audioCapture.stopRecording()...")
        guard let url = await audioCapture.stopRecording() else {
            wfLog("[WARN] " + "  audioCapture.stopRecording() returned nil")
            currentStatusMessage = "Failed to stop recording"
            isTranscribing = false
            menuBarController?.setIdle()
            return
        }
        wfLog("  stopRecording file: \(url.lastPathComponent)")
        
        do {
            wfLog("  calling transcriptionEngine.transcribe()...")
            let result = try await transcriptionEngine.transcribe(
                audioURL: url,
                language: settingsStore.settings.transcriptionLanguage.rawValue == "auto" ? nil : settingsStore.settings.transcriptionLanguage.rawValue
            )
            wfLog("  transcribe() done in \(String(format: "%.2f", result.processingTime))s")
            
            let finalText = applySnippets(to: result.text)
            lastTranscription = finalText
            isTranscribing = false
            currentStatusMessage = "Done (\(String(format: "%.1f", result.processingTime))s)"
            menuBarController?.setIdle()

            let entry = TranscriptionEntry(
                text: finalText,
                durationSeconds: result.processingTime,
                appName: recordingTargetApp?.localizedName
            )
            transcriptionHistory.insert(entry, at: 0)
            saveHistory()

            await outputTranscription(finalText)
        } catch {
            wfLog("[ERROR] " + "  transcribe error: \(error)")
            isTranscribing = false
            currentStatusMessage = "Transcription error: \(error.localizedDescription)"
            menuBarController?.setError(error.localizedDescription)
        }
    }
    
    /// Show the main window
    public func showMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Focus the main window
        if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "main-window" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    /// Show about panel
    public func openAboutPanel() {
        showAboutPanel = true
    }
    
    // MARK: - Private Methods
    
    private func setupHotkeyHandler() {
        hotkeyService.setHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleRecording()
            }
        }
    }
    
    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        wfLog("  Accessibility not granted — showing system prompt")
        // Calling with prompt:true triggers the macOS "Allow accessibility" alert
        // and registers the app in System Settings → Privacy → Accessibility.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private func loadInitialModel() async {
        wfLog("▶ loadInitialModel() begin")
        let modelSize = settingsStore.settings.modelSize
        let whisperSize: WhisperModelSize
        switch modelSize {
        case .tiny: whisperSize = .tiny
        case .base: whisperSize = .base
        case .small: whisperSize = .small
        case .medium: whisperSize = .medium
        case .largeV3: whisperSize = .largeV3
        }
        do {
            wfLog("  loading model: \(whisperSize.rawValue)")
            try await transcriptionEngine.loadModel(whisperSize)
            wfLog("  model loaded OK")
        } catch {
            wfLog("[ERROR] " + "  loadModel error: \(error)")
        }
    }
    
    private func outputTranscription(_ text: String) async {
        wfLog("━━━ outputTranscription BEGIN ━━━")
        wfLog("  text: \"\(text.prefix(60))\"")
        wfLog("  autoPaste=\(settingsStore.settings.autoPaste)  autoCopy=\(settingsStore.settings.autoCopyToClipboard)")
        wfLog("  AXIsProcessTrusted=\(AXIsProcessTrusted())")
        wfLog("  inlineTargetElement=\(inlineTargetElement != nil ? "SET" : "nil")")
        wfLog("  recordingTargetApp=\(recordingTargetApp?.localizedName ?? "nil") bundle=\(recordingTargetApp?.bundleIdentifier ?? "nil")")
        wfLog("  frontmostApp=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil")")

        // Always copy to clipboard first — reliable manual fallback.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let clipOK = NSPasteboard.general.string(forType: .string) == text
        wfLog("  clipboard write: \(clipOK ? "OK" : "FAILED")")

        guard settingsStore.settings.autoPaste else {
            wfLog("  autoPaste is OFF — stopping after clipboard copy")
            return
        }

        // Determine which app to paste into.
        // Inline path: user clicked the floating mic button → we know the PID.
        // Hotkey path: we captured the frontmost app at recording start.
        var targetApp: NSRunningApplication?
        if let element = inlineTargetElement {
            inlineTargetElement = nil
            var elemPid: pid_t = 0
            AXUIElementGetPid(element, &elemPid)
            targetApp = NSRunningApplication(processIdentifier: elemPid)
            wfLog("  PATH: inline trigger — element pid=\(elemPid)")
        } else {
            targetApp = recordingTargetApp.flatMap {
                $0.bundleIdentifier != Bundle.main.bundleIdentifier ? $0 : nil
            }
            wfLog("  PATH: hotkey — target=\(targetApp?.localizedName ?? "nil")")
        }

        // Paste with retry — other apps (e.g. Krisp meeting note-taker) may
        // steal focus by popping a modal right when the microphone is released.
        // We retry up to 3 times with increasing delays to ride it out.
        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            wfLog("  paste attempt \(attempt)/\(maxAttempts)")

            if let targetApp {
                targetApp.activate()
                // First attempt: short delay. Later attempts: longer, to let
                // interfering modals appear and settle.
                let delay = attempt == 1 ? 400 : 800
                try? await Task.sleep(for: .milliseconds(delay))
            }

            let frontmost = NSWorkspace.shared.frontmostApplication
            let frontmostName = frontmost?.localizedName ?? "nil"
            let isFrontmost = targetApp == nil || frontmost?.processIdentifier == targetApp?.processIdentifier
            wfLog("  frontmost=\(frontmostName) isFrontmost=\(isFrontmost)")

            if isFrontmost {
                postCmdVToFrontmost()
                wfLog("━━━ outputTranscription END (attempt \(attempt)) ━━━")
                return
            }
            wfLog("  target not frontmost — another app stole focus, retrying...")
        }

        // All retries exhausted — force-activate once more and paste anyway.
        wfLog("  retries exhausted — forcing final paste")
        if let targetApp { targetApp.activate() }
        try? await Task.sleep(for: .milliseconds(500))
        postCmdVToFrontmost()
        wfLog("━━━ outputTranscription END (forced) ━━━")
    }

    /// Posts ⌘V to the HID event tap — delivers to the currently frontmost app
    /// via the normal macOS routing chain, reaching Electron renderers correctly.
    private func postCmdVToFrontmost() {
        wfLog("  postCmdVToFrontmost: AXTrusted=\(AXIsProcessTrusted())")
        guard AXIsProcessTrusted() else {
            wfLog("  postCmdVToFrontmost: BLOCKED — AX not trusted")
            return
        }
        let src = CGEventSource(stateID: .hidSystemState)
        guard
            let dn = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        else {
            wfLog("  postCmdVToFrontmost: could not create CGEvent")
            return
        }
        dn.flags = .maskCommand
        up.flags = .maskCommand
        dn.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        wfLog("  postCmdVToFrontmost: ⌘V posted to HID tap")
    }
    
    // MARK: - Snippet Expansion

    /// Replaces trigger words in the transcribed text with their expansions.
    /// Matching is case-insensitive and whole-word.
    private func applySnippets(to text: String) -> String {
        guard !snippets.isEmpty else { return text }
        var result = text
        for snippet in snippets {
            guard !snippet.trigger.isEmpty else { continue }
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: snippet.trigger))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result),
                    withTemplate: NSRegularExpression.escapedTemplate(for: snippet.expansion)
                )
            }
        }
        return result
    }

    // MARK: - Persistence

    private static let historyKey = "speakr_history"
    private static let snippetsKey = "speakr_snippets"

    func loadPersistedData() {
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let entries = try? JSONDecoder().decode([TranscriptionEntry].self, from: data) {
            transcriptionHistory = entries
        }
        if let data = UserDefaults.standard.data(forKey: Self.snippetsKey),
           let items = try? JSONDecoder().decode([Snippet].self, from: data) {
            snippets = items
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(transcriptionHistory) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    private func saveSnippets() {
        if let data = try? JSONEncoder().encode(snippets) {
            UserDefaults.standard.set(data, forKey: Self.snippetsKey)
        }
    }

    public func deleteHistoryEntry(_ entry: TranscriptionEntry) {
        transcriptionHistory.removeAll { $0.id == entry.id }
        saveHistory()
    }

    public func clearHistory() {
        transcriptionHistory.removeAll()
        saveHistory()
    }
}
