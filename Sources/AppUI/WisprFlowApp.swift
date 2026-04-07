import SwiftUI
import AudioCapture
import TranscriptionEngine
import HotkeyService
import TextOutput
import Settings


@main
struct SpeakrApp: App {
    @State private var appState: AppState
    @State private var menuBarController: MenuBarController

    init() {
        wfLog("▶ SpeakrApp.init()")
        let controller = MenuBarController()
        let state = AppState()
        state.menuBarController = controller
        _menuBarController = State(initialValue: controller)
        _appState = State(initialValue: state)
        wfLog("▶ SpeakrApp.init() complete")
    }

    var body: some Scene {
        // IMPORTANT: do NOT read any @Observable properties here — every read
        // creates an observation dependency that causes App.body (and therefore
        // makeMainMenu) to re-run on every state change. Keep this side-effect-free.

        WindowGroup("Speakr", id: "main-window") {
            PermissionsGateView()
                .environment(appState)
                .environment(menuBarController)
        }
        .defaultPosition(.center)
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) {
                Button("About Speakr") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }

        Settings {
            SettingsWindowView()
                .environment(appState)
                .environment(menuBarController)
        }

        // Use .constant(true) instead of $menuBarController.showMenuInMenuBar.
        // The isInserted: Binding<Bool> variant reads the property during App.body
        // evaluation, which creates an observation dependency that causes App.body
        // (and therefore makeMainMenu) to re-run on every menuBarController change.
        // .constant(true) creates no observation dependency at all.
        MenuBarExtra(isInserted: .constant(true)) {
            MenuBarView()
                .environment(appState)
                .environment(menuBarController)
        } label: {
            MenuBarIconView()
                .environment(menuBarController)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar Controller

/// Controls the menu bar icon and state visualization
@Observable
@MainActor
final class MenuBarController: Sendable {
    var currentStatus: MenuBarStatus = .idle
    var audioLevel: Float = 0.0
    var selectedProfile: Profile = .defaultProfile
    var profiles: [Profile] = [.defaultProfile, .workProfile, .personalProfile]

    // Derived state — computed so MenuBarView reads currentStatus, not separate bools
    var isRecording: Bool {
        if case .recording = currentStatus { return true }
        return false
    }
    var isTranscribing: Bool {
        if case .processing = currentStatus { return true }
        return false
    }

    // Stored only for formatted duration display; read directly (no timer needed)
    private(set) var recordingStartTime: Date?

    enum MenuBarStatus: Equatable {
        case idle
        case recording(startTime: Date)
        case processing(progress: Double)
        case error(String)
        
        var iconName: String {
            switch self {
            case .idle:
                return "waveform.circle"
            case .recording:
                return "record.circle.fill"
            case .processing:
                return "waveform.circle.fill"
            case .error:
                return "exclamationmark.triangle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .idle:
                return .primary
            case .recording:
                return .red
            case .processing:
                return .blue
            case .error:
                return .orange
            }
        }
    }
    
    func startRecording() {
        recordingStartTime = Date()
        currentStatus = .recording(startTime: recordingStartTime!)
    }

    func stopRecording() {
        currentStatus = .processing(progress: 0)
    }

    func setProcessing(progress: Double) {
        currentStatus = .processing(progress: progress)
    }

    func setIdle() {
        currentStatus = .idle
        recordingStartTime = nil
    }

    func setError(_ message: String) {
        currentStatus = .error(message)
        recordingStartTime = nil
    }

    func setAudioLevel(_ level: Float) {
        audioLevel = min(max(level, 0), 1)
    }

    func selectProfile(_ profile: Profile) {
        selectedProfile = profile
    }
}

// MARK: - Profile Model

struct Profile: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var color: ProfileColor
    var settings: ProfileSettings
    
    static let defaultProfile = Profile(
        id: UUID(),
        name: "Default",
        icon: "person",
        color: .blue,
        settings: ProfileSettings()
    )
    
    static let workProfile = Profile(
        id: UUID(),
        name: "Work",
        icon: "briefcase",
        color: .green,
        settings: ProfileSettings(language: "en", autoPunctuation: true)
    )
    
    static let personalProfile = Profile(
        id: UUID(),
        name: "Personal",
        icon: "house",
        color: .purple,
        settings: ProfileSettings(language: "auto", autoPunctuation: false)
    )
}

enum ProfileColor: String, Codable, CaseIterable {
    case blue, green, purple, orange, pink, teal
    
    var swiftUIColor: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .purple: return .purple
        case .orange: return .orange
        case .pink: return .pink
        case .teal: return .teal
        }
    }
}

struct ProfileSettings: Codable, Equatable, Hashable {
    var language: String = "auto"
    var autoPunctuation: Bool = true
    var model: WhisperModelSize = .base
}
