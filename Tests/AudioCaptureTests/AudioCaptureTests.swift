import XCTest
@testable import AudioCapture

@available(macOS 14.0, *)
final class AudioCaptureTests: XCTestCase {
    
    var audioCapture: AudioCapture!
    
    override func setUp() {
        super.setUp()
        audioCapture = AudioCapture()
    }
    
    override func tearDown() {
        audioCapture = nil
        super.tearDown()
    }
    
    func testAudioCaptureErrorDescription() {
        let permissionError = AudioCaptureError.permissionDenied
        XCTAssertTrue(permissionError.description.contains("Microphone"))
        
        let deviceError = AudioCaptureError.noInputDevice
        XCTAssertTrue(deviceError.description.contains("input device"))
        
        let setupError = AudioCaptureError.setupFailed("test reason")
        XCTAssertTrue(setupError.description.contains("test reason"))
    }
    
    func testAudioLevelInit() {
        let level = AudioLevel(average: 0.5, peak: 0.8)
        XCTAssertEqual(level.average, 0.5)
        XCTAssertEqual(level.peak, 0.8)
    }
}
