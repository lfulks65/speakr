import SwiftUI

/// Main application window content
struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    
    @State private var showingOnboarding = false
    @State private var selectedNavigation: NavigationItem = .history
    
    var body: some View {
        NavigationSplitView {
            Sidebar(selectedItem: $selectedNavigation)
        } detail: {
            detailView
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                showingOnboarding = false
            }
            .frame(minWidth: 560, minHeight: 480)
        }
        .onAppear {
            checkFirstLaunch()
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
        switch selectedNavigation {
        case .history:
            HistoryView()
                .environment(appState)
        case .settings:
            SettingsWindowView()
                .environment(appState)
        }
    }
    
    private func checkFirstLaunch() {
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showingOnboarding = true
        }
    }
}

// MARK: - Navigation

enum NavigationItem: String, CaseIterable, Identifiable {
    case history = "History"
    case settings = "Settings"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .history:
            return "clock"
        case .settings:
            return "gear"
        }
    }
}

struct Sidebar: View {
    @Binding var selectedItem: NavigationItem
    
    var body: some View {
        List(NavigationItem.allCases, selection: $selectedItem) { item in
            Label(item.rawValue, systemImage: item.icon)
        }
        .navigationTitle("Speakr")
        .listStyle(.sidebar)
    }
}

// MARK: - History View

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        VStack(spacing: 16) {
            if appState.lastTranscription == nil {
                emptyState
            } else {
                transcriptionContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Transcription History")
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "text.bubble")
                .font(.system(size: 64))
                .foregroundStyle(.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("No Transcriptions Yet")
                    .font(.title3)
                    .fontWeight(.medium)
                
                Text("Press ⌃⌥Space to start recording and transcribe your voice.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var transcriptionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let transcription = appState.lastTranscription {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Last Transcription")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button {
                                copyToClipboard(transcription)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                        }
                        
                        Text(transcription)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.secondary.opacity(0.1))
                    )
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
