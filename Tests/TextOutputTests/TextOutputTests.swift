import XCTest
@testable import TextOutput

@available(macOS 14.0, *)
final class TextOutputTests: XCTestCase {
    
    var output: TextOutput!
    var service: TextOutputService!
    var clipboardManager: ClipboardManager!
    
    override func setUp() {
        super.setUp()
        service = TextOutputService()
        output = TextOutput(service: service)
        clipboardManager = ClipboardManager.shared
        clipboardManager.clearSaved()
    }
    
    override func tearDown() {
        output = nil
        service = nil
        super.tearDown()
    }
    
    // MARK: - Error Tests
    
    func testErrorDescription() {
        let pasteboardError = TextOutputError.pasteboardAccessFailed
        XCTAssertTrue(pasteboardError.description.contains("pasteboard"))
        
        let timeoutError = TextOutputError.timeout
        XCTAssertTrue(timeoutError.description.contains("timed"))
        
        let accessibilityError = TextOutputError.accessibilityNotAvailable
        XCTAssertTrue(accessibilityError.description.contains("Accessibility"))
        
        let insertionError = TextOutputError.insertionFailed("test")
        XCTAssertTrue(insertionError.description.contains("test"))
    }
    
    func testErrorIsRecoverable() {
        XCTAssertTrue(TextOutputError.pasteboardAccessFailed.isRecoverable)
        XCTAssertTrue(TextOutputError.timeout.isRecoverable)
        XCTAssertTrue(TextOutputError.accessibilityNotAvailable.isRecoverable)
        XCTAssertTrue(TextOutputError.permissionsDenied.isRecoverable)
        XCTAssertFalse(TextOutputError.noFocusedElement.isRecoverable)
        XCTAssertFalse(TextOutputError.targetApplicationNotFound.isRecoverable)
    }
    
    // MARK: - Output Mode Tests
    
    func testOutputModeDisplayNames() {
        XCTAssertEqual(OutputMode.clipboard.displayName, "Copy to Clipboard")
        XCTAssertEqual(OutputMode.type.displayName, "Type Text (simulate keystrokes)")
        XCTAssertEqual(OutputMode.paste.displayName, "Paste into Active Field")
        XCTAssertEqual(OutputMode.accessibility.displayName, "Direct Insert (Accessibility API)")
    }
    
    func testOutputModeCases() {
        let allCases = OutputMode.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.clipboard))
        XCTAssertTrue(allCases.contains(.type))
        XCTAssertTrue(allCases.contains(.paste))
        XCTAssertTrue(allCases.contains(.accessibility))
    }
    
    // MARK: - Options Tests
    
    func testTextOutputOptionsDefaults() {
        let options = TextOutputOptions.default
        XCTAssertEqual(options.delay, 0.1)
        XCTAssertEqual(options.selectionDelay, 0.05)
        XCTAssertEqual(options.restoreDelay, 0.1)
        XCTAssertEqual(options.timeout, 5.0)
        XCTAssertEqual(options.retryCount, 1)
        XCTAssertEqual(options.retryDelay, 0.2)
        XCTAssertTrue(options.useFallback)
        XCTAssertFalse(options.selectBeforeInsert)
    }
    
    func testTextOutputOptionsSlowApp() {
        let options = TextOutputOptions.slowApp
        XCTAssertEqual(options.delay, 0.3)
        XCTAssertEqual(options.selectionDelay, 0.1)
        XCTAssertEqual(options.restoreDelay, 0.2)
        XCTAssertEqual(options.retryCount, 2)
        XCTAssertEqual(options.retryDelay, 0.5)
    }
    
    func testTextOutputOptionsReplaceMode() {
        let options = TextOutputOptions.replaceMode
        XCTAssertTrue(options.selectBeforeInsert)
        XCTAssertEqual(options.delay, 0.1)
        XCTAssertEqual(options.selectionDelay, 0.1)
    }
    
    func testTextOutputOptionsCustomInit() {
        let options = TextOutputOptions(
            delay: 1.0,
            selectBeforeInsert: true,
            selectionDelay: 2.0,
            restoreDelay: 3.0,
            timeout: 10.0,
            retryCount: 3,
            retryDelay: 1.5,
            useFallback: false
        )
        XCTAssertEqual(options.delay, 1.0)
        XCTAssertTrue(options.selectBeforeInsert)
        XCTAssertEqual(options.selectionDelay, 2.0)
        XCTAssertEqual(options.restoreDelay, 3.0)
        XCTAssertEqual(options.timeout, 10.0)
        XCTAssertEqual(options.retryCount, 3)
        XCTAssertEqual(options.retryDelay, 1.5)
        XCTAssertFalse(options.useFallback)
    }
    
    // MARK: - Result Tests
    
    func testTextOutputResultSuccess() {
        let result = TextOutputResult.success
        XCTAssertTrue(result.isSuccess)
        XCTAssertNil(result.error)
    }
    
    func testTextOutputResultSuccessWithFallback() {
        let result = TextOutputResult.successWithFallback(source: "Pasteboard")
        XCTAssertTrue(result.isSuccess)
        XCTAssertNil(result.error)
    }
    
    func testTextOutputResultFailure() {
        let result = TextOutputResult.failure(.timeout)
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.error, .timeout)
    }
    
    // MARK: - Clipboard Tests
    
    func testCopyToClipboard() {
        let testText = "Test text"
        output.copyToClipboard(testText)
        
        let pasteboard = NSPasteboard.general
        XCTAssertEqual(pasteboard.string(forType: .string), testText)
    }
    
    func testClipboardManagerSaveAndRestore() {
        // Set initial clipboard content
        let initialText = "Initial text"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(initialText, forType: .string)
        
        // Save clipboard
        clipboardManager.saveClipboard()
        
        // Change clipboard
        clipboardManager.setString("New text")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "New text")
        
        // Restore clipboard
        clipboardManager.restoreClipboard()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), initialText)
        
        clipboardManager.clearSaved()
    }
    
    // MARK: - Service Availability Tests
    
    func testServiceAvailability() {
        // Pasteboard is always available
        XCTAssertTrue(service.isAvailable)
    }
    
    func testAccessibilityPermissionsCheck() {
        // This will depend on the actual system state
        // Just verify the method exists and returns a boolean
        _ = service.hasAccessibilityPermissions
    }
    
    // MARK: - Strategy Tests
    
    func testPasteboardStrategyAvailability() {
        let strategy = PasteboardTextOutput()
        XCTAssertTrue(strategy.isAvailable)
    }
    
    func testAccessibilityStrategyAvailability() {
        let strategy = AccessibilityTextOutput()
        // This will depend on system permissions
        // Just verify the method exists
        _ = strategy.isAvailable
    }
    
    func testStrategyNames() {
        let pasteboardStrategy = PasteboardTextOutput()
        XCTAssertEqual(pasteboardStrategy.strategyName, "PasteboardTextOutput")
        
        let accessibilityStrategy = AccessibilityTextOutput()
        XCTAssertEqual(accessibilityStrategy.strategyName, "AccessibilityTextOutput")
    }
    
    // MARK: - Integration Tests
    
    func testInsertTextWithDefaultOptions() async {
        // Test the service can be called (actual insertion requires GUI)
        let text = "Test text"
        let result = await service.insertText(text, options: .default)
        
        // Verify we got a result (success or failure is acceptable)
        XCTAssertNotNil(result)
    }
    
    func testCopyToClipboardViaService() {
        let testText = "Service test"
        service.copyToClipboard(testText)
        
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), testText)
    }
    
    func testReplaceTextOptions() async {
        let options = TextOutputOptions.replaceMode
        XCTAssertTrue(options.selectBeforeInsert)
        
        // Test the replace method can be called
        let result = await service.replaceText("Test")
        XCTAssertNotNil(result)
    }
    
    // MARK: - Output Mode Switching Tests
    
    func testOutputModeChanges() {
        // Test all output modes can be set
        let modes: [OutputMode] = [.clipboard, .type, .paste, .accessibility]
        for mode in modes {
            output.outputMode = mode
            XCTAssertEqual(output.outputMode, mode)
        }
    }
    
    func testOutputModeCodable() throws {
        let mode = OutputMode.accessibility
        let encoder = JSONEncoder()
        let data = try encoder.encode(mode.rawValue)
        
        let decoder = JSONDecoder()
        let rawValue = try decoder.decode(String.self, from: data)
        let decodedMode = OutputMode(rawValue: rawValue)
        XCTAssertEqual(decodedMode, .accessibility)
    }
    
    // MARK: - Legacy Compatibility Tests
    
    func testLegacyTextOutput() {
        // Verify the old API still works
        output.outputMode = .clipboard
        output.output(text: "Legacy test")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Legacy test")
    }
    
    func testServiceAccess() {
        let accessedService = output.currentService
        XCTAssertNotNil(accessedService)
    }
}

// MARK: - Performance Tests

@available(macOS 14.0, *)
extension TextOutputTests {
    func testClipboardSavePerformance() {
        let manager = ClipboardManager.shared
        measure {
            manager.saveClipboard()
        }
    }
    
    func testErrorLookupPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = TextOutputError.timeout.isRecoverable
            }
        }
    }
}