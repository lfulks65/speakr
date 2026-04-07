import SwiftUI

/// Custom menu bar icon view with animated status indication.
/// Shows a brief "charging" ring when recording starts.
struct MenuBarIconView: View {
    @Environment(MenuBarController.self) private var menuBarController

    @State private var isAnimating = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var chargeProgress: CGFloat = 0
    @State private var isCharging = false

    private let chargeDuration: Double = 1.2

    var body: some View {
        ZStack {
            if isCharging {
                // Charge-up ring around the icon
                Circle()
                    .trim(from: 0, to: chargeProgress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .orange.opacity(0.7), radius: 3)
            }

            Image(systemName: menuBarController.currentStatus.iconName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 18))
                .foregroundStyle(isCharging ? Color.orange : menuBarController.currentStatus.color)
                .contentTransition(.symbolEffect)
                .symbolEffect(.pulse, isActive: isActive)
        }
        .frame(width: 22, height: 22)
        .overlay(alignment: .topTrailing) {
            if case .recording = menuBarController.currentStatus, !isCharging {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .offset(x: 1, y: -1)
                    .phaseAnimator([false, true], trigger: isAnimating) { content, phase in
                        content.opacity(phase ? 1 : 0.3)
                    } animation: { _ in
                        .easeInOut(duration: 0.6)
                    }
            }
        }
        .onAppear { isAnimating = true }
        .onChange(of: menuBarController.currentStatus) { old, new in
            withAnimation(.spring(duration: 0.3)) { pulseScale = 1.2 }
            withAnimation(.spring(duration: 0.3).delay(0.1)) { pulseScale = 1.0 }

            if case .recording = new {
                if case .recording = old { } else { startCharge() }
            } else {
                isCharging = false
                chargeProgress = 0
            }
        }
        .scaleEffect(pulseScale)
    }

    private var isActive: Bool {
        switch menuBarController.currentStatus {
        case .recording, .processing: return true
        default: return false
        }
    }

    private func startCharge() {
        chargeProgress = 0
        isCharging = true
        withAnimation(.easeInOut(duration: chargeDuration)) {
            chargeProgress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + chargeDuration) {
            isCharging = false
        }
    }
}

/// Animated waveform view for recording indicator
struct WaveformView: View {
    let level: Float
    @State private var phase: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let barCount = 5
            let barWidth: CGFloat = 4
            let spacing: CGFloat = 2
            
            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: barWidth)
                        .frame(height: barHeight(for: index, totalHeight: height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: false)) {
                    phase = .pi * 2
                }
            }
        }
        .frame(height: 40)
    }
    
    private func barHeight(for index: Int, totalHeight: CGFloat) -> CGFloat {
        let normalizedLevel = CGFloat(max(0.1, min(1.0, level)))
        let baseHeight = totalHeight * 0.2
        let maxAdditional = totalHeight * 0.8 * normalizedLevel
        
        // Create wave effect
        let wave = sin(phase + Double(index) * 0.5) * 0.5 + 0.5
        let additional = maxAdditional * wave
        
        return baseHeight + additional
    }
}

/// Minimal audio level indicator for compact display
struct AudioLevelIndicator: View {
    let level: Float
    @State private var barHeights: [CGFloat] = Array(repeating: 0.1, count: 5)
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(for: index))
                    .frame(width: 3, height: barHeights[index] * 16)
            }
        }
        .frame(width: 25, height: 18)
        .onAppear {
            animateBars()
        }
        .onChange(of: level) { oldValue, newValue in
            animateBars()
        }
    }
    
    private func barColor(for index: Int) -> Color {
        let threshold = Float(index + 1) / 5.0
        if level >= threshold {
            return .blue
        }
        return Color.gray.opacity(0.3)
    }
    
    private func animateBars() {
        withAnimation(.easeOut(duration: 0.05)) {
            for i in barHeights.indices {
                let threshold = Float(i + 1) / 5.0
                barHeights[i] = level >= threshold ? 0.6 + CGFloat(i) * 0.1 : 0.1
            }
        }
    }
}

/// Recording indicator popover content.
/// Shows a "charging" ring for the first ~1.2s to signal users should
/// wait a beat before speaking, then transitions to the live waveform.
struct RecordingIndicatorView: View {
    @Environment(MenuBarController.self) private var menuBarController

    @State private var chargeProgress: CGFloat = 0
    @State private var chargeComplete = false
    private let chargeDuration: Double = 1.2

    var body: some View {
        VStack(spacing: 16) {
            if !chargeComplete {
                // ── Charge-up phase ──
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(Color.red.opacity(0.15), lineWidth: 5)
                            .frame(width: 64, height: 64)

                        Circle()
                            .trim(from: 0, to: chargeProgress)
                            .stroke(
                                AngularGradient(
                                    colors: [.yellow, .orange, .red],
                                    center: .center,
                                    startAngle: .degrees(0),
                                    endAngle: .degrees(360)
                                ),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .frame(width: 64, height: 64)
                            .rotationEffect(.degrees(-90))
                            .shadow(color: .red.opacity(0.5), radius: 8)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.red)
                            .scaleEffect(0.85 + 0.15 * chargeProgress)
                    }

                    Text("Warming up...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                // ── Live recording phase ──
                TimelineView(.periodic(from: menuBarController.recordingStartTime ?? .now, by: 1)) { ctx in
                    HStack {
                        Image(systemName: "record.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)

                        Text("Recording")
                            .font(.headline)

                        Spacer()

                        Text(formattedDuration(now: ctx.date))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                WaveformView(level: menuBarController.audioLevel)
                    .frame(height: 60)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.green, .yellow, .orange, .red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(menuBarController.audioLevel), height: 8)
                            .animation(.easeOut(duration: 0.05), value: menuBarController.audioLevel)
                    }
                }
                .frame(height: 8)

                Button {
                    Task { }
                } label: {
                    Label("Stop Recording", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear { startCharge() }
    }

    private func startCharge() {
        chargeProgress = 0
        chargeComplete = false
        withAnimation(.easeInOut(duration: chargeDuration)) {
            chargeProgress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + chargeDuration) {
            withAnimation(.easeInOut(duration: 0.3)) {
                chargeComplete = true
            }
        }
    }

    private func formattedDuration(now: Date) -> String {
        let elapsed = Int(now.timeIntervalSince(menuBarController.recordingStartTime ?? now))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Processing indicator view
struct ProcessingIndicatorView: View {
    @Environment(MenuBarController.self) private var menuBarController
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                ProgressView()
                    .scaleEffect(1.2)
                
                Text("Processing...")
                    .font(.headline)
                
                Spacer()
            }
            
            Divider()
            
            if case .processing(let progress) = menuBarController.currentStatus {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Transcribing audio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
            }
        }
        .padding()
        .frame(width: 280)
    }
}

#Preview {
    MenuBarIconView()
        .environment(MenuBarController())
}

#Preview("Waveform") {
    WaveformView(level: 0.5)
        .frame(width: 200, height: 60)
        .padding()
}

#Preview("Recording Indicator") {
    RecordingIndicatorView()
        .environment(MenuBarController())
}

#Preview("Processing Indicator") {
    ProcessingIndicatorView()
        .environment(MenuBarController())
}
