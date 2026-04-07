import SwiftUI
import AudioCapture
import TranscriptionEngine
import HotkeyService
import TextOutput

/// The menu bar dropdown view with all menu items
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(MenuBarController.self) private var menuBarController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            StatusHeaderView()
                .padding(.horizontal)
                .padding(.bottom, 8)
            
            Divider()
            
            // Recording section
            RecordingSection()
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            // Show recording indicator when active
            if menuBarController.isRecording {
                RecordingIndicatorView()
                    .padding()
                
                Divider()
            } else if menuBarController.isTranscribing {
                ProcessingIndicatorView()
                    .padding()
                
                Divider()
            }
            
            // Quick settings
            QuickSettingsSection()
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            Divider()
            
            // Profile switcher
            ProfileSwitcherSection()
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            Divider()
            
            // Navigation actions
            NavigationSection()
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            Divider()
            
            // Quit button
            QuitSection()
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .frame(width: 280)
    }
}

// MARK: - Status Header

struct StatusHeaderView: View {
    @Environment(MenuBarController.self) private var controller

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: controller.currentStatus.iconName)
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
                .foregroundStyle(controller.currentStatus.color)

            VStack(alignment: .leading, spacing: 2) {
                Text("Speakr")
                    .font(.system(size: 13, weight: .semibold))

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.top, 12)
    }

    private var statusText: String {
        switch controller.currentStatus {
        case .idle: return "Ready"
        case .recording: return "Recording..."
        case .processing: return "Processing..."
        case .error(let msg): return msg
        }
    }
}

// MARK: - Recording Section

struct RecordingSection: View {
    @Environment(AppState.self) private var appState
    @Environment(MenuBarController.self) private var menuBarController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if menuBarController.isRecording {
                MenuBarButton(
                    title: "Stop Recording",
                    icon: "stop.fill",
                    color: .red,
                    action: stopRecording
                )
            } else if menuBarController.isTranscribing {
                MenuBarButton(
                    title: "Cancel",
                    icon: "xmark",
                    color: .orange,
                    action: cancelProcessing
                )
            } else {
                MenuBarButton(
                    title: "Start Recording",
                    icon: "record.circle.fill",
                    color: .red,
                    action: startRecording
                )

                HStack {
                    Spacer()
                    Text("⌥Space")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func startRecording() {
        Task { await appState.startRecording() }
    }

    private func stopRecording() {
        Task { await appState.stopRecording() }
    }

    private func cancelProcessing() {
        appState.transcriptionEngine.cancelTranscription()
        Task { await appState.audioCapture.stopRecording() }
        appState.isTranscribing = false
        appState.isRecording = false
        menuBarController.setIdle()
    }
}

// MARK: - Quick Settings Section

struct QuickSettingsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(MenuBarController.self) private var controller
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Settings")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            HStack(spacing: 12) {
                // Language toggle
                QuickSettingButton(
                    icon: "globe",
                    title: appState.settingsStore.settings.transcriptionLanguage.rawValue == "auto" ? "Auto" : appState.settingsStore.settings.transcriptionLanguage.rawValue.uppercased(),
                    subtitle: "Language"
                )
                
                // Model info
                let modelName = appState.transcriptionEngine.loadedModel?.displayName ?? "None"
                QuickSettingButton(
                    icon: "cpu",
                    title: modelName,
                    subtitle: "Model"
                )
                
                // Punctuation
                QuickSettingButton(
                    icon: "text.quote",
                    title: appState.settingsStore.settings.autoPunctuation ? "On" : "Off",
                    subtitle: "Punctuation"
                )
            }
        }
    }
}

struct QuickSettingButton: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        Button {
            // Open settings to this section
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.secondary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile Switcher

struct ProfileSwitcherSection: View {
    @Environment(MenuBarController.self) private var controller
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                Button {
                    // Open profile settings
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            
            // Current profile display
            HStack(spacing: 10) {
                Image(systemName: controller.selectedProfile.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(controller.selectedProfile.color.swiftUIColor)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(controller.selectedProfile.color.swiftUIColor.opacity(0.15))
                    )
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(controller.selectedProfile.name)
                        .font(.system(size: 13, weight: .medium))
                    
                    Text(profileDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Profile picker popover trigger
                Menu {
                    ForEach(controller.profiles) { profile in
                        Button {
                            controller.selectProfile(profile)
                        } label: {
                            HStack {
                                Image(systemName: profile.icon)
                                    .foregroundStyle(profile.color.swiftUIColor)
                                Text(profile.name)
                                if profile == controller.selectedProfile {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button {
                        // Create new profile - open settings
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        Label("New Profile...", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
            }
        }
    }
    
    private var profileDescription: String {
        let settings = controller.selectedProfile.settings
        let lang = settings.language == "auto" ? "Auto" : settings.language.uppercased()
        return "\(lang) • \(settings.model.displayName)"
    }
}

// MARK: - Navigation Section

struct NavigationSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                MenuBarNavigationButton(
                    title: "Open Main Window...",
                    icon: "window",
                    action: openMainWindow
                )
                
                MenuBarNavigationButton(
                    title: "Open Settings...",
                    icon: "gear",
                    action: openSettings
                )
                
                MenuBarNavigationButton(
                    title: "Manage Models...",
                    icon: "cloud.arrow.down",
                    action: openModelManager
                )
            }
        }
    }
    
    private func openMainWindow() {
        dismiss()
        appState.showMainWindow()
    }
    
    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    
    private func openModelManager() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - Quit Section

struct QuitSection: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        MenuBarButton(
            title: "Quit Speakr",
            icon: "power",
            color: .primary,
            action: quitApp
        )
    }
    
    private func quitApp() {
        dismiss()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Reusable Components

struct MenuBarButton: View {
    let title: String
    let icon: String
    var color: Color = .primary
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 13))
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

struct MenuBarNavigationButton: View {
    let title: String
    let icon: String
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 13))
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.clear)
                .hoverEffect()
        )
    }
}

// MARK: - Extensions

extension View {
    func hoverEffect() -> some View {
        self.modifier(HoverEffectModifier())
    }
}

struct HoverEffectModifier: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? .secondary.opacity(0.1) : Color.clear)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovered = hovering
                }
            }
    }
}
