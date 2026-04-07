import XCTest
@testable import TranscriptionEngine
@testable import AudioCapture

@available(macOS 14.0, *)
final class TranscriptionEngineTests: XCTestCase {
    
    var engine: TranscriptionEngine!
    
    override func setUp() {
        super.setUp()
        engine = TranscriptionEngine()
    }
    
    override func tearDown() {
        engine = nil
        super.tearDown()
    }
    
    func testErrorDescription() {
        let noModelError = TranscriptionError.noModelLoaded
        XCTAssertTrue(noModelError.description.contains("model"))
        
        let loadFailedError = TranscriptionError.modelLoadFailed("test")
        XCTAssertTrue(loadFailedError.description.contains("test"))
    }
    
    func testTranscriptionSegment() {
        let segment = TranscriptionSegment(
            text: "Hello world",
            startTime: 0.0,
            endTime: 1.0,
            confidence: 0.95
        )
        
        XCTAssertEqual(segment.text, "Hello world")
        XCTAssertEqual(segment.confidence, 0.95)
    }
    
    func testTranscriptionResult() {
        let result = TranscriptionResult(
            text: "Hello",
            segments: [],
            duration: 1.0,
            processingTime: 0.5,
            language: "en"
        )
        
        XCTAssertEqual(result.text, "Hello")
        XCTAssertEqual(result.language, "en")
    }
    
    func testWhisperModelSize() {
        let allSizes = WhisperModelSize.allCases
        XCTAssertEqual(allSizes.count, 5)
        
        XCTAssertEqual(WhisperModelSize.tiny.displayName, "Tiny (fastest, least accurate)")
        XCTAssertEqual(WhisperModelSize.largeV3.fileSize, "~2.9 GB")
    }
}
