import SwiftUI
import Settings
import TranscriptionEngine

/// Settings window content with tabs
struct SettingsWindowView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("showMenuInMenuBar") private var showMenuInMenuBar = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AudioSettingsTab()
                .tabItem {
                    Label("Audio", systemImage: "mic")
                }
            
            ModelSettingsTab()
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }
            
            ProfileSettingsTab()
                .tabItem {
                    Label("Profiles", systemImage: "person.2")
                }
            
            ShortcutsSettingsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(minWidth: 600, minHeight: 450)
        .padding()
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState
    @AppStorage("showMenuInMenuBar") private var showMenuInMenuBar = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Menu Bar") {
                Toggle("Show in menu bar", isOn: $showMenuInMenuBar)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }

            Section("Text Output") {
                Toggle(
                    "Auto-paste into active window",
                    isOn: Binding(
                        get: { appState.settingsStore.settings.autoPaste },
                        set: { appState.settingsStore.settings.autoPaste = $0 }
                    )
                )
                Text("Inserts transcribed text directly where your cursor is. Requires Accessibility permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    "Copy to clipboard",
                    isOn: Binding(
                        get: { appState.settingsStore.settings.autoCopyToClipboard },
                        set: { appState.settingsStore.settings.autoCopyToClipboard = $0 }
                    )
                )
                Text("Always copies text to the clipboard as a backup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Audio Settings Tab

struct AudioSettingsTab: View {
    @State private var inputGain: Double = 1.0
    @State private var inputLevel: Float = 0.0
    @State private var noiseReduction: Bool = true
    
    var body: some View {
        Form {
            Section("Input Level") {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.green, .yellow, .orange, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * CGFloat(inputLevel))
                        }
                    }
                    .frame(height: 20)
                    
                    Slider(value: $inputGain, in: 0.5...2.0, step: 0.1) {
                        Text("Input Gain")
                    }
                }
            }
            
            Section("Audio Quality") {
                Toggle("Noise reduction", isOn: $noiseReduction)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Model Settings Tab

struct ModelSettingsTab: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        Form {
            Section("Current Model") {
                if let loadedModel = appState.transcriptionEngine.loadedModel {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        
                        VStack(alignment: .leading) {
                            Text(loadedModel.displayName)
                                .font(.headline)
                            Text(loadedModel.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Label("No model loaded", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            
            Section("Available Models") {
                ForEach(WhisperModelSize.allCases, id: \.self) { model in
                    SettingsModelRow(
                        model: model,
                        isLoaded: appState.transcriptionEngine.loadedModel == model
                    )
                }
            }
            
            Section("Performance") {
                Toggle("Use GPU acceleration", isOn: .constant(true))
                    .disabled(true)
                
                Button("Unload model (free memory)") {
                    // Actual unload implementation
                }
                .disabled(!appState.transcriptionEngine.isTranscribing)
            }
        }
        .formStyle(.grouped)
    }
}

struct SettingsModelRow: View {
    let model: WhisperModelSize
    let isLoaded: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.rawValue.capitalized)
                
                Text(model.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isLoaded {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            } else {
                Text("Load")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Profile Settings Tab

struct ProfileSettingsTab: View {
    @State private var selectedProfile: Profile = .defaultProfile
    
    var profiles: [Profile] = [.defaultProfile, .workProfile, .personalProfile]
    
    var body: some View {
        HStack {
            // Profile List
            VStack(alignment: .leading, spacing: 0) {
                List {
                    ForEach(profiles) { profile in
                        ProfileSettingsRow(profile: profile, isSelected: selectedProfile == profile)
                            .onTapGesture {
                                selectedProfile = profile
                            }
                    }
                }
                .listStyle(.plain)
                
                Divider()
                
                HStack {
                    Button {
                        // Add profile
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    
                    Spacer()
                    
                    Button {
                        // Delete profile
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(profiles.count <= 1)
                }
                .padding(8)
            }
            .frame(width: 200)
            
            Divider()
            
            // Profile Editor
            VStack(alignment: .leading, spacing: 16) {
                Form {
                    Section("Profile Info") {
                        TextField("Name:", text: .constant(selectedProfile.name))
                        
                        Picker("Color:", selection: .constant(selectedProfile.color)) {
                            ForEach(ProfileColor.allCases, id: \.self) { color in
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .frame(width: 16, height: 16)
                                    .tag(color)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    Section("Transcription Settings") {
                        Picker("Language:", selection: .constant(selectedProfile.settings.language)) {
                            Text("Auto-detect").tag("auto")
                            Text("English").tag("en")
                            Text("Spanish").tag("es")
                            Text("French").tag("fr")
                        }
                        .pickerStyle(.menu)
                        
                        Toggle("Auto-punctuation", isOn: .constant(selectedProfile.settings.autoPunctuation))
                        
                        Picker("Model:", selection: .constant(selectedProfile.settings.model)) {
                            ForEach(WhisperModelSize.allCases, id: \.self) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    Section {
                        Button("Save Changes") {
                            // Save profile changes
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .formStyle(.grouped)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

struct ProfileSettingsRow: View {
    let profile: Profile
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: profile.icon)
                .foregroundStyle(profile.color.swiftUIColor)
                .frame(width: 24)
            
            Text(profile.name)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }
}

// MARK: - Shortcuts Settings Tab

struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            Section("Recording Shortcuts") {
                ShortcutSettingsRow(title: "Toggle Recording", shortcut: "⌃⌥Space")
                ShortcutSettingsRow(title: "Push-to-Talk", shortcut: "⌃Space")
            }
            
            Section("Tips") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb")
                            .foregroundStyle(.yellow)
                        Text("Avoid shortcuts that conflict with common applications like ⌘C (copy) or ⌘V (paste).")
                    }
                    
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text("Accessibility permission is required for global shortcuts to work when Speakr is not in focus.")
                    }
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutSettingsRow: View {
    let title: String
    let shortcut: String
    
    var body: some View {
        HStack {
            Text(title)
            
            Spacer()
            
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
        }
        .padding(.vertical, 4)
    }
}
