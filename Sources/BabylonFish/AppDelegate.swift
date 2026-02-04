import Cocoa
import SwiftUI
import Carbon
import IOKit
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var inputListener: InputListener?
    var settingsWindow: NSWindow?
    var suggestionWindow: SuggestionWindow?
    var retryTimer: Timer?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Register defaults
        UserDefaults.standard.register(defaults: ["autoSwitchEnabled": true])
        
        suggestionWindow = SuggestionWindow()
        
        let bundlePath = Bundle.main.bundlePath
        let executablePath = Bundle.main.executableURL?.path ?? (CommandLine.arguments.first ?? "")
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? Version.current
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        logDebug("App launch: pid=\(ProcessInfo.processInfo.processIdentifier) bundle=\(bundlePath) exe=\(executablePath) version=\(version) build=\(build)")

        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = drawIcon(flag: nil)
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        constructMenu()
        ensurePermissionsAndStart()
        
        // Listen for input source changes
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(inputSourceChanged), name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        
        // Initial update
        updateIcon()
    }
    
    func constructMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? Version.current
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        let versionItem = NSMenuItem(title: "Version \(version) (\(build))", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Accessibility…", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Input Monitoring…", action: #selector(openInputMonitoringSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Retry Start Listener", action: #selector(retryStartListener), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit BabylonFish", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            settingsWindow?.center()
            settingsWindow?.setFrameAutosaveName("Settings")
            settingsWindow?.contentView = NSHostingView(rootView: settingsView)
            settingsWindow?.title = "BabylonFish Settings"
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func checkAccessibilityPermissions() {
        _ = AXIsProcessTrusted()
    }

    func checkInputMonitoringPermissions() {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if access == kIOHIDAccessTypeGranted {
            return
        }

        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let recheck = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            if recheck != kIOHIDAccessTypeGranted {
                self.showInputMonitoringAlert()
            }
        }
    }

    func showInputMonitoringAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Input Monitoring Required"
            alert.informativeText = "BabylonFish can see modifier keys (Shift), but macOS is blocking normal key presses.\n\nGo to System Settings -> Privacy & Security -> Input Monitoring and enable BabylonFish.\n\nIf BabylonFish is not in the list, add it with the '+' button."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func hasAccessibility(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func hasInputMonitoring() -> Bool {
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private func ensurePermissionsAndStart() {
        let axGranted = hasAccessibility(prompt: true)
        let imGranted = hasInputMonitoring()
        logDebug("Checking permissions: AX=\(axGranted) IM=\(imGranted)")
        
        if !axGranted {
            logDebug("Accessibility permission missing. Showing alert.")
            showPermissionsAlert()
            scheduleRetry()
            return
        }

        inputListener = InputListener()
        inputListener?.suggestionWindow = suggestionWindow
        let success = inputListener?.start() ?? false
        if !success {
            logDebug("InputListener failed to start (likely Accessibility permission missing).")
            scheduleRetry()
        }
        checkInputMonitoringPermissions()
    }

    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Don't prompt repeatedly in the timer
            if self.hasAccessibility(prompt: false), self.hasInputMonitoring() {
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                self.inputListener = InputListener()
                self.inputListener?.suggestionWindow = self.suggestionWindow
                let ok = self.inputListener?.start() ?? false
                logDebug("Retry start InputListener, success=\(ok)")
            }
        }
    }

    @objc func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func retryStartListener() {
        ensurePermissionsAndStart()
    }
    
    func showPermissionsAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permissions Required"
            alert.informativeText = "BabylonFish needs Accessibility permissions to function.\n\nSince the app was updated, macOS may have invalidated the previous permission.\n\nPlease go to System Settings -> Privacy & Security -> Accessibility, remove 'BabylonFish' (using the '-' button), and add it again."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Quit")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            } else {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    @objc func inputSourceChanged() {
        updateIcon()
        
        // Show Visual Border
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let sourceIDPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        
        if let ptr = sourceIDPtr {
            let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            if id.contains("Russian") {
                // Blue for Russian
                OverlayWindow.shared.flash(color: .systemBlue)
            } else if id.contains("US") || id.contains("English") {
                // Red for English
                OverlayWindow.shared.flash(color: .systemRed)
            }
        }
    }
    
    func updateIcon() {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let sourceIDPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        
        var flag: String? = nil
        if let ptr = sourceIDPtr {
            let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            if id.contains("Russian") {
                flag = "🇷🇺"
            } else if id.contains("US") || id.contains("English") {
                flag = "🇺🇸"
            }
        }
        
        DispatchQueue.main.async {
            self.statusItem.button?.image = self.drawIcon(flag: flag)
        }
    }
    
    func drawIcon(flag: String?) -> NSImage {
        let size = NSSize(width: 26, height: 22)
        let img = NSImage(size: size)
        
        // Try to load custom icon
        var customIcon: NSImage?
        if let path = Bundle.main.path(forResource: "tray_icon", ofType: "png") {
            customIcon = NSImage(contentsOfFile: path)
        }
        
        img.lockFocus()
        
        if let icon = customIcon {
            // Draw custom icon resized to fit
            // Keep aspect ratio, fit within 20x20
            let rect = NSRect(x: 0, y: 2, width: 18, height: 18)
            icon.draw(in: rect)
        } else {
            // Draw Fish (Fallback)
            let fish = "🐠" as NSString
            let fishAttrs = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 16)]
            fish.draw(at: NSPoint(x: 0, y: 1), withAttributes: fishAttrs)
        }
        
        // Draw Flag if available
        if let flag = flag {
            let flagStr = flag as NSString
            let flagAttrs = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 10)]
            flagStr.draw(at: NSPoint(x: 14, y: 0), withAttributes: flagAttrs)
        }
        
        img.unlockFocus()
        img.isTemplate = false // Keep colors
        return img
    }
}

struct SettingsView: View {
    @AppStorage("autoSwitchEnabled") private var autoSwitchEnabled = true
    @AppStorage("startAtLogin") private var startAtLogin = false
    @State private var newException = ""
    @AppStorage("exceptions") private var exceptionsData: Data = Data()
    
    @State private var exceptions: [String] = []
    
    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Enable Auto-Switching", isOn: $autoSwitchEnabled)
                .toggleStyle(SwitchToggleStyle())
            
            Toggle("Start at Login", isOn: $startAtLogin)
                .toggleStyle(SwitchToggleStyle())
                .onChange(of: startAtLogin) { newValue in
                    toggleLaunchAtLogin(newValue)
                }
                .padding(.bottom)
            
            Text("Exceptions (Applications or Words):")
                .font(.headline)
            
            HStack {
                TextField("Add exception...", text: $newException)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Add") {
                    if !newException.isEmpty {
                        exceptions.append(newException)
                        saveExceptions()
                        newException = ""
                    }
                }
            }
            
            List {
                ForEach(exceptions, id: \.self) { item in
                    Text(item)
                }
                .onDelete(perform: deleteException)
            }
            .border(Color.gray.opacity(0.2))
            
            Text("Note: Use Right Arrow (->) to temporarily prevent switching.")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top)
        }
        .padding()
        .frame(width: 500, height: 400)
        .onAppear {
            loadExceptions()
            // Check actual status
            startAtLogin = isLaunchAtLoginEnabled()
        }
    }
    
    func deleteException(at offsets: IndexSet) {
        exceptions.remove(atOffsets: offsets)
        saveExceptions()
    }
    
    func saveExceptions() {
        if let data = try? JSONEncoder().encode(exceptions) {
            exceptionsData = data
        }
    }
    
    func loadExceptions() {
        if let loaded = try? JSONDecoder().decode([String].self, from: exceptionsData) {
            exceptions = loaded
        }
    }
    
    // MARK: - Launch at Login Logic
    // Using LaunchAgent plist for robustness with non-sandboxed app
    
    private var launchAgentURL: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let launchAgents = library.appendingPathComponent("LaunchAgents")
        return launchAgents.appendingPathComponent("com.babylonfish.app.plist")
    }
    
    private func isLaunchAtLoginEnabled() -> Bool {
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }
    
    private func toggleLaunchAtLogin(_ enabled: Bool) {
        let fileManager = FileManager.default
        let url = launchAgentURL
        
        if enabled {
            // Create LaunchAgent plist
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
                // Ensure directory exists
                let launchAgentsDir = url.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: launchAgentsDir.path) {
                    try fileManager.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
                }
                
                try plistContent.write(to: url, atomically: true, encoding: .utf8)
                logDebug("LaunchAgent created at \(url.path)")
            } catch {
                logDebug("Failed to create LaunchAgent: \(error)")
            }
        } else {
            // Remove LaunchAgent plist
            do {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                    logDebug("LaunchAgent removed")
                }
            } catch {
                logDebug("Failed to remove LaunchAgent: \(error)")
            }
        }
    }
}
