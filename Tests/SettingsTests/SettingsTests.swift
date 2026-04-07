import XCTest
@testable import Settings

@available(macOS 14.0, *)
final class SettingsTests: XCTestCase {
    
    var storage: UserDefaultsStorage!
    var store: SettingsStore!
    
    override func setUp() {
        super.setUp()
        storage = UserDefaultsStorage(suiteName: "TestSettings")
        store = SettingsStore(storage: storage)
    }
    
    override func tearDown() {
        // Clear test settings
        UserDefaults(suiteName: "TestSettings")?.removePersistentDomain(forName: "TestSettings")
        store = nil
        storage = nil
        super.tearDown()
    }
    
    func testDefaultSettings() {
        let defaults = AppSettings.default
        XCTAssertEqual(defaults.modelSize, .base)
        XCTAssertEqual(defaults.transcriptionLanguage, .auto)
        XCTAssertTrue(defaults.autoCopyToClipboard)
        XCTAssertFalse(defaults.autoPaste)
    }
    
    func testModelSizeCases() {
        let sizes = ModelSize.allCases
        XCTAssertEqual(sizes.count, 5)
        
        // Test file size descriptions
        XCTAssertTrue(ModelSize.tiny.fileSize.contains("75 MB"))
        XCTAssertTrue(ModelSize.largeV3.fileSize.contains("2.9 GB"))
    }
    
    func testLanguageCases() {
        let languages = TranscriptionLanguage.allCases
        XCTAssertTrue(languages.count > 5)
        
        XCTAssertEqual(TranscriptionLanguage.english.displayName, "English")
        XCTAssertEqual(TranscriptionLanguage.auto.displayName, "Auto-detect")
    }
    
    func testSettingsStorage() throws {
        let original = AppSettings(
            transcriptionLanguage: .english,
            modelSize: .small,
            autoCopyToClipboard: false
        )
        
        try storage.save(original, forKey: "test_settings")
        let loaded: AppSettings? = try storage.load(forKey: "test_settings", as: AppSettings.self)
        
        XCTAssertEqual(loaded?.modelSize, .small)
        XCTAssertEqual(loaded?.transcriptionLanguage, .english)
        XCTAssertEqual(loaded?.autoCopyToClipboard, false)
    }
    
    func testSettingsEquality() {
        let settings1 = AppSettings()
        let settings2 = AppSettings()
        let settings3 = AppSettings(modelSize: .tiny)
        
        XCTAssertEqual(settings1, settings2)
        XCTAssertNotEqual(settings1, settings3)
    }
    
    func testResetToDefaults() {
        store.settings.modelSize = .largeV3
        store.settings.transcriptionLanguage = .spanish
        
        store.resetToDefaults()
        
        XCTAssertEqual(store.settings.modelSize, .base)
        XCTAssertEqual(store.settings.transcriptionLanguage, .auto)
    }
}
