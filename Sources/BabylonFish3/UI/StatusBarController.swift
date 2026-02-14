import Cocoa
import SwiftUI

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: EventMonitor?
    private var engine: BabylonFishEngine?
    
    init(engine: BabylonFishEngine?) {
        self.engine = engine
        super.init()
        
        setupStatusBar()
        setupPopover()
        setupEventMonitor()
    }

    func updateEngine(_ engine: BabylonFishEngine?) {
        self.engine = engine
        updateStatusBarIcon()
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "BabylonFish 3.0")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        updateStatusBarIcon()
        setupMenu()
    }
    
    private func setupPopover() {
        popover = NSPopover()
        
        // Create a simple settings view for now
        let settingsView = Text("Настройки BabylonFish 3.0\n\nЗдесь будет интерфейс настроек")
            .padding()
            .frame(width: 300, height: 200)
        
        let hostingController = NSHostingController(rootView: settingsView)
        
        popover.contentSize = NSSize(width: 400, height: 500)
        popover.behavior = .transient
        popover.contentViewController = hostingController
    }
    
    private func setupEventMonitor() {
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let strongSelf = self, strongSelf.popover.isShown {
                strongSelf.closePopover(sender: event)
            }
        }
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender: sender)
        } else {
            showPopover(sender: sender)
        }
    }
    
    func showPopover(sender: AnyObject?) {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            eventMonitor?.start()
        }
    }
    
    func closePopover(sender: AnyObject?) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }
    
    func updateStatusBarIcon() {
        guard let button = statusItem.button else { return }
        
        let isEnabled = engine?.currentConfig.exceptions.globalEnabled ?? true
        
        if isEnabled {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "BabylonFish 3.0 (Enabled)")
            button.image?.isTemplate = true
        } else {
            button.image = NSImage(systemSymbolName: "keyboard.slash", accessibilityDescription: "BabylonFish 3.0 (Disabled)")
            button.image?.isTemplate = true
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Добавляем информацию о версии и пути
        let versionInfo = getVersionInfo()
        let versionItem = NSMenuItem(title: versionInfo, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let openPerms = NSMenuItem(title: "Открыть настройки разрешений", action: #selector(openPermissions), keyEquivalent: "")
        openPerms.target = self
        menu.addItem(openPerms)
        
        let resetPerms = NSMenuItem(title: "Сбросить права (TCC)", action: #selector(resetPermissions), keyEquivalent: "")
        resetPerms.target = self
        menu.addItem(resetPerms)
        
        menu.addItem(NSMenuItem.separator())
        
        let quit = NSMenuItem(title: "Выход", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        
        statusItem.menu = menu
    }
    
    private func getVersionInfo() -> String {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "3.0.0"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        let bundlePath = bundle.bundlePath
        
        // Получаем дату сборки из файла ресурсов или текущую дату
        var buildDate = "unknown"
        if let resourcesPath = bundle.path(forResource: "build_info", ofType: "txt"),
           let buildInfo = try? String(contentsOfFile: resourcesPath, encoding: .utf8) {
            // Парсим дату из файла build_info.txt
            let lines = buildInfo.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("Дата:") {
                    let components = line.components(separatedBy: "Дата:")
                    if components.count > 1 {
                        buildDate = components[1].trimmingCharacters(in: .whitespaces)
                    }
                    break
                }
            }
        }
        
        // Форматируем путь для отображения
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
        
        if buildDate != "unknown" {
            return "BabylonFish v\(version) (\(build)) - \(formattedPath)\nСборка: \(buildDate)"
        } else {
            return "BabylonFish v\(version) (\(build)) - \(formattedPath)"
        }
    }
    
    @objc private func openPermissions() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.openAccessibilitySettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                appDelegate.openInputMonitoringSettings()
            }
        }
    }
    
    @objc private func resetPermissions() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.resetPermissionsFromMenu()
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    func showNotification(title: String, message: String) {
        DispatchQueue.main.async {
            // Всегда используем fallback метод, так как UNUserNotificationCenter
            // может вызывать исключения в контексте приложения без бандла
            self.showFallbackNotification(title: title, message: message)
        }
    }
    
    private func showFallbackNotification(title: String, message: String) {
        // Fallback метод для показа уведомлений
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default.deliver(notification)
    }
}

class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void
    
    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    
    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
