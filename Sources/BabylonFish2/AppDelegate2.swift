import Cocoa
import SwiftUI
import Carbon
import IOKit
import ApplicationServices

class AppDelegate2: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var babylonFishEngine: BabylonFishEngine?
    var settingsWindow: NSWindow?
    var helpWindow: NSWindow?
    var suggestionWindow: SuggestionWindow?
    var retryTimer: Timer?
    var configObserver: NSObjectProtocol?
    var menuRefreshWorkItem: DispatchWorkItem?
    var firstLaunchAlertShown = false
    
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

        // Create status bar controller
        suggestionWindow = SuggestionWindow()
        statusBarController = StatusBarController(engine: babylonFishEngine)
        
        // Check if this is first launch
        let isFirstLaunch = UserDefaults.standard.object(forKey: "babylonfish_first_launch") == nil
        
        if isFirstLaunch {
            // Mark as launched
            UserDefaults.standard.set(true, forKey: "babylonfish_first_launch")
            
            // Show welcome alert on first launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showFirstLaunchAlert()
            }
        }
        
        ensurePermissionsAndStart()
        
        // Listen for input source changes
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(inputSourceChanged), name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        
        // Initial update
        updateIcon()
        
        // Update LaunchAgent path if enabled (since app path might have changed due to versioning)
        // Also ensure LaunchAgent exists if it was previously enabled via UserDefaults (resilience)
        LaunchAgentManager.updatePathIfNeeded()
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
            settingsWindow?.title = "Настройки BabylonFish"
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
            helpWindow?.title = "Как пользоваться BabylonFish"
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
            alert.messageText = "Требуется мониторинг ввода"
            alert.informativeText = "BabylonFish видит клавиши-модификаторы (Shift), но macOS блокирует обычные нажатия клавиш.\n\nПерейдите в Системные настройки -> Конфиденциальность и безопасность -> Мониторинг ввода и включите BabylonFish.\n\nЕсли BabylonFish нет в списке, добавьте его с помощью кнопки '+'."
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
        
        // 2. Check Input Monitoring
        let imGranted = hasInputMonitoring()
        
        if !axGranted || !imGranted {
            logDebug("Permissions missing: Accessibility=\(axGranted), InputMonitoring=\(imGranted)")
            
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
            logDebug("BabylonFish 3.0 started successfully!")
            
            // Show success notification
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.statusBarController?.showNotification(
                    title: "BabylonFish 3.0 запущен! 🎉",
                    message: "Теперь приложение будет автоматически переключать раскладку и исправлять опечатки."
                )
            }
        }
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
            alert.messageText = "Требуются разрешения для BabylonFish 🐠"
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
            scheduleRetry()
        }
    }

    @objc func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
            scheduleRetry()
        }
    }

    @objc func retryStartListener() {
        ensurePermissionsAndStart()
    }
    
    func showPermissionsAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Требуется универсальный доступ"
            alert.informativeText = "BabylonFish требуются права универсального доступа для работы.\n\nТак как приложение было обновлено, macOS могла аннулировать предыдущее разрешение.\n\nПожалуйста, перейдите в Системные настройки -> Конфиденциальность и безопасность -> Универсальный доступ, удалите 'BabylonFish' (используя кнопку '-') и добавьте его снова."
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
        updateIcon()
        // Overlay removed
    }
    
    func updateIcon() {
        DispatchQueue.main.async {
            // Icon is now handled by StatusBarController
            self.statusBarController?.updateStatusBarIcon()
        }
    }
    

}

// SettingsView moved to separate file
