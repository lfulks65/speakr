import Foundation

private let logFile: URL = URL(fileURLWithPath: "/tmp/speakr.log")
private let logHandle: FileHandle? = {
    // Create or truncate the log file on launch
    FileManager.default.createFile(atPath: logFile.path, contents: nil)
    return try? FileHandle(forWritingTo: logFile)
}()

func wfLog(_ message: String, file: String = #file, line: Int = #line) {
    let filename = URL(fileURLWithPath: file).lastPathComponent
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "\(ts) [\(filename):\(line)] \(message)\n"
    if let data = line.data(using: .utf8) {
        logHandle?.write(data)
    }
    // Also write to stderr so it shows in Xcode/terminal
    fputs(line, stderr)
}
