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
    var configObserver: NSObjectProtocol?
    var firstLaunchAlertShown = false
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Register defaults
        UserDefaults.standard.register(defaults: ["autoSwitchEnabled": true])
        
        // Create suggestion window
        suggestionWindow = SuggestionWindow()
        
        let bundlePath = Bundle.main.bundlePath
        let _ = Bundle.main.executableURL?.path ?? (CommandLine.arguments.first ?? "") // Используем _ чтобы избежать предупреждения
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "3.0.0"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        let bundleID = info["CFBundleIdentifier"] as? String ?? "com.babylonfish.app"
        
        // Форматируем путь для логов
         let formattedPath: String
         if bundlePath.hasPrefix("/Applications/") {
             formattedPath = "System: \(bundlePath)"
         } else if bundlePath.hasPrefix("/Users/") {
             let components = bundlePath.components(separatedBy: "/")
             if components.count > 3 {
                 formattedPath = "User: ~/\(components[3...].joined(separator: "/"))"
             } else {
                 formattedPath = "User: \(bundlePath)"
             }
         } else {
             formattedPath = bundlePath
         }
         
         logDebug("BabylonFish 3.0 launch: pid=\(ProcessInfo.processInfo.processIdentifier) bundleID=\(bundleID) path=\(formattedPath) version=\(version) build=\(build)")
         
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
        logDebug("=== ПРОВЕРКА ПРАВ И ЗАПУСК ===")
        
        // Защита от слишком частых проверок
        struct CheckLock {
            static var isChecking = false
            static var lastCheckTime: Date?
        }
        
        let now = Date()
        if let lastCheck = CheckLock.lastCheckTime, now.timeIntervalSince(lastCheck) < 1.0 {
            logDebug("⚠️ СЛИШКОМ ЧАСТЫЕ ПРОВЕРКИ ПРАВ, пропускаем")
            return
        }
        
        if CheckLock.isChecking {
            logDebug("⚠️ ПРОВЕРКА ПРАВ УЖЕ ВЫПОЛНЯЕТСЯ, пропускаем")
            return
        }
        
        CheckLock.isChecking = true
        CheckLock.lastCheckTime = now
        
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                CheckLock.isChecking = false
            }
        }
        
        // 1. Проверяем доступность (Trusted Process)
        let axGranted = hasAccessibility(prompt: false)
        
        // 2. Проверяем мониторинг ввода
        let imGranted = hasInputMonitoring()
        
        logDebug("✅ Проверка прав: Доступность=\(axGranted), Мониторинг ввода=\(imGranted)")
        
        if !imGranted {
            logDebug("⚠️ Недостаточно прав: Доступность=\(axGranted), Мониторинг ввода=\(imGranted)")
            
            // Показываем алерт, если оба разрешения отсутствуют
            if !axGranted && !imGranted {
                DispatchQueue.main.async {
                    self.showPermissionsAlert()
                }
            }
            
            // Планируем повторную проверку
            scheduleRetry()
            return
        }
        
        // Все права получены, запускаем движок
        logDebug("✅ Все права получены, запускаем движок...")
        
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
            ./fix_permissions_safe.sh
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
    

    
    private func startAppLogic() {
        do {
            // Migrate settings from previous versions
            try AppConfig.migrateFromPreviousVersions()
            
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
                logError("BabylonFishEngine failed to start despite permissions checks.")
                
                // Check permissions again to see if they were revoked
                let axGranted = hasAccessibility(prompt: false)
                let imGranted = hasInputMonitoring()
                
                if !axGranted || !imGranted {
                    logError("Permissions appear to be missing after engine start attempt")
                    logError("Accessibility: \(axGranted), InputMonitoring: \(imGranted)")
                    
                    // Show more aggressive alert about permissions
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.showPermissionTroubleshootingAlert()
                    }
                } else {
                    logError("Permissions OK but engine still failed. Possible event tap issue.")
                    scheduleRetry()
                }
            } else {
                logInfo("BabylonFish 3.0 started successfully!")
                
                // Show success notification
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.statusBarController?.showNotification(
                        title: "BabylonFish 3.0 запущен! 🎉",
                        message: "Теперь приложение будет автоматически переключать раскладку и исправлять опечатки."
                    )
                }
                
                scheduleEventsCheck()
            }
        } catch {
            logError(error, context: "Failed to start app logic")
            // Show error to user
            DispatchQueue.main.async {
                self.showErrorAlert(
                    title: "Ошибка запуска BabylonFish",
                    message: "Не удалось запустить приложение: \(error.localizedDescription)"
                )
            }
        }
    }
    
    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func scheduleRetry() {
        logDebug("=== ПЛАНИРОВАНИЕ ПОВТОРНОЙ ПРОВЕРКИ ===")
        
        // Защита от слишком частых планирований
        struct RetryLock {
            static var isScheduling = false
            static var lastScheduleTime: Date?
        }
        
        let now = Date()
        if let lastSchedule = RetryLock.lastScheduleTime, now.timeIntervalSince(lastSchedule) < 1.0 {
            logDebug("⚠️ СЛИШКОМ ЧАСТОЕ ПЛАНИРОВАНИЕ ПОВТОРНОЙ ПРОВЕРКИ, пропускаем")
            return
        }
        
        if RetryLock.isScheduling {
            logDebug("⚠️ ПЛАНИРОВАНИЕ УЖЕ ВЫПОЛНЯЕТСЯ, пропускаем")
            return
        }
        
        RetryLock.isScheduling = true
        RetryLock.lastScheduleTime = now
        
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                RetryLock.isScheduling = false
            }
        }
        
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            logDebug("=== ВЫПОЛНЕНИЕ ПОВТОРНОЙ ПРОВЕРКИ ===")
            
            // Проверяем права
            let axGranted = self.hasAccessibility(prompt: false)
            let imGranted = self.hasInputMonitoring()
            
            logDebug("✅ Проверка прав: Доступность=\(axGranted), Мониторинг ввода=\(imGranted)")
            
            if axGranted && imGranted {
                // Все права получены, пытаемся запустить
                logDebug("✅ Все права получены, пытаемся запустить движок...")
                
                if let engine = self.babylonFishEngine {
                    do {
                        try engine.start()
                        logDebug("✅ Движок успешно запущен!")
                        self.retryTimer?.invalidate()
                        self.retryTimer = nil
                        return
                    } catch {
                        logDebug("❌ Ошибка запуска движка: \(error)")
                    }
                } else {
                    // Если движок еще не создан, создаем и запускаем
                    logDebug("⚠️ Движок не создан, создаем...")
                    self.startAppLogic()
                    self.retryTimer?.invalidate()
                    self.retryTimer = nil
                    return
                }
            } else {
                // Недостаточно прав
                logDebug("⚠️ Недостаточно прав: Доступность=\(axGranted), Мониторинг ввода=\(imGranted)")
                
                // Проверяем статистику событий для диагностики
                let stats = self.babylonFishEngine?.getAllStatistics() ?? [:]
                if let etm = stats["eventTapManager"] as? [String: Any],
                   let processed = etm["eventsProcessed"] as? Int,
                   let running = etm["isRunning"] as? Bool,
                   running, processed == 0 {
                    logDebug("⚠️ ДИАГНОСТИКА: EventTapManager запущен, но событий не обработано")
                    
                    // Если движок запущен, но событий нет, возможно проблема с правами
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.runFixPermissionsScript()
                        self.openAccessibilitySettings()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.openInputMonitoringSettings()
                        }
                    }
                }
            }
            
            logDebug("=== ЗАВЕРШЕНИЕ ПОВТОРНОЙ ПРОВЕРКИ ===")
        }
        
        logDebug("✅ Таймер повторной проверки запланирован (интервал: 3.0 сек)")
    }
    
    @objc func openAccessibilitySettings() {
        logDebug("📱 Открываем настройки доступности...")
        
        do {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                logDebug("✅ URL доступности: \(url)")
                
                // Защита от зависаний при открытии URL
                DispatchQueue.main.async {
                    let success = NSWorkspace.shared.open(url)
                    if success {
                        logDebug("✅ Настройки доступности успешно открыты")
                    } else {
                        logDebug("❌ Не удалось открыть настройки доступности")
                    }
                    
                    // Планируем повторную проверку через 2 секунды
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.scheduleRetry()
                    }
                }
            } else {
                logDebug("❌ Не удалось создать URL для настроек доступности")
            }
        } catch {
            logDebug("❌ Ошибка при открытии настроек доступности: \(error)")
        }
    }
    
    @objc func openInputMonitoringSettings() {
        logDebug("📱 Открываем настройки мониторинга ввода...")
        
        do {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                logDebug("✅ URL мониторинга ввода: \(url)")
                
                // Защита от зависаний при открытии URL
                DispatchQueue.main.async {
                    let success = NSWorkspace.shared.open(url)
                    if success {
                        logDebug("✅ Настройки мониторинга ввода успешно открыты")
                    } else {
                        logDebug("❌ Не удалось открыть настройки мониторинга ввода")
                    }
                    
                    // Планируем повторную проверку через 2 секунды
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.scheduleRetry()
                    }
                }
            } else {
                logDebug("❌ Не удалось создать URL для настроек мониторинга ввода")
            }
        } catch {
            logDebug("❌ Ошибка при открытии настроек мониторинга ввода: \(error)")
        }
    }
    
    @objc func resetPermissionsFromMenu() {
        logDebug("=== ЗАПУСК СБРОСА ПРАВ ИЗ МЕНЮ ===")
        
        // Защита от повторных вызовов
        struct ResetLock {
            static var isResetting = false
            static var lastResetTime: Date?
        }
        
        let now = Date()
        if let lastReset = ResetLock.lastResetTime, now.timeIntervalSince(lastReset) < 2.0 {
            logDebug("⚠️ СЛИШКОМ ЧАСТЫЙ СБРОС ПРАВ, пропускаем")
            return
        }
        
        if ResetLock.isResetting {
            logDebug("⚠️ СБРОС ПРАВ УЖЕ ВЫПОЛНЯЕТСЯ, пропускаем")
            return
        }
        
        ResetLock.isResetting = true
        ResetLock.lastResetTime = now
        
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                ResetLock.isResetting = false
            }
        }
        
        // Запускаем в фоновом потоке для защиты от зависаний UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            logDebug("🚀 Запускаем безопасный скрипт сброса прав...")
            self.runFixPermissionsScript()
            
            // Открываем настройки с задержкой
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                logDebug("📱 Открываем настройки доступности...")
                self.openAccessibilitySettings()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    logDebug("📱 Открываем настройки мониторинга ввода...")
                    self.openInputMonitoringSettings()
                    
                    // Показываем уведомление пользователю
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.showResetCompleteNotification()
                    }
                }
            }
        }
        
        logDebug("✅ Сброс прав запущен безопасно")
    }
    
    private func showResetCompleteNotification() {
        let notification = NSUserNotification()
        notification.title = "BabylonFish 3.0"
        notification.informativeText = "Сброс прав выполнен. Проверьте настройки системы."
        notification.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default.deliver(notification)
        logDebug("📢 Уведомление о завершении сброса прав отправлено")
    }
    
    @objc func retryStartListener() {
        ensurePermissionsAndStart()
    }
    
    private func scheduleEventsCheck() {
        // Эта функция больше не используется, логика проверки событий интегрирована в scheduleRetry
        logDebug("⚠️ scheduleEventsCheck устарел, используйте scheduleRetry")
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
        let result = AXIsProcessTrustedWithOptions(options)
        logDebug("Accessibility check: prompt=\(prompt), result=\(result), bundleID=\(Bundle.main.bundleIdentifier ?? "unknown"), path=\(Bundle.main.bundlePath)")
        return result
    }
    
    private func hasInputMonitoring() -> Bool {
        // IOHIDCheckAccess returns:
        // 0 = kIOHIDAccessTypeNone (Denied)
        // 1 = kIOHIDAccessTypeMonitor (Granted)
        // 2 = kIOHIDAccessTypeModify (Granted + Modify, rare but valid)
        let status = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        
        // Log detailed status
        let statusDescription: String
        switch status.rawValue {
        case 0: statusDescription = "Denied (kIOHIDAccessTypeNone)"
        case 1: statusDescription = "Granted (kIOHIDAccessTypeMonitor)"
        case 2: statusDescription = "Granted+Modify (kIOHIDAccessTypeModify)"
        default: statusDescription = "Unknown (\(status.rawValue))"
        }
        
        logDebug("Input Monitoring check: status=\(statusDescription), bundleID=\(Bundle.main.bundleIdentifier ?? "unknown"), path=\(Bundle.main.bundlePath)")
        
        // Check all possible granted states
        let isGranted = status == kIOHIDAccessTypeGranted || status.rawValue == 1 || status.rawValue == 2
        logDebug("Input Monitoring granted: \(isGranted)")
        
        return isGranted
    }
    





    
    private func runFixPermissionsScript() {
        logDebug("=== Запуск безопасного скрипта сброса прав ===")
        
        // Сначала пробуем безопасный скрипт
        var scriptPath = "\(FileManager.default.currentDirectoryPath)/fix_permissions_safe.sh"
        
        // Проверяем наличие скрипта в Resources
        if let resourcePath = Bundle.main.path(forResource: "fix_permissions_safe", ofType: "sh") {
            scriptPath = resourcePath
        }
        
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            logDebug("❌ Скрипт сброса прав не найден: \(scriptPath)")
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Скрипт не найден"
                alert.informativeText = "Скрипт сброса прав не найден.\n\nСоздайте fix_permissions_safe.sh в текущей директории."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }
        
        logDebug("✅ Найден скрипт: \(scriptPath)")
        
        // Запускаем скрипт в фоновом потоке с защитой от зависаний
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = [scriptPath]
            
            // Настраиваем таймаут для защиты от зависаний
            let timeoutSeconds = 45.0
            let startTime = Date()
            
            do {
                logDebug("🚀 Запускаем скрипт с таймаутом \(timeoutSeconds) секунд...")
                try task.run()
                
                // Мониторим выполнение с таймаутом
                while task.isRunning {
                    let elapsed = Date().timeIntervalSince(startTime)
                    
                    if elapsed > timeoutSeconds {
                        logDebug("⚠️ Таймаут скрипта (\(timeoutSeconds) секунд)! Прерываем...")
                        task.terminate()
                        break
                    }
                    
                    Thread.sleep(forTimeInterval: 0.5)
                }
                
                task.waitUntilExit()
                let exitCode = task.terminationStatus
                
                if exitCode == 0 {
                    logDebug("✅ Скрипт успешно завершен (код: \(exitCode))")
                } else {
                    logDebug("⚠️ Скрипт завершен с кодом ошибки: \(exitCode)")
                }
                
            } catch {
                logDebug("❌ Ошибка запуска скрипта: \(error)")
            }
            
            // Планируем повторную проверку прав
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.scheduleRetry()
            }
        }
    }
}
