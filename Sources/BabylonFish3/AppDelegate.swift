import Cocoa
import SwiftUI
import Carbon
import IOKit
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var babylonFishEngine: BabylonFishEngine?
    var suggestionWindow: SuggestionWindow?
    var retryTimer: Timer?
    var eventsCheckTimer: Timer?
    var configObserver: NSObjectProtocol?
    var firstLaunchAlertShown = false
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Register defaults
        UserDefaults.standard.register(defaults: ["autoSwitchEnabled": true])
        
        // Create suggestion window
        suggestionWindow = SuggestionWindow()
        
        let bundlePath = Bundle.main.bundlePath
        let executablePath = Bundle.main.executableURL?.path ?? (CommandLine.arguments.first ?? "")
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "3.0.0"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        logDebug("BabylonFish 3.0 launch: pid=\(ProcessInfo.processInfo.processIdentifier) bundle=\(bundlePath) exe=\(executablePath) version=\(version) build=\(build)")
        
        // Create status bar controller (engine can be attached later)
        statusBarController = StatusBarController(engine: nil)
        
        // Check if this is first launch
        let isFirstLaunch = UserDefaults.standard.object(forKey: "babylonfish3_first_launch") == nil
        
        if isFirstLaunch {
            // Mark as launched
            UserDefaults.standard.set(true, forKey: "babylonfish3_first_launch")
            
            // Show welcome alert on first launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showFirstLaunchAlert()
            }
        }
        
        ensurePermissionsAndStart()
        
        // Listen for input source changes
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(inputSourceChanged), name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        
        // Update LaunchAgent path if enabled
        LaunchAgentManager.updatePathIfNeeded()
    }
    
    private func showFirstLaunchAlert() {
        guard !firstLaunchAlertShown else { return }
        firstLaunchAlertShown = true
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Добро пожаловать в BabylonFish 3.0! 🐠"
            alert.informativeText = "Чтобы автоматически переключать раскладку клавиатуры и исправлять опечатки, мне нужны два разрешения:\n\n1. 🖥️ Универсальный доступ — чтобы видеть активное окно\n2. ⌨️ Мониторинг ввода — чтобы видеть нажатия клавиш\n\nБез этих разрешений приложение не сможет работать.\n\nНажмите 'Открыть настройки', затем включите переключатели для BabylonFish в обоих разделах."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Открыть настройки")
            alert.addButton(withTitle: "Позже")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open Accessibility settings
                let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(accessibilityURL)
                
                // Open Input Monitoring after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let inputMonitoringURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
                    NSWorkspace.shared.open(inputMonitoringURL)
                }
                
                // Show notification reminder
                self.statusBarController?.showNotification(
                    title: "BabylonFish 3.0",
                    message: "Не забудьте включить оба разрешения в Системных настройках!"
                )
                
                // Start checking for permissions
                self.scheduleRetry()
            }
        }
    }
    
    private func showWelcomeWindow() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Требуются разрешения для BabylonFish 3.0 🐠"
            alert.informativeText = "Для работы приложения нужны два разрешения:\n\n1. 🖥️ Универсальный доступ — чтобы видеть активное окно\n2. ⌨️ Мониторинг ввода — чтобы видеть нажатия клавиш\n\nБез этих разрешений приложение не сможет автоматически переключать раскладку и исправлять опечатки.\n\nНажмите 'Открыть настройки', затем включите переключатели для BabylonFish в обоих разделах."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Открыть настройки")
            alert.addButton(withTitle: "Позже")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open Accessibility settings
                let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(accessibilityURL)
                
                // Open Input Monitoring after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let inputMonitoringURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
                    NSWorkspace.shared.open(inputMonitoringURL)
                }
                
                // Start checking for permissions
                self.scheduleRetry()
            }
        }
    }
    
    private func ensurePermissionsAndStart() {
        // 1. Check Accessibility (Trusted Process)
        let axGranted = hasAccessibility(prompt: false)
        
        // 2. Check Input Monitoring
        let imGranted = hasInputMonitoring()
        
        logDebug("Permission check: Accessibility=\(axGranted), InputMonitoring=\(imGranted)")
        
        if !axGranted || !imGranted {
            logDebug("Permissions missing: Accessibility=\(axGranted), InputMonitoring=\(imGranted)")
            
            // Show diagnostic info
            showPermissionDiagnostics(axGranted: axGranted, imGranted: imGranted)
            
            if !imGranted {
                // Trigger Input Monitoring prompt if possible
                checkInputMonitoringPermissions()
            }
            
            // Show alert only if we haven't shown the first launch alert recently
            // or if permissions are still missing after user was prompted
            if !firstLaunchAlertShown {
                // First launch alert will be shown separately
                return
            } else {
                // Show welcome window for missing permissions
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.showWelcomeWindow()
                }
            }
            return
        }

        // Permissions OK. Start.
        startAppLogic()
    }
    
    private func showPermissionTroubleshootingAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Проблема с разрешениями BabylonFish 3.0 🔧"
            alert.informativeText = """
            Похоже, разрешения не применяются правильно. Это частая проблема в macOS.

            Пожалуйста, выполните следующие шаги:

            1. Убедитесь, что BabylonFish3 НЕТ в списках разрешений
            2. Удалите BabylonFish3 из обоих списков (если есть)
            3. Перезапустите BabylonFish3
            4. При повторном запуске добавьте его в оба списка

            Или используйте скрипт для сброса разрешений:
            Откройте Терминал и выполните:
            cd \(FileManager.default.currentDirectoryPath)
            ./fix_permissions.sh
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Открыть настройки")
            alert.addButton(withTitle: "Запустить скрипт")
            alert.addButton(withTitle: "Позже")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open both settings
                let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(accessibilityURL)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let inputMonitoringURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
                    NSWorkspace.shared.open(inputMonitoringURL)
                }
            } else if response == .alertSecondButtonReturn {
                // Run the fix script
                self.runFixPermissionsScript()
            }
        }
    }
    
    private func showPermissionDiagnostics(axGranted: Bool, imGranted: Bool) {
        logDebug("=== Permission Diagnostics ===")
        logDebug("App Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        logDebug("App Path: \(Bundle.main.bundlePath)")
        logDebug("Executable Path: \(Bundle.main.executableURL?.path ?? "unknown")")
        
        // Check if app is in Accessibility list
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        logDebug("AXIsProcessTrustedWithOptions: \(trusted)")
        
        // Check Input Monitoring via IOHID
        let imStatus = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        logDebug("IOHIDCheckAccess status: \(imStatus)")
        
        // Log TCC database info if possible
        logDebug("TCC Database paths:")
        logDebug("  User: ~/Library/Application Support/com.apple.TCC/TCC.db")
        logDebug("  System: /Library/Application Support/com.apple.TCC/TCC.db")
        
        // Show user-friendly message
        if !axGranted && !imGranted {
            logDebug("Diagnosis: Both permissions missing")
        } else if !axGranted {
            logDebug("Diagnosis: Only Accessibility missing")
        } else if !imGranted {
            logDebug("Diagnosis: Only Input Monitoring missing")
        }
        
        logDebug("=== End Diagnostics ===")
    }
    
    private func startAppLogic() {
        // Migrate settings from previous versions
        AppConfig.migrateFromPreviousVersions()
        
        // Create BabylonFish 3.0 engine
        babylonFishEngine = BabylonFishEngine()
        babylonFishEngine?.setSuggestionWindow(suggestionWindow)
        
        // Update status bar controller with engine
        statusBarController?.updateEngine(babylonFishEngine)
        
        // Add observer for configuration changes
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
            logDebug("BabylonFishEngine failed to start despite permissions checks.")
            
            // Check permissions again to see if they were revoked
            let axGranted = hasAccessibility(prompt: false)
            let imGranted = hasInputMonitoring()
            
            if !axGranted || !imGranted {
                logDebug("Permissions appear to be missing after engine start attempt")
                logDebug("Accessibility: \(axGranted), InputMonitoring: \(imGranted)")
                
                // Show more aggressive alert about permissions
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.showPermissionTroubleshootingAlert()
                }
            } else {
                logDebug("Permissions OK but engine still failed. Possible event tap issue.")
                scheduleRetry()
            }
        } else {
            logDebug("BabylonFish 3.0 started successfully!")
            
            // Show success notification
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.statusBarController?.showNotification(
                    title: "BabylonFish 3.0 запущен! 🎉",
                    message: "Теперь приложение будет автоматически переключать раскладку и исправлять опечатки."
                )
            }
            
            scheduleEventsCheck()
        }
    }
    
    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            
            // Check permissions silently
            if self.hasAccessibility(prompt: false) && self.hasInputMonitoring() {
                // Try to start
                if let engine = self.babylonFishEngine {
                    if engine.start() {
                        logDebug("Retry successful!")
                        self.retryTimer?.invalidate()
                        self.retryTimer = nil
                    }
                } else {
                    // If engine not created yet, try startAppLogic
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
            scheduleRetry()
        }
    }
    
    @objc func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
            scheduleRetry()
        }
    }
    
    @objc func resetPermissionsFromMenu() {
        runFixPermissionsScript()
        openAccessibilitySettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.openInputMonitoringSettings()
        }
    }
    
    @objc func retryStartListener() {
        ensurePermissionsAndStart()
    }
    
    private func scheduleEventsCheck() {
        eventsCheckTimer?.invalidate()
        eventsCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            let stats = self.babylonFishEngine?.getAllStatistics() ?? [:]
            if let etm = stats["eventTapManager"] as? [String: Any],
               let processed = etm["eventsProcessed"] as? Int,
               let running = etm["isRunning"] as? Bool,
               running, processed == 0 {
                self.runFixPermissionsScript()
                self.openAccessibilitySettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.openInputMonitoringSettings()
                }
                self.scheduleRetry()
            }
        }
    }
    
    func showPermissionsAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Требуется универсальный доступ"
            alert.informativeText = "BabylonFish 3.0 требуются права универсального доступа для работы.\n\nТак как приложение было обновлено, macOS могла аннулировать предыдущее разрешение.\n\nПожалуйста, перейдите в Системные настройки -> Конфиденциальность и безопасность -> Универсальный доступ, удалите 'BabylonFish' (используя кнопку '-') и добавьте его снова."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Открыть настройки")
            alert.addButton(withTitle: "Выход")
            
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
        // Update status bar icon
        DispatchQueue.main.async {
            self.statusBarController?.updateStatusBarIcon()
        }
    }
    
    private func hasAccessibility(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    private func hasInputMonitoring() -> Bool {
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
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
            alert.messageText = "Требуется мониторинг ввода"
            alert.informativeText = "BabylonFish 3.0 видит клавиши-модификаторы (Shift), но macOS блокирует обычные нажатия клавиш.\n\nПерейдите в Системные настройки -> Конфиденциальность и безопасность -> Мониторинг ввода и включите BabylonFish.\n\nЕсли BabylonFish нет в списке, добавьте его с помощью кнопки '+'."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Открыть настройки")
            alert.addButton(withTitle: "Позже")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func runFixPermissionsScript() {
        var scriptPath = "\(FileManager.default.currentDirectoryPath)/fix_permissions.sh"
        
        // Check if script exists in Resources
        if let resourcePath = Bundle.main.path(forResource: "fix_permissions", ofType: "sh") {
            scriptPath = resourcePath
        }
        
        if FileManager.default.fileExists(atPath: scriptPath) {
            logDebug("Running fix permissions script: \(scriptPath)")
            
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = [scriptPath]
            
            do {
                try task.run()
                logDebug("Fix permissions script launched")
                
                // Schedule retry after script runs
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.scheduleRetry()
                }
            } catch {
                logDebug("Failed to run fix script: \(error)")
            }
        } else {
            logDebug("Fix permissions script not found at: \(scriptPath)")
            
            // Show alert that script is missing
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Скрипт не найден"
                alert.informativeText = "Скрипт fix_permissions.sh не найден в текущей директории.\n\nСоздайте его с помощью команды в Терминале."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}
