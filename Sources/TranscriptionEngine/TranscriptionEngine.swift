import Foundation
import AudioCapture
@preconcurrency import WhisperKit

// MARK: - Errors

public enum TranscriptionError: Error, CustomStringConvertible {
    case noModelLoaded
    case modelLoadFailed(String)
    case transcriptionFailed(String)
    case invalidAudioData
    case processingFailed(String)

    public var description: String {
        switch self {
        case .noModelLoaded:
            return "No transcription model loaded. Please download a model first."
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .invalidAudioData:
            return "Invalid or missing audio file."
        case .processingFailed(let reason):
            return "Processing failed: \(reason)"
        }
    }
}

// MARK: - Our result types (distinct from WhisperKit's same-named types)

public struct TranscriptionSegment: Sendable, Identifiable {
    public let id = UUID()
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float

    public init(text: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}

public struct TranscriptionResult: Sendable {
    public let text: String
    public let segments: [TranscriptionSegment]
    public let duration: TimeInterval
    public let processingTime: TimeInterval
    public let language: String?

    public init(text: String, segments: [TranscriptionSegment], duration: TimeInterval,
                processingTime: TimeInterval, language: String? = nil) {
        self.text = text
        self.segments = segments
        self.duration = duration
        self.processingTime = processingTime
        self.language = language
    }
}

// MARK: - Model sizes

public enum WhisperModelSize: String, CaseIterable, Codable, Hashable, Sendable {
    case tiny
    case base
    case small
    case medium
    case largeV3 = "large-v3"

    /// WhisperKit model variant name on Hugging Face (argmaxinc/whisperkit-coreml)
    public var whisperKitName: String {
        switch self {
        case .tiny:    return "openai_whisper-tiny"
        case .base:    return "openai_whisper-base"
        case .small:   return "openai_whisper-small"
        case .medium:  return "openai_whisper-medium"
        case .largeV3: return "openai_whisper-large-v3_turbo"
        }
    }

    public var displayName: String {
        switch self {
        case .tiny:    return "Tiny (fastest, least accurate)"
        case .base:    return "Base (fast, good accuracy)"
        case .small:   return "Small (balanced)"
        case .medium:  return "Medium (slower, better accuracy)"
        case .largeV3: return "Large v3 Turbo (best accuracy)"
        }
    }

    public var fileSize: String {
        switch self {
        case .tiny:    return "~150 MB"
        case .base:    return "~290 MB"
        case .small:   return "~590 MB"
        case .medium:  return "~1.5 GB"
        case .largeV3: return "~1.6 GB"
        }
    }
}

// MARK: - Protocol

@MainActor
public protocol TranscriptionEngineProtocol: AnyObject {
    var isTranscribing: Bool { get }
    var loadedModel: WhisperModelSize? { get }
    /// 0…1 during model download; 1.0 when ready
    var downloadProgress: Double { get }

    func loadModel(_ size: WhisperModelSize) async throws
    func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult
    func transcribeStream(audioURL: URL, language: String?) -> AsyncThrowingStream<String, Error>
    func cancelTranscription()
}

// MARK: - Engine

@available(macOS 14.0, *)
@Observable
public final class TranscriptionEngine: TranscriptionEngineProtocol {

    // MARK: - Public state

    public private(set) var isTranscribing: Bool = false
    public private(set) var loadedModel: WhisperModelSize?
    public private(set) var downloadProgress: Double = 0.0

    // MARK: - Private

    // WhisperKit is not Sendable; keep it nonisolated(unsafe) and only touch it
    // from async functions called on @MainActor (AppState / TranscriptionEngine).
    nonisolated(unsafe) private var whisperKit: WhisperKit?
    private var cancellationRequested = false
    private var transcriptionTask: Task<Void, Never>?

    // MARK: - Init

    public init() {}

    // MARK: - Model loading

    /// Downloads (if needed) and loads the specified Whisper model.
    /// WhisperKit caches models in `~/Library/Application Support/Speakr/Models/`.
    public func loadModel(_ size: WhisperModelSize) async throws {
        guard !isTranscribing else {
            throw TranscriptionError.processingFailed("Cannot load model while transcribing")
        }

        NSLog("▶ TranscriptionEngine.loadModel(\(size.rawValue))")
        downloadProgress = 0.0
        let modelDir = modelsDirectory()

        do {
            // Step 1: download if not already cached (no progress callback here;
            // onboarding's DownloadModelStep handles that separately).
            let modelFolder = try await WhisperKit.download(
                variant: size.whisperKitName,
                downloadBase: modelDir
            )

            // Step 2: initialise from the local folder (no network needed)
            let kit = try await WhisperKit(
                modelFolder: modelFolder.path,
                verbose: false,
                logLevel: .none,
                prewarm: false,
                load: true,
                download: false
            )

            whisperKit = kit
            loadedModel = size
            downloadProgress = 1.0
            NSLog("▶ TranscriptionEngine.loadModel(\(size.rawValue)) complete")
        } catch {
            NSLog("[ERROR] TranscriptionEngine.loadModel: \(error)")
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }
    }

    // MARK: - Transcription

    public func transcribe(audioURL: URL, language: String? = nil) async throws -> TranscriptionResult {
        guard let kit = whisperKit else {
            throw TranscriptionError.noModelLoaded
        }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.invalidAudioData
        }
        guard !isTranscribing else {
            throw TranscriptionError.processingFailed("Already transcribing")
        }

        isTranscribing = true
        cancellationRequested = false
        let startTime = CFAbsoluteTimeGetCurrent()
        NSLog("▶ TranscriptionEngine.transcribe() — \(audioURL.lastPathComponent)")

        defer { isTranscribing = false }

        do {
            var options = DecodingOptions()
            options.task = .transcribe
            if let lang = language, !lang.isEmpty, lang != "auto" {
                options.language = lang
            }
            options.usePrefillPrompt = true

            // `transcribe` returns WhisperKit's own [TranscriptionResult] class.
            // We intentionally avoid annotating the type to sidestep the name
            // collision with our own TranscriptionResult struct above.
            let kitResults = try await kit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options
            )

            if cancellationRequested {
                throw TranscriptionError.transcriptionFailed("Transcription cancelled")
            }

            // Combine text from all chunks (WhisperKit may split long audio)
            let rawText = kitResults.map { $0.text }.joined(separator: " ")
            let fullText = rawText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            // Convert WhisperKit segments → our TranscriptionSegment
            var ourSegments: [TranscriptionSegment] = []
            for kitResult in kitResults {
                for seg in kitResult.segments {
                    let conf = Float(exp(Double(seg.avgLogprob)))
                    ourSegments.append(TranscriptionSegment(
                        text: seg.text,
                        startTime: TimeInterval(seg.start),
                        endTime: TimeInterval(seg.end),
                        confidence: conf
                    ))
                }
            }

            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            let detectedLanguage = kitResults.first?.language

            NSLog("▶ done in \(String(format: "%.2f", processingTime))s — \"\(fullText.prefix(80))\"")

            return TranscriptionResult(
                text: fullText,
                segments: ourSegments,
                duration: processingTime,
                processingTime: processingTime,
                language: detectedLanguage ?? language
            )
        } catch let e as TranscriptionError {
            throw e
        } catch {
            NSLog("[ERROR] TranscriptionEngine.transcribe: \(error)")
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    public func transcribeStream(audioURL: URL, language: String?) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        transcriptionTask = Task {
            do {
                let result = try await transcribe(audioURL: audioURL, language: language)
                continuation.yield(result.text)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return stream
    }

    public func cancelTranscription() {
        cancellationRequested = true
        transcriptionTask?.cancel()
        isTranscribing = false
    }

    // MARK: - Helpers

    private func modelsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Speakr/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
