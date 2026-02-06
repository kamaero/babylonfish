import Foundation
import Cocoa
import Carbon

/// Управляет event tap и правами доступа
class EventTapManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private let eventProcessor: EventProcessor
    private let bufferManager: BufferManager
    private let layoutSwitcher: LayoutSwitcher
    
    private var startedAt: TimeInterval = 0
    private var keyDownEventsSeen = 0
    private var flagsChangedEventsSeen = 0
    private var reportedMissingKeyDown = false
    
    var isEnabled: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }
    
    init(eventProcessor: EventProcessor, bufferManager: BufferManager, layoutSwitcher: LayoutSwitcher) {
        self.eventProcessor = eventProcessor
        self.bufferManager = bufferManager
        self.layoutSwitcher = layoutSwitcher
    }
    
    /// Запускает event tap
    @discardableResult
    func start() -> Bool {
        logDebug("EventTapManager: Starting...")
        
        startedAt = Date().timeIntervalSince1970
        keyDownEventsSeen = 0
        flagsChangedEventsSeen = 0
        reportedMissingKeyDown = false
        
        // Маска для KeyDown и FlagsChanged
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        logDebug("EventTapManager: Creating event tap with mask: \(eventMask)")
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    logDebug("ERROR: refcon is nil in callback!")
                    return Unmanaged.passRetained(event)
                }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logDebug("CRITICAL: Failed to create event tap. Check Accessibility permissions.")
            return false
        }
        
        self.eventTap = eventTap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Включаем tap
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
        logDebug("Event tap created. Enabled status: \(isEnabled)")
        
        if !isEnabled {
            logDebug("WARNING: Tap was created but is not enabled! Trying to enable again...")
            CGEvent.tapEnable(tap: eventTap, enable: true)
            let isEnabledNow = CGEvent.tapIsEnabled(tap: eventTap)
            logDebug("After re-enable attempt: \(isEnabledNow)")
        }
        
        // Таймер для проверки статуса
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkTapStatus()
        }
        
        return true
    }
    
    /// Останавливает event tap
    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        logDebug("EventTapManager: Stopped")
    }
    
    /// Обрабатывает входящее событие
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logDebug("WARNING: Event tap disabled by system (type=\(type.rawValue)). Re-enabling...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        }
        
        logDebug("Event received: type=\(type.rawValue)")
        
        // Игнорируем события, сгенерированные нами
        if event.getIntegerValueField(.eventSourceUserData) == 0xBAB7 {
            logDebug("Ignoring synthesized event")
            return Unmanaged.passRetained(event)
        }
        
        switch type {
        case .flagsChanged:
            flagsChangedEventsSeen += 1
            eventProcessor.handleFlagsChanged(event)
            return Unmanaged.passRetained(event)
            
        case .keyDown:
            keyDownEventsSeen += 1
            return eventProcessor.handleKeyDown(event, proxy: proxy)
            
        default:
            return Unmanaged.passRetained(event)
        }
    }
    
    /// Проверяет статус event tap
    private func checkTapStatus() {
        guard let tap = eventTap else { return }
        let isEnabled = CGEvent.tapIsEnabled(tap: tap)
        if !isEnabled {
            logDebug("WARNING: Event tap was disabled by system! Re-enabling...")
            CGEvent.tapEnable(tap: tap, enable: true)
            let isEnabledNow = CGEvent.tapIsEnabled(tap: tap)
            logDebug("Re-enable result: \(isEnabledNow)")
        }

        let uptime = Date().timeIntervalSince1970 - startedAt
        if uptime >= 10, !reportedMissingKeyDown, flagsChangedEventsSeen > 0, keyDownEventsSeen == 0 {
            reportedMissingKeyDown = true
            logDebug("WARNING: flagsChanged events are received, but keyDown events are not. Check macOS Privacy & Security -> Input Monitoring for BabylonFish, and ensure Secure Input is not enabled by another app.")
        }
    }
}