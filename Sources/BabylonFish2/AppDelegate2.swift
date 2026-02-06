import Cocoa
import SwiftUI
import Carbon
import IOKit
import ApplicationServices

class AppDelegate2: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var babylonFishEngine: BabylonFishEngine?
    var settingsWindow: NSWindow?
    var helpWindow: NSWindow?
    var suggestionWindow: SuggestionWindow?
    var retryTimer: Timer?
    var configObserver: NSObjectProtocol?
    
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
        
        // Update LaunchAgent path if enabled (since app path might have changed due to versioning)
        // Also ensure LaunchAgent exists if it was previously enabled via UserDefaults (resilience)
        updateLaunchAgentPathIfNeeded()
    }
    
    private func updateLaunchAgentPathIfNeeded() {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let launchAgentURL = library.appendingPathComponent("LaunchAgents").appendingPathComponent("com.babylonfish.app.plist")
        
        // Check if we SHOULD have it enabled based on UserDefaults (fallback)
        // We use a custom key "startAtLoginPreferred" to track intent
        let preferred = UserDefaults.standard.bool(forKey: "startAtLoginPreferred")
        
        let fileExists = FileManager.default.fileExists(atPath: launchAgentURL.path)
        
        if fileExists || preferred {
             // It's enabled (or should be), so let's update/create the plist
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
                 let launchAgentsDir = launchAgentURL.deletingLastPathComponent()
                 if !FileManager.default.fileExists(atPath: launchAgentsDir.path) {
                     try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
                 }
                 
                 try plistContent.write(to: launchAgentURL, atomically: true, encoding: .utf8)
                 logDebug("LaunchAgent updated/created at: \(execPath)")
                 
                 // If it was missing but preferred, we just restored it.
                 // We should probably tell launchd to load it?
                 // But simply writing the file is usually enough for the next login.
             } catch {
                 logDebug("Failed to update LaunchAgent: \(error)")
             }
        }
    }
    
    func constructMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "How to use? 🐠", action: #selector(openHelp), keyEquivalent: "?"))
        
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
    
    @objc func openHelp() {
        if helpWindow == nil {
            let helpView = HelpView()
            helpWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            helpWindow?.center()
            helpWindow?.contentView = NSHostingView(rootView: helpView)
            helpWindow?.title = "How to use BabylonFish"
        }
        
        helpWindow?.makeKeyAndOrderFront(nil)
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
        // 1. Check Accessibility (Trusted Process)
        // Do NOT prompt immediately. Check status first.
        let axGranted = hasAccessibility(prompt: false)
        
        if !axGranted {
            logDebug("Accessibility permission missing. Showing welcome/instruction window.")
            showWelcomeWindow()
            return
        }
        
        // 2. Start Listener (Requires Accessibility)
        // This might trigger Input Monitoring alert if not granted?
        // Actually, creating EventTap triggers Input Monitoring.
        // We should check if we have it before creating? 
        // IOHIDCheckAccess check is reliable.
        
        let imGranted = hasInputMonitoring()
        if !imGranted {
            logDebug("Input Monitoring permission missing. Showing welcome/instruction window.")
            showWelcomeWindow()
            return
        }

        // Permissions OK. Start.
        startAppLogic()
    }
    
    private func startAppLogic() {
        // Мигрируем настройки из v1 если нужно
        AppConfig.migrateFromV1()
        
        // Создаем движок BabylonFish 2.0
        babylonFishEngine = BabylonFishEngine()
        babylonFishEngine?.setSuggestionWindow(suggestionWindow)
        
        // Добавляем наблюдатель за изменением конфигурации
        configObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("BabylonFishConfigChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let newConfig = AppConfig.load()
            self.babylonFishEngine?.updateConfiguration(newConfig)
        }
        
        let success = babylonFishEngine?.start() ?? false
        
        if !success {
            logDebug("BabylonFishEngine failed to start despite permissions checks. Retrying...")
            // Если старт не удался, возможно, пермишены были отозваны или повреждены.
            // Но мы уже проверили их выше.
            // В редких случаях (обновление бинарника) система может "забыть" пермишены, но возвращать true.
            // Попробуем перезапросить/показать окно, но только если это не временная ошибка.
            
            // Если createTap возвращает null, это часто означает отсутствие прав.
            // Попробуем еще раз через секунду.
            scheduleRetry()
        } else {
             logDebug("BabylonFish 2.0 started successfully!")
        }
    }

    private func showWelcomeWindow() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Welcome to BabylonFish! 🐠"
            alert.informativeText = "To catch your typos, I need two permissions:\n\n1. Accessibility (to see what window is active)\n2. Input Monitoring (to catch keys)\n\nPlease click 'Open Settings', then toggle the switches for BabylonFish."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Quit")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open both if possible, or just Security root
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
                
                // Start a timer to check for permissions
                self.scheduleRetry()
            } else {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            
            // Check permissions silently
            if self.hasAccessibility(prompt: false) && self.hasInputMonitoring() {
                // Пытаемся запустить
                if let engine = self.babylonFishEngine {
                    if engine.start() {
                        logDebug("Retry successful!")
                        self.retryTimer?.invalidate()
                        self.retryTimer = nil
                    }
                } else {
                    // Если движок еще не создан, пробуем startAppLogic
                    self.retryTimer?.invalidate()
                    self.retryTimer = nil
                    self.startAppLogic()
                }
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
        // Overlay removed
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
        
        img.lockFocus()
        
        // Draw Fish
        let fish = "\u{1F420}" as NSString
        let fishAttrs = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 16)]
        fish.draw(at: NSPoint(x: 0, y: 1), withAttributes: fishAttrs)
        
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
    @State private var config = AppConfig.load()
    @State private var startAtLogin = false
    @State private var newException = ""
    
    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Enable Auto-Switching", isOn: $config.exceptions.globalEnabled)
                .toggleStyle(SwitchToggleStyle())
                .onChange(of: config.exceptions.globalEnabled) {
                    config.save()
                    notifyEngineConfigChanged()
                }
            
            Toggle("Auto-Correct Typos", isOn: $config.exceptions.autoCorrectTypos)
                .toggleStyle(SwitchToggleStyle())
                .onChange(of: config.exceptions.autoCorrectTypos) {
                    config.save()
                    notifyEngineConfigChanged()
                }
            
            Toggle("Start at Login", isOn: $startAtLogin)
                .toggleStyle(SwitchToggleStyle())
                .onChange(of: startAtLogin) {
                    toggleLaunchAtLogin($0)
                    // Persist preference
                    UserDefaults.standard.set($0, forKey: "startAtLoginPreferred")
                }
                .padding(.bottom)
            
            Text("Exceptions (Applications or Words):")
                .font(.headline)
            
            HStack {
                TextField("Add exception...", text: $newException)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Add") {
                    if !newException.isEmpty {
                        config.exceptions.wordExceptions.insert(newException)
                        config.save()
                        newException = ""
                        notifyEngineConfigChanged()
                    }
                }
            }
            
            List {
                ForEach(Array(config.exceptions.wordExceptions.sorted()), id: \.self) { item in
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
            // Check actual status
            startAtLogin = isLaunchAtLoginEnabled()
        }
    }
    
    func deleteException(at offsets: IndexSet) {
        let sortedItems = Array(config.exceptions.wordExceptions.sorted())
        for offset in offsets {
            if offset < sortedItems.count {
                config.exceptions.wordExceptions.remove(sortedItems[offset])
            }
        }
        config.save()
        notifyEngineConfigChanged()
    }
    
    private func notifyEngineConfigChanged() {
        // Notify AppDelegate to update engine configuration
        NotificationCenter.default.post(name: NSNotification.Name("BabylonFishConfigChanged"), object: nil)
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
