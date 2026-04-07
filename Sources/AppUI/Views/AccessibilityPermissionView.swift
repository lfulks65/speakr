import SwiftUI
import AVFoundation

/// Standalone accessibility permission prompt that can be shown from menu or at startup
struct AccessibilityPermissionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasPermission = false
    @State private var isChecking = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "keyboard.badge.eye.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
            
            VStack(spacing: 12) {
                Text("Accessibility Access Required")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Speakr needs accessibility permission to insert transcribed text into other applications.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                // Current status
                HStack {
                    Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(hasPermission ? .green : .orange)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hasPermission ? "Access Granted" : "Access Not Granted")
                            .font(.headline)
                        
                        Text(hasPermission 
                            ? "You're all set! Speakr can now type text into other applications."
                            : "Speakr needs your permission to type transcribed text automatically.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hasPermission ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(hasPermission ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
                
                if !hasPermission {
                    // Instructions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to enable:")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            PermissionInstructionStep(
                                number: 1,
                                text: "Click 'Open System Settings' below"
                            )
                            PermissionInstructionStep(
                                number: 2,
                                text: "Click the lock icon (bottom-left) and enter your password"
                            )
                            PermissionInstructionStep(
                                number: 3,
                                text: "Click the '+' button and select Speakr from Applications"
                            )
                            PermissionInstructionStep(
                                number: 4,
                                text: "Toggle Speakr ON in the list"
                            )
                            PermissionInstructionStep(
                                number: 5,
                                text: "Return here and click 'Check Access'")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.secondary.opacity(0.05))
                    )
                }
            }
            .frame(maxWidth: 450)
            
            HStack(spacing: 12) {
                if hasPermission {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Open System Settings") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        checkPermission()
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
                    
                    Button("Later") {
                        dismiss()
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.top)
            
            Spacer()
        }
        .padding(40)
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            checkPermission()
        }
    }
    
    private func checkPermission() {
        isChecking = true
        // prompt: true → shows the system "allow accessibility" dialog and adds the
        // app to the Accessibility list if it isn't there yet.
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
        hasPermission = accessibilityEnabled
        isChecking = false
    }
    
    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct PermissionInstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(.secondary.opacity(0.15))
                )
            
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A compact inline permission prompt for use within the menu bar dropdown
struct CompactAccessibilityPrompt: View {
    @State private var hasPermission = false
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: hasPermission ? "checkmark.circle.fill" : "keyboard.badge.eye.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(hasPermission ? .green : .orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility Access")
                            .font(.system(size: 13, weight: .medium))
                        
                        Text(hasPermission ? "Granted" : "Required for text insertion")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hasPermission ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
            )
            
            if isExpanded && !hasPermission {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speakr needs accessibility permission to automatically type transcribed text into other applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Button("Open Settings") {
                            openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("Check") {
                            checkPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
    }
    
    private func checkPermission() {
        hasPermission = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Microphone permission prompt view
struct MicrophonePermissionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasPermission = false
    @State private var isChecking = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
            
            VStack(spacing: 12) {
                Text("Microphone Access Required")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Speakr needs microphone access to record and transcribe your voice.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                // Current status
                HStack {
                    Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(hasPermission ? .green : .orange)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hasPermission ? "Access Granted" : "Access Not Granted")
                            .font(.headline)
                        
                        Text(hasPermission 
                            ? "You're all set! Speakr can now access your microphone."
                            : "Without microphone access, Speakr cannot record audio.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hasPermission ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(hasPermission ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .frame(maxWidth: 450)
            
            HStack(spacing: 12) {
                if hasPermission {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Open System Settings") {
                        openMicrophoneSettings()
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        requestPermission()
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
            .padding(.top)
            
            Spacer()
        }
        .padding(40)
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            checkCurrentPermission()
        }
    }
    
    private func checkCurrentPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasPermission = true
        case .denied, .restricted:
            hasPermission = false
        case .notDetermined:
            hasPermission = false
        @unknown default:
            hasPermission = false
        }
    }
    
    private func requestPermission() {
        isChecking = true
        
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                isChecking = false
                hasPermission = granted
            }
        }
    }
    
    private func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}

#Preview("Accessibility Permission") {
    AccessibilityPermissionView()
}

#Preview("Compact Accessibility Prompt") {
    CompactAccessibilityPrompt()
        .frame(width: 260)
        .padding()
}

#Preview("Microphone Permission") {
    MicrophonePermissionView()
}
