import Foundation
import Combine

/// Errors that can occur with settings
public enum SettingsError: Error {
    case saveFailed(Error)
    case loadFailed(Error)
    case encodingFailed
    case decodingFailed
}

/// Available transcription languages
public enum TranscriptionLanguage: String, CaseIterable, Codable, Sendable {
    case auto = "auto"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case japanese = "ja"
    case chinese = "zh"
    case korean = "ko"
    case russian = "ru"
    
    public var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .dutch: return "Dutch"
        case .japanese: return "Japanese"
        case .chinese: return "Chinese"
        case .korean: return "Korean"
        case .russian: return "Russian"
        }
    }
}

/// Available Whisper model sizes
public enum ModelSize: String, CaseIterable, Codable, Sendable {
    case tiny
    case base
    case small
    case medium
    case largeV3 = "large-v3"
    
    public var displayName: String {
        switch self {
        case .tiny:
            return "Tiny (fastest, least accurate)"
        case .base:
            return "Base (fast, good accuracy)"
        case .small:
            return "Small (balanced)"
        case .medium:
            return "Medium (slower, better accuracy)"
        case .largeV3:
            return "Large v3 (slowest, best accuracy)"
        }
    }
    
    public var fileSize: String {
        switch self {
        case .tiny:
            return "~75 MB"
        case .base:
            return "~142 MB"
        case .small:
            return "~466 MB"
        case .medium:
            return "~1.5 GB"
        case .largeV3:
            return "~2.9 GB"
        }
    }
}

/// Application settings model
public struct AppSettings: Codable, Equatable, Sendable {
    public var transcriptionLanguage: TranscriptionLanguage
    public var modelSize: ModelSize
    public var autoCopyToClipboard: Bool
    public var autoPaste: Bool
    public var autoPunctuation: Bool
    public var showMenuBarIcon: Bool
    public var launchAtLogin: Bool
    public var audioRetentionDays: Int
    public var enableSoundEffects: Bool
    public var audioSensitivity: Double

    public init(
        transcriptionLanguage: TranscriptionLanguage = .auto,
        modelSize: ModelSize = .base,
        autoCopyToClipboard: Bool = true,
        autoPaste: Bool = true,
        autoPunctuation: Bool = true,
        showMenuBarIcon: Bool = true,
        launchAtLogin: Bool = false,
        audioRetentionDays: Int = 7,
        enableSoundEffects: Bool = true,
        audioSensitivity: Double = 0.5
    ) {
        self.transcriptionLanguage = transcriptionLanguage
        self.modelSize = modelSize
        self.autoCopyToClipboard = autoCopyToClipboard
        self.autoPaste = autoPaste
        self.autoPunctuation = autoPunctuation
        self.showMenuBarIcon = showMenuBarIcon
        self.launchAtLogin = launchAtLogin
        self.audioRetentionDays = audioRetentionDays
        self.enableSoundEffects = enableSoundEffects
        self.audioSensitivity = audioSensitivity
    }
    
    public static let `default` = AppSettings()
}

/// Protocol for settings storage backend
public protocol SettingsStorage: Sendable {
    func save<T: Encodable>(_ value: T, forKey key: String) throws
    func load<T: Decodable>(forKey key: String, as type: T.Type) throws -> T?
    func delete(forKey key: String)
}

/// UserDefaults-based storage implementation
public final class UserDefaultsStorage: SettingsStorage {
    // UserDefaults is safe to use from multiple contexts despite lacking Sendable; we only write from SettingsStore
    nonisolated(unsafe) private let defaults: UserDefaults
    
    public init(suiteName: String? = nil) {
        if let suiteName = suiteName {
            self.defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        } else {
            self.defaults = UserDefaults.standard
        }
    }
    
    public func save<T: Encodable>(_ value: T, forKey key: String) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        defaults.set(data, forKey: key)
    }
    
    public func load<T: Decodable>(forKey key: String, as type: T.Type) throws -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
    
    public func delete(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

/// Observable settings store for the application
@available(macOS 14.0, *)
@Observable
public final class SettingsStore: @unchecked Sendable {

    // MARK: - Public Properties

    public var settings: AppSettings {
        get { _currentSettings }
        set {
            _currentSettings = newValue
            Task { await saveSettings() }
        }
    }

    // Shortcut hotkey stored separately for quick access by HotkeyService
    public var shortcutHotkey: Hotkey? {
        get {
            guard let data = try? storage.load(forKey: Keys.shortcutHotkey, as: Data.self) else { return nil }
            return try? JSONDecoder().decode(Hotkey.self, from: data)
        }
        set {
            if let newValue,
               let data = try? JSONEncoder().encode(newValue) {
                try? storage.save(data, forKey: Keys.shortcutHotkey)
            } else {
                storage.delete(forKey: Keys.shortcutHotkey)
            }
        }
    }

    // MARK: - Private Properties

    private let storage: any SettingsStorage
    private let settingsKey = "app_settings"

    private struct Keys {
        static let shortcutHotkey = "shortcut_hotkey"
    }

    // Access is always from main thread via @Observable; nonisolated(unsafe) satisfies Sendable
    nonisolated(unsafe) private var _currentSettings: AppSettings = .default

    // MARK: - Initialization

    public init(storage: any SettingsStorage = UserDefaultsStorage()) {
        self.storage = storage
        _currentSettings = (try? storage.load(forKey: settingsKey, as: AppSettings.self)) ?? .default
    }

    // MARK: - Public Methods

    public func resetToDefaults() {
        settings = .default
    }

    public func exportSettings(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(settings)
        try data.write(to: url)
    }

    public func importSettings(from url: URL) throws {
        let data = try Data(contentsOf: url)
        settings = try JSONDecoder().decode(AppSettings.self, from: data)
    }

    // MARK: - Private Methods

    private func saveSettings() async {
        do {
            try storage.save(_currentSettings, forKey: settingsKey)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }
}

// Hotkey struct shared between Settings and HotkeyService modules
public struct Hotkey: Codable, Equatable, Hashable, Sendable {
    public let keyCode: Int
    public let modifiers: UInt
    
    public init(keyCode: Int, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    
    public static let `default` = Hotkey(keyCode: 49, modifiers: 0x0800) // ⌥Space (optionKey = 2048)
}

// MARK: - Extensions for Codable support

extension ModelSize {
    public var whisperModelSize: String {
        switch self {
        case .tiny: return "tiny"
        case .base: return "base"
        case .small: return "small"
        case .medium: return "medium"
        case .largeV3: return "large-v3"
        }
    }
}
