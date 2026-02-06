import Foundation
import Cocoa

struct LaunchAgentManager {
    static var url: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let launchAgents = library.appendingPathComponent("LaunchAgents")
        return launchAgents.appendingPathComponent("com.babylonfish.app.plist")
    }
    
    static func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
    
    static func toggle(_ enabled: Bool) {
        let fileManager = FileManager.default
        let targetURL = url
        
        if enabled {
            let execPath = Bundle.main.bundlePath + "/Contents/MacOS/BabylonFish"
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.babylonfish.app</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(execPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <false/>
            </dict>
            </plist>
            """
            
            do {
                let launchAgentsDir = targetURL.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: launchAgentsDir.path) {
                    try fileManager.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
                }
                try plistContent.write(to: targetURL, atomically: true, encoding: .utf8)
                logDebug("LaunchAgent created at \(targetURL.path)")
            } catch {
                logDebug("Failed to create LaunchAgent: \(error)")
            }
        } else {
            do {
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                    logDebug("LaunchAgent removed")
                }
            } catch {
                logDebug("Failed to remove LaunchAgent: \(error)")
            }
        }
    }
    
    static func updatePathIfNeeded() {
        let targetURL = url
        let preferred = UserDefaults.standard.bool(forKey: "startAtLoginPreferred")
        let fileExists = FileManager.default.fileExists(atPath: targetURL.path)
        if fileExists || preferred {
            toggle(true)
        }
    }
}
