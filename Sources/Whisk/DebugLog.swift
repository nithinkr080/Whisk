import Foundation

/// Appends a line to ~/Library/Logs/Whisk.log (handy for diagnosing switching problems).
/// Off by default: enable with `defaults write io.github.nithinkr080.whisk debugLog -bool true`.
func debugLog(_ message: String) {
    guard UserDefaults.standard.bool(forKey: "debugLog") else { return }
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Whisk.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile(); handle.write(data); try? handle.close()
    } else {
        try? data.write(to: url)
    }
}
