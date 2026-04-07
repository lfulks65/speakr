import AVFoundation
import Foundation


/// Errors that can occur during audio capture
public enum AudioCaptureError: Error, CustomStringConvertible {
    case permissionDenied
    case noInputDevice
    case setupFailed(String)
    case recordingFailed(String)
    case invalidFormat
    
    public var description: String {
        switch self {
        case .permissionDenied:
            return "Microphone access denied. Please grant permission in System Settings."
        case .noInputDevice:
            return "No audio input device found."
        case .setupFailed(let reason):
            return "Audio setup failed: \(reason)"
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)"
        case .invalidFormat:
            return "Invalid audio format configuration."
        }
    }
}

/// Audio level information for UI visualization
public struct AudioLevel: Sendable {
    public let average: Float
    public let peak: Float
    
    public init(average: Float, peak: Float) {
        self.average = average
        self.peak = peak
    }
}

/// Protocol defining the audio capture interface
public protocol AudioCaptureProtocol: AnyObject {
    /// Published audio levels for visualization
    var audioLevels: AsyncStream<AudioLevel> { get }
    
    /// Current recording state
    var isRecording: Bool { get }
    
    /// Request microphone permission
    func requestPermission() async -> Bool
    
    /// Start recording audio
    /// - Returns: URL to the recorded audio file
    /// - Throws: AudioCaptureError if recording fails
    func startRecording() async throws -> URL
    
    /// Stop recording audio
    /// - Returns: URL to the final recorded audio file
    func stopRecording() async -> URL?
}

/// Default implementation of audio capture using AVFoundation
@available(macOS 14.0, *)
public actor AudioCapture: @preconcurrency AudioCaptureProtocol {

    // MARK: - Public Properties

    public var audioLevels: AsyncStream<AudioLevel> {
        AsyncStream { continuation in
            self.levelsContinuation = continuation
        }
    }

    public private(set) var isRecording: Bool = false
    
    // MARK: - Private Properties

    // Lazily initialized so the main thread is never blocked at startup
    private var _audioEngine: AVAudioEngine?
    private var audioEngine: AVAudioEngine {
        if let e = _audioEngine { return e }
        NSLog("  AVAudioEngine() init begin (first use)...")
        let e = AVAudioEngine()
        _audioEngine = e
        NSLog("  AVAudioEngine() init done")
        return e
    }

    private var audioRecorder: AVAudioRecorder?
    private var recordedFileURL: URL?
    private var levelsContinuation: AsyncStream<AudioLevel>.Continuation?
    
    // Settings for audio recording (16kHz mono for Whisper)
    private let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]
    
    // MARK: - Initialization
    
    public init() {
        NSLog("▶ AudioCapture.init() — AVAudioEngine deferred to first use")
    }
    
    // MARK: - Public Methods

    /// Pre-warms the audio subsystem. Called after permissions are granted.
    public func warmUp() {
        _ = audioEngine.inputNode
        NSLog("▶ AudioCapture.warmUp() — engine input node touched")
    }

    public func requestPermission() async -> Bool {
        NSLog("▶ requestPermission() begin")
        let result = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        NSLog("▶ requestPermission() → \(result)")
        return result
    }
    
    public func startRecording() async throws -> URL {
        NSLog("▶ startRecording() begin")
        let status = AVAudioApplication.shared.recordPermission
        
        switch status {
        case .denied:
            throw AudioCaptureError.permissionDenied
        case .undetermined:
            let granted = await requestPermission()
            guard granted else {
                throw AudioCaptureError.permissionDenied
            }
        case .granted:
            break
        @unknown default:
            throw AudioCaptureError.permissionDenied
        }
        
        NSLog("  checking for input device (audioEngine.inputNode)...")
        guard audioEngine.inputNode.inputFormat(forBus: 0).sampleRate > 0 else {
            NSLog("[ERROR] " + "  no input device found")
            throw AudioCaptureError.noInputDevice
        }
        NSLog("  input device OK")
        
        // Create temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "recording_\(UUID().uuidString).m4a"
        let fileURL = tempDir.appendingPathComponent(fileName)
        recordedFileURL = fileURL
        
        do {
            NSLog("  creating AVAudioRecorder at \(fileURL.lastPathComponent)...")
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: recordingSettings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            NSLog("  AVAudioRecorder ready, calling record()...")
            guard audioRecorder?.record() == true else {
                throw AudioCaptureError.recordingFailed("Failed to start recording")
            }
            isRecording = true
            NSLog("▶ startRecording() success — file: \(fileURL.lastPathComponent)")
            startLevelMonitoring()
            return fileURL
        } catch {
            NSLog("[ERROR] " + "▶ startRecording() error: \(error)")
            throw AudioCaptureError.setupFailed(error.localizedDescription)
        }
    }
    
    public func stopRecording() async -> URL? {
        guard isRecording else { return nil }
        
        audioRecorder?.stop()
        isRecording = false
        
        levelsContinuation?.finish()
        levelsContinuation = nil
        
        // Return the recorded file URL
        return recordedFileURL
    }
    
    // MARK: - Private Methods
    
    private func startLevelMonitoring() {
        Task {
            while isRecording {
                audioRecorder?.updateMeters()
                
                let averagePower = audioRecorder?.averagePower(forChannel: 0) ?? -160
                let peakPower = audioRecorder?.peakPower(forChannel: 0) ?? -160
                
                // Convert from dB to linear scale (0.0 - 1.0)
                let averageLevel = pow(10, averagePower / 20)
                let peakLevel = pow(10, peakPower / 20)
                
                let level = AudioLevel(average: Float(averageLevel), peak: Float(peakLevel))
                levelsContinuation?.yield(level)
                
                // Update every 50ms
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
