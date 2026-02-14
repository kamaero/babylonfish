import Foundation
import os

class FileLogger {
    static let shared = FileLogger()
    
    private let logFileURL: URL
    private let oslog: OSLog
    
    init() {
        // Используем директорию Downloads для удобного доступа
        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let logPath = downloadsDirectory.appendingPathComponent("babylonfish_debug.log").path
        logFileURL = URL(fileURLWithPath: logPath)
        
        oslog = OSLog(subsystem: "com.babylonfish.app", category: "runtime")
        // Create file if not exists
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        }
        
        // Ensure everyone can write to it (in case of user/root switching)
        try? FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: logFileURL.path)
        
        // Логируем путь к файлу для отладки
        print("Логи будут записываться в: \(logFileURL.path)")
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
    FileLogger.shared.log("[DEBUG] \(message)")
}

func logInfo(_ message: String) {
    FileLogger.shared.log("[INFO] \(message)")
}

func logWarning(_ message: String) {
    FileLogger.shared.log("[WARNING] \(message)")
}

func logError(_ message: String) {
    FileLogger.shared.log("[ERROR] \(message)")
}

func logError(_ error: Error, context: String = "") {
    let message = context.isEmpty ? "\(error)" : "\(context): \(error)"
    FileLogger.shared.log("[ERROR] \(message)")
}
