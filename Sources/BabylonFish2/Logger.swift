import Foundation
import os

class FileLogger {
    static let shared = FileLogger()
    
    private let logFileURL: URL
    private let oslog: OSLog
    
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        logFileURL = home.appendingPathComponent("babylonfish_debug.log")
        oslog = OSLog(subsystem: "com.babylonfish.app", category: "runtime")
        // Create file if not exists
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }
    
    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)\n"
        
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            if let data = logMessage.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        }
        os_log("%{public}@", log: oslog, type: .default, message)
    }
}

func logDebug(_ message: String) {
    FileLogger.shared.log(message)
}
