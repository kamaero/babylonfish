import Cocoa

/// Точка входа BabylonFish 3.0
class BabylonFish3 {
    static func main() {
        // Инициализируем логгер
        logDebug("=== BabylonFish 3.0 Starting ===")
        logDebug("Date: \(Date())")
        logDebug("macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        
        // Создаем AppDelegate
        let delegate = AppDelegate()
        
        // Настраиваем NSApplication
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // Для приложения в меню баре
        
        // Запускаем приложение
        app.run()
    }
}

// Точка входа
BabylonFish3.main()