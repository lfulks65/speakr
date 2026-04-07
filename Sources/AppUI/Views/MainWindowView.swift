import SwiftUI
import AVFoundation

// MARK: - Permissions Gate

/// Blocks the entire UI until both Microphone and Accessibility permissions are granted.
/// Polls every 2 seconds so it auto-advances when the user flips the toggle in System Settings.
struct PermissionsGateView: View {
    @Environment(AppState.self) private var appState

    @State private var micGranted = false
    @State private var axGranted = false
    @State private var filesGranted = false
    @State private var micRequested = false
    @State private var timer: Timer?

    private var allGranted: Bool { micGranted && axGranted && filesGranted }

    var body: some View {
        if allGranted {
            MainWindowView()
                .environment(appState)
                .onAppear { appState.onPermissionsGranted() }
        } else {
            gateContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
                .onAppear { startPolling() }
                .onDisappear { stopPolling() }
        }
    }

    // MARK: - Gate UI

    private var gateContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)

                VStack(spacing: 8) {
                    Text("Permissions Required")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Speakr needs the following permissions to function.\nGrant them below to get started.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                VStack(spacing: 16) {
                    permissionCard(
                        icon: "mic.circle.fill",
                        iconColor: .red,
                        title: "Microphone",
                        subtitle: "Record your voice for transcription.",
                        granted: micGranted,
                        action: requestMicrophone
                    )

                    permissionCard(
                        icon: "keyboard.badge.eye.fill",
                        iconColor: .blue,
                        title: "Accessibility",
                        subtitle: "Paste transcribed text into other apps.",
                        granted: axGranted,
                        action: requestAccessibility
                    )

                    permissionCard(
                        icon: "folder.circle.fill",
                        iconColor: .orange,
                        title: "Files & Folders",
                        subtitle: "Store AI models for local transcription.",
                        granted: filesGranted,
                        action: requestFilesAccess
                    )
                }
                .frame(maxWidth: 480)

                Text("Permissions are checked automatically every few seconds.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(40)
    }

    private func permissionCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(granted ? .green : iconColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            } else {
                Button("Grant") { action() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(granted ? Color.green.opacity(0.06) : Color.secondary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(granted ? Color.green.opacity(0.25) : Color.secondary.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Permission Actions

    private func requestMicrophone() {
        micRequested = true
        wfLog("▶ requestMicrophone tapped")
        Task {
            let granted = await _triggerMicPermission()
            wfLog("  requestMicrophone result: \(granted)")
            micGranted = granted
            if !granted { openMicSettings() }
        }
    }

    private func requestAccessibility() {
        let trusted = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
        axGranted = trusted
        if !trusted { openAccessibilitySettings() }
    }

    private func requestFilesAccess() {
        // Access ~/Documents to trigger the macOS TCC "Files & Folders" prompt.
        // This is what WhisperKit hits internally, so we surface it here to avoid
        // a surprise popup later.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let docs {
            _ = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)
        }

        // Also ensure the model storage directory exists
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let modelDir = appSupport.appendingPathComponent("Speakr/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Brief delay so macOS has time to process the prompt before we re-check
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            filesGranted = checkFilesAccess()
            if !filesGranted {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: - Polling

    @MainActor
    private func checkPermissions() {
        let micStatus = AVAudioApplication.shared.recordPermission
        micGranted = micStatus == .granted
        axGranted = AXIsProcessTrusted()
        filesGranted = checkFilesAccess()
    }

    /// Checks if the app can access TCC-protected directories (Documents).
    /// Returns true if file access is granted or if the directory isn't
    /// TCC-restricted on this macOS version.
    private func checkFilesAccess() -> Bool {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return true
        }
        do {
            _ = try FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)
            return true
        } catch {
            return false
        }
    }

    private func startPolling() {
        checkPermissions()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [self] _ in
            DispatchQueue.main.async {
                checkPermissions()
            }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - System Settings Openers

    private func openMicSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Triggers the macOS microphone permission dialog by briefly starting the
/// audio engine. On macOS, `AVAudioApplication.requestRecordPermission` alone
/// may not show the system prompt — the system only asks when an app actually
/// tries to access the audio hardware. This function starts AVAudioEngine,
/// which triggers the TCC prompt, then immediately stops it.
private nonisolated func _triggerMicPermission() async -> Bool {
    // First try the standard API — works if status is .undetermined
    let status = AVAudioApplication.shared.recordPermission
    if status == .granted { return true }

    if status == .undetermined {
        // Try the API-based request first
        let ok = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        if ok { return true }
    }

    // If the API didn't show a prompt, actually touch the hardware to force it.
    // AVAudioEngine.inputNode triggers the TCC dialog on macOS.
    do {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { _, _ in }
        try engine.start()
        // Tiny delay so the system has time to show the prompt
        try? await Task.sleep(for: .milliseconds(200))
        engine.stop()
        inputNode.removeTap(onBus: 0)
    } catch {
        // Engine start may fail if permission denied — that's expected
    }

    // Check the result after the hardware attempt
    return AVAudioApplication.shared.recordPermission == .granted
}

// MARK: - Main Window

/// Main application window content
struct MainWindowView: View {
    @Environment(AppState.self) private var appState

    @State private var showingOnboarding = false
    @State private var selectedNavigation: NavigationItem? = .history

    var body: some View {
        NavigationSplitView {
            List(NavigationItem.allCases, selection: $selectedNavigation) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationTitle("Speakr")
            .listStyle(.sidebar)
        } detail: {
            detailView
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                showingOnboarding = false
            }
            .frame(minWidth: 560, minHeight: 480)
            .overlay(alignment: .topLeading) {
                Button {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    showingOnboarding = false
                } label: {
                    ZStack {
                        Circle()
                            .fill(.secondary.opacity(0.3))
                            .frame(width: 30, height: 30)
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .buttonStyle(.plain)
                .help("Close")
                .padding(12)
            }
        }
        .onAppear {
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                showingOnboarding = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingOnboarding = true
                } label: {
                    Label("Setup Guide", systemImage: "questionmark.circle")
                }
                .help("Open setup guide")
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedNavigation ?? .history {
        case .history:
            HistoryView()
                .environment(appState)
        case .snippets:
            SnippetsView()
                .environment(appState)
        case .settings:
            SettingsWindowView()
                .environment(appState)
        }
    }
}

// MARK: - Navigation

enum NavigationItem: String, CaseIterable, Identifiable, Hashable {
    case history = "History"
    case snippets = "Snippets"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .history: return "clock"
        case .snippets: return "text.badge.plus"
        case .settings: return "gear"
        }
    }
}

// MARK: - History View

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    private var filteredHistory: [TranscriptionEntry] {
        if searchText.isEmpty {
            return appState.transcriptionHistory
        }
        return appState.transcriptionHistory.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if appState.transcriptionHistory.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("History")
        .searchable(text: $searchText, prompt: "Search transcriptions")
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                if !appState.transcriptionHistory.isEmpty {
                    Button(role: .destructive) {
                        appState.clearHistory()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .help("Clear all history")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 56))
                .foregroundStyle(.secondary.opacity(0.4))
            VStack(spacing: 8) {
                Text("No Transcriptions Yet")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("Press ⌥Space to start recording.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var historyList: some View {
        List {
            ForEach(filteredHistory) { entry in
                HistoryRow(entry: entry)
                    .contextMenu {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.text, forType: .string)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            appState.deleteHistoryEntry(entry)
                        }
                    }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}

struct HistoryRow: View {
    let entry: TranscriptionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text)
                .font(.body)
                .lineLimit(3)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Label(entry.date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                Label(String(format: "%.1fs", entry.durationSeconds), systemImage: "timer")
                if let app = entry.appName {
                    Label(app, systemImage: "app")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Snippets View

struct SnippetsView: View {
    @Environment(AppState.self) private var appState
    @State private var newTrigger = ""
    @State private var newExpansion = ""
    @State private var editingSnippet: Snippet?

    var body: some View {
        VStack(spacing: 0) {
            // Add new snippet bar
            HStack(spacing: 12) {
                TextField("Trigger word", text: $newTrigger)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                TextField("Expands to...", text: $newExpansion)
                    .textFieldStyle(.roundedBorder)

                Button {
                    addSnippet()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(newTrigger.isEmpty || newExpansion.isEmpty)
                .help("Add snippet")
            }
            .padding()

            Divider()

            if appState.snippets.isEmpty {
                snippetsEmptyState
            } else {
                snippetsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Snippets")
    }

    private var snippetsEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.secondary.opacity(0.4))
            VStack(spacing: 8) {
                Text("No Snippets")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("Define trigger words that automatically expand into longer text.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
                Text("Example: say \"sig\" and it becomes your full email signature.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private var snippetsList: some View {
        List {
            ForEach(appState.snippets) { snippet in
                SnippetRow(
                    snippet: snippet,
                    onUpdate: { updated in updateSnippet(updated) },
                    onDelete: { deleteSnippet(snippet) }
                )
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func addSnippet() {
        let snippet = Snippet(trigger: newTrigger.trimmingCharacters(in: .whitespaces),
                              expansion: newExpansion)
        appState.snippets.append(snippet)
        newTrigger = ""
        newExpansion = ""
    }

    private func updateSnippet(_ snippet: Snippet) {
        if let idx = appState.snippets.firstIndex(where: { $0.id == snippet.id }) {
            appState.snippets[idx] = snippet
        }
    }

    private func deleteSnippet(_ snippet: Snippet) {
        appState.snippets.removeAll { $0.id == snippet.id }
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    var onUpdate: (Snippet) -> Void
    var onDelete: () -> Void

    @State private var isEditing = false
    @State private var editTrigger: String = ""
    @State private var editExpansion: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                editView
            } else {
                displayView
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Edit") { startEditing() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private var displayView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(snippet.trigger)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.cyan)

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(snippet.expansion)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 8) {
                Button { startEditing() } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)

                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var editView: some View {
        HStack(spacing: 12) {
            TextField("Trigger", text: $editTrigger)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)

            TextField("Expansion", text: $editExpansion)
                .textFieldStyle(.roundedBorder)

            Button("Save") {
                var updated = snippet
                updated.trigger = editTrigger.trimmingCharacters(in: .whitespaces)
                updated.expansion = editExpansion
                onUpdate(updated)
                isEditing = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(editTrigger.isEmpty || editExpansion.isEmpty)

            Button("Cancel") { isEditing = false }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func startEditing() {
        editTrigger = snippet.trigger
        editExpansion = snippet.expansion
        isEditing = true
    }
}
