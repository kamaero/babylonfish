import Foundation
import Cocoa

/// Обрабатывает двойное нажатие Shift
class DoubleShiftHandler {
    private var config: HotkeyConfig
    private var lastNotificationTime: TimeInterval = 0
    private let notificationCooldown: TimeInterval = 1.0
    
    init(config: HotkeyConfig) {
        self.config = config
    }
    
    /// Обрабатывает событие двойного Shift
    func handleDoubleShift() {
        guard config.doubleShiftEnabled else {
            logDebug("Double shift ignored (disabled in config)")
            return
        }
        
        let now = Date().timeIntervalSince1970
        if now - lastNotificationTime < notificationCooldown {
            logDebug("Double shift ignored (cooldown)")
            return
        }
        lastNotificationTime = now
        
        logDebug("Double shift detected, showing notification...")
        showNotification()
        
        // TODO: Реализовать другие действия в зависимости от конфигурации
        // (переключение режима, открытие панели быстрого исправления и т.д.)
    }
    
    /// Показывает уведомление о двойном Shift
    private func showNotification() {
        DispatchQueue.main.async {
            let notification = NSUserNotification()
            notification.title = "BabylonFish 🐠"
            notification.informativeText = "Double Shift detected"
            notification.soundName = NSUserNotificationDefaultSoundName
            
            NSUserNotificationCenter.default.deliver(notification)
        }
    }
    
    /// Обновляет конфигурацию
    func updateConfig(_ newConfig: HotkeyConfig) {
        config = newConfig
        logDebug("DoubleShiftHandler config updated")
    }
}