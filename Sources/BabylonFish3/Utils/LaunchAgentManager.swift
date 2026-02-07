import Foundation

class LaunchAgentManager {
    static func updatePathIfNeeded() {
        // Simple implementation for now
        logDebug("LaunchAgentManager: updatePathIfNeeded called")
    }
    
    static func toggle(_ enabled: Bool) {
        logDebug("LaunchAgentManager: toggle to \(enabled)")
    }
    
    static func isEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: "startAtLoginPreferred")
    }
}