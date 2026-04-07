import XCTest
@testable import HotkeyService
@testable import Settings

@available(macOS 14.0, *)
final class HotkeyServiceTests: XCTestCase {
    
    var service: HotkeyService!
    
    override func setUp() {
        super.setUp()
        service = HotkeyService()
    }
    
    override func tearDown() {
        service.unregisterHotkey()
        service = nil
        super.tearDown()
    }
    
    func testErrorDescription() {
        let permissionError = HotkeyError.accessibilityPermissionDenied
        XCTAssertTrue(permissionError.description.contains("Accessibility"))
        
        let registrationError = HotkeyError.registrationFailed("reason")
        XCTAssertTrue(registrationError.description.contains("reason"))
    }
    
    func testHotkeyEquality() {
        let hotkey1 = Hotkey(keyCode: 49, modifiers: 0x0008)
        let hotkey2 = Hotkey(keyCode: 49, modifiers: 0x0008)
        let hotkey3 = Hotkey(keyCode: 50, modifiers: 0x0008)
        
        XCTAssertEqual(hotkey1, hotkey2)
        XCTAssertNotEqual(hotkey1, hotkey3)
    }
    
    func testHotkeyDefault() {
        let defaultHotkey = Hotkey.default
        XCTAssertEqual(defaultHotkey.keyCode, 49)  // Space key
        XCTAssertEqual(defaultHotkey.modifiers, 0x0008)  // Option key
    }
}
