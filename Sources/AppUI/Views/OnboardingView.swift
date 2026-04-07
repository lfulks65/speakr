import SwiftUI
import AVFoundation
import TranscriptionEngine
import WhisperKit

/// First-launch onboarding flow for new users
struct OnboardingView: View {
    var onComplete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var hasMicrophonePermission = false
    @State private var hasAccessibilityPermission = false
    @State private var isCheckingPermissions = false
    @State private var selectedModel: WhisperModelSize = .base
    @State private var isModelDownloaded = false

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            HStack(spacing: 4) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index <= currentStep ? Color.accentColor : Color.gray.opacity(0.2))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 50)
            .padding(.top, 16)
            .padding(.bottom, 4)

            // Content
            Group {
                switch currentStep {
                case 0:
                    WelcomeStep()
                case 1:
                    MicrophonePermissionStep(
                        hasPermission: $hasMicrophonePermission
                    )
                case 2:
                    AccessibilityPermissionStep(
                        hasPermission: $hasAccessibilityPermission
                    )
                case 3:
                    DownloadModelStep(
                        selectedModel: $selectedModel,
                        isDownloaded: $isModelDownloaded
                    )
                case 4:
                    SetupCompleteStep()
                default:
                    WelcomeStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation buttons
            HStack {
                if currentStep > 0 && currentStep < totalSteps - 1 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button("Continue") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        (currentStep == 1 && !hasMicrophonePermission) ||
                        (currentStep == 2 && !hasAccessibilityPermission)
                    )
                } else {
                    Button("Get Started") {
                        complete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 480)
        .background(.windowBackground)
    }

    private func complete() {
        if let onComplete {
            onComplete()
        } else {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            dismiss()
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // App icon
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
            
            VStack(spacing: 12) {
                Text("Welcome to Speakr")
                    .font(.system(size: 28, weight: .semibold))
                
                Text("Your private, local transcription assistant")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "lock.fill",
                    iconColor: .green,
                    title: "Completely Private",
                    description: "All transcription happens on your Mac. No cloud, no data sent to servers."
                )
                
                FeatureRow(
                    icon: "keyboard.fill",
                    iconColor: .blue,
                    title: "Global Hotkey",
                    description: "Press ⌃⌥Space from any app to start dictating."
                )
                
                FeatureRow(
                    icon: "text.insert",
                    iconColor: .purple,
                    title: "Instant Text Insertion",
                    description: "Transcribed text is automatically typed into the active application."
                )
            }
            .frame(maxWidth: 420)
            
            Spacer()
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(iconColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Microphone Permission Step

struct MicrophonePermissionStep: View {
    @Binding var hasPermission: Bool
    @State private var permissionStatus: PermissionStatus = .unknown
    @State private var isChecking = false
    
    enum PermissionStatus {
        case unknown
        case requesting
        case granted
        case denied
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 80))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
            
            VStack(spacing: 12) {
                Text("Microphone Access")
                    .font(.system(size: 24, weight: .semibold))
                
                Text("Speakr needs access to your microphone to transcribe your voice.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            VStack(spacing: 16) {
                PermissionStatusRow(
                    status: permissionStatus == .granted ? .granted : (permissionStatus == .denied ? .denied : .pending),
                    title: "Microphone Access",
                    description: permissionStatus == .granted 
                        ? "Access granted. You can change this in System Settings anytime."
                        : "Required to record and transcribe your voice"
                )
                
                if permissionStatus == .denied {
                    Button("Open System Settings") {
                        openMicrophoneSettings()
                    }
                    .buttonStyle(.bordered)
                } else if permissionStatus != .granted {
                    Button {
                        requestMicrophonePermission()
                    } label: {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Request Access")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isChecking)
                }
            }
            .padding(.vertical)
            
            Spacer()
        }
        .padding()
        .onAppear {
            checkCurrentPermission()
        }
    }
    
    private func checkCurrentPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permissionStatus = .granted
            hasPermission = true
        case .denied, .restricted:
            permissionStatus = .denied
            hasPermission = false
        case .notDetermined:
            permissionStatus = .unknown
            hasPermission = false
        @unknown default:
            permissionStatus = .unknown
            hasPermission = false
        }
    }
    
    private func requestMicrophonePermission() {
        isChecking = true
        permissionStatus = .requesting
        
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                isChecking = false
                if granted {
                    permissionStatus = .granted
                    hasPermission = true
                } else {
                    permissionStatus = .denied
                    hasPermission = false
                }
            }
        }
    }
    
    private func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Accessibility Permission Step

struct AccessibilityPermissionStep: View {
    @Binding var hasPermission: Bool
    @State private var permissionStatus: PermissionStatus = .unknown
    @State private var isChecking = false
    
    enum PermissionStatus {
        case unknown
        case requesting
        case granted
        case denied
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "keyboard.badge.eye.fill")
                .font(.system(size: 80))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
            
            VStack(spacing: 12) {
                Text("Accessibility Access")
                    .font(.system(size: 24, weight: .semibold))
                
                Text("Speakr needs accessibility access to type transcribed text into other applications.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                PermissionStatusRow(
                    status: permissionStatus == .granted ? .granted : (permissionStatus == .denied ? .denied : .pending),
                    title: "Accessibility Access",
                    description: permissionStatus == .granted 
                        ? "Access granted. You can change this in System Settings anytime."
                        : "Required for text insertion"
                )
                
                if !hasPermission {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to enable:")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            OnboardingInstructionStep(number: 1, text: "Click 'Open System Settings' below")
                            OnboardingInstructionStep(number: 2, text: "Click the lock icon (bottom-left) and enter your password")
                            OnboardingInstructionStep(number: 3, text: "Click the '+' button and select Speakr from Applications")
                            OnboardingInstructionStep(number: 4, text: "Toggle Speakr ON in the list")
                            OnboardingInstructionStep(number: 5, text: "Return here and click 'Check Access'")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.secondary.opacity(0.05))
                    )
                }
                
                if permissionStatus == .denied {
                    Button("Open System Settings") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)
                }
                
                if permissionStatus != .granted {
                    Button {
                        checkAccessibilityPermission()
                    } label: {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Check Access")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isChecking)
                }
            }
            .frame(maxWidth: 400)
            
            Spacer()
        }
        .padding()
        .onAppear {
            checkAccessibilityPermission()
        }
    }
    
    private func checkAccessibilityPermission() {
        isChecking = true
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
        
        permissionStatus = accessibilityEnabled ? .granted : .denied
        hasPermission = accessibilityEnabled
        isChecking = false
    }
    
    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct OnboardingInstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(.secondary.opacity(0.15))
                )
            
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Permission Status Row

enum PermissionRowStatus {
    case pending
    case granted
    case denied
}

struct PermissionStatusRow: View {
    let status: PermissionRowStatus
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 24))
                .foregroundStyle(statusColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(statusColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(statusColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var iconName: String {
        switch status {
        case .pending:
            return "circle.dashed"
        case .granted:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .pending:
            return .orange
        case .granted:
            return .green
        case .denied:
            return .red
        }
    }
}

// MARK: - Download Model Step

/// Thread-safe bridge so a nonisolated WhisperKit progress callback can
/// write progress without capturing any @MainActor-isolated SwiftUI state.
final class ProgressBridge: @unchecked Sendable {
    var fraction: Double = 0
}

struct DownloadModelStep: View {
    @Binding var selectedModel: WhisperModelSize
    @Binding var isDownloaded: Bool
    @State private var downloadProgress: Double = 0
    @State private var isDownloading = false
    @State private var isComplete = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)

                Text("Model Ready!")
                    .font(.system(size: 24, weight: .semibold))

                Text("The \(selectedModel.displayName) model is downloaded and ready to use.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            } else {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)

                Text("Download AI Model")
                    .font(.system(size: 24, weight: .semibold))

                Text("Speakr transcribes locally using Whisper. Choose a model — it downloads once and stays on your Mac.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach([WhisperModelSize.tiny, .base, .small], id: \.self) { model in
                        OnboardingModelSelectionRow(
                            model: model,
                            isSelected: selectedModel == model,
                            action: { selectedModel = model }
                        )
                    }
                }
                .frame(maxWidth: 400)
                .disabled(isDownloading)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: 400)
                }

                if isDownloading {
                    VStack(spacing: 8) {
                        ProgressView(value: downloadProgress > 0 ? downloadProgress : nil)
                            .progressViewStyle(.linear)

                        Text(downloadProgress > 0
                             ? "Downloading… \(Int(downloadProgress * 100))%"
                             : "Preparing download…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 400)
                } else {
                    Button("Download \(selectedModel.displayName.components(separatedBy: " (").first ?? selectedModel.rawValue) Model") {
                        downloadModel()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                }
            }

            Spacer()
        }
        .padding()
    }

    private func downloadModel() {
        isDownloading = true
        errorMessage = nil
        downloadProgress = 0

        // ProgressBridge lets the nonisolated WhisperKit callback write progress
        // without capturing @MainActor state, satisfying Swift 6 concurrency rules.
        let bridge = ProgressBridge()
        let modelName = selectedModel.whisperKitName

        Task { @MainActor in
            do {
                let appSupport = FileManager.default.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask
                ).first!
                let modelDir = appSupport.appendingPathComponent("Speakr/Models", isDirectory: true)
                try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

                // Poll bridge for progress on the main actor while download runs in background
                let downloadTask = Task.detached {
                    try await WhisperKit.download(
                        variant: modelName,
                        downloadBase: modelDir,
                        progressCallback: { progress in
                            bridge.fraction = progress.fractionCompleted
                        }
                    )
                }

                // Refresh the progress bar every 250 ms
                let pollTask = Task { @MainActor in
                    while true {
                        try await Task.sleep(for: .milliseconds(250))
                        withAnimation { downloadProgress = bridge.fraction }
                    }
                }

                _ = try await downloadTask.value
                pollTask.cancel()
                downloadProgress = 1.0
                isDownloading = false
                isComplete = true
                isDownloaded = true
            } catch {
                isDownloading = false
                errorMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }
}

struct OnboardingModelSelectionRow: View {
    let model: WhisperModelSize
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.rawValue.capitalized)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    
                    Text(model.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Text(model.fileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Circle()
                            .stroke(.secondary.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Setup Complete Step

struct SetupCompleteStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Animated checkmark
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Circle()
                    .stroke(Color.green.opacity(0.2), lineWidth: 2)
                    .frame(width: 120, height: 120)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(.green)
            }
            
            VStack(spacing: 12) {
                Text("You're All Set!")
                    .font(.system(size: 28, weight: .semibold))
                
                Text("Speakr is ready to transcribe your voice.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                OnboardingTipRow(
                    icon: "keyboard",
                    text: "Press ⌃⌥Space to start recording"
                )
                
                OnboardingTipRow(
                    icon: "menubar.arrow.up.rectangle",
                    text: "Access more options from the menu bar icon"
                )
                
                OnboardingTipRow(
                    icon: "gear",
                    text: "Configure settings anytime from the menu"
                )
            }
            .frame(maxWidth: 340)
            .padding(.vertical)
            
            Spacer()
        }
        .padding()
    }
}

struct OnboardingTipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 14))
        }
    }
}

#Preview {
    OnboardingView()
}
