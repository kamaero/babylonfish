import Cocoa
import Carbon

/// Менеджер для захвата и обработки событий клавиатуры
class EventTapManager {
    
    // Синглтон
    static let shared = EventTapManager()
    
    // Состояние
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false
    private var isEnabled = true
    private var fallbackMonitor: Any?
    private var watchdogTimer: Timer?
    private var lastEventTime: TimeInterval = 0
    
    // Конфигурация
    private let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
    private let tapLocation: CGEventTapLocation = .cgSessionEventTap
    
    // Зависимости
    private weak var eventProcessor: EventProcessor?
    
    // Статистика
    private var eventsProcessed: Int = 0
    private var eventsBlocked: Int = 0
    private var startTime: Date?
    
    private init() {
        logDebug("EventTapManager initialized")
    }
    
    // MARK: - Public API
    
    /// Запускает захват событий
    func start() -> Bool {
        guard !isRunning else {
            logDebug("EventTapManager is already running")
            return false
        }
        
        guard isEnabled else {
            logDebug("EventTapManager is disabled")
            return false
        }
        
        // Проверяем permissions
        let axOk = checkAccessibilityPermissions()
        let imOk = checkInputMonitoringPermissions()
        if !axOk || !imOk {
            startFallback()
            isRunning = true
            startTime = Date()
            logDebug("EventTapManager started in fallback mode")
            return true
        }
        
        // Создаем event tap
        guard let tap = createEventTap() else {
            startFallback()
            isRunning = true
            startTime = Date()
            logDebug("EventTapManager started in fallback mode (tapCreate failed)")
            return true
        }
        
        eventTap = tap
        isRunning = true
        startTime = Date()
        
        logDebug("EventTapManager started successfully")
        
        // Запускаем watchdog
        startWatchdog()
        
        return true
    }
    
    /// Останавливает захват событий
    func stop() {
        stopWatchdog()
        
        guard isRunning, let tap = eventTap else { return }
            if let monitor = fallbackMonitor {
                NSEvent.removeMonitor(monitor)
                fallbackMonitor = nil
                isRunning = false
                logDebug("Fallback monitor stopped")
            }
        
        // Удаляем run loop source
        
        // Удаляем run loop source
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        
        // Отключаем event tap
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        
        eventTap = nil
        isRunning = false
        
        logDebug("EventTapManager stopped")
    }
    
    /// Включает/выключает захват событий
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        
        if !enabled && isRunning {
            stop()
        }
        
        logDebug("EventTapManager enabled: \(enabled)")
    }
    
    /// Устанавливает обработчик событий
    func setEventProcessor(_ processor: EventProcessor) {
        self.eventProcessor = processor
        logDebug("EventProcessor set")
    }
    
    /// Получает статистику
    func getStatistics() -> [String: Any] {
        let uptime = startTime.map { Date().timeIntervalSince($0) } ?? 0
        
        return [
            "isRunning": isRunning,
            "isEnabled": isEnabled,
            "eventsProcessed": eventsProcessed,
            "eventsBlocked": eventsBlocked,
            "uptime": uptime,
            "eventTapExists": eventTap != nil,
            "runLoopSourceExists": runLoopSource != nil
        ]
    }
    
    // MARK: - Private Methods
    
    private func startWatchdog() {
        stopWatchdog()
        DispatchQueue.main.async {
            self.watchdogTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.checkTapStatus()
            }
        }
    }
    
    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }
    
    private func checkTapStatus() {
        guard let tap = eventTap else { return }
        
        // Проверяем, включен ли tap
        let isTapEnabled = CGEvent.tapIsEnabled(tap: tap)
        if !isTapEnabled {
            logDebug("WATCHDOG: Event tap was disabled! Re-enabling...")
            CGEvent.tapEnable(tap: tap, enable: true)
            let isNowEnabled = CGEvent.tapIsEnabled(tap: tap)
            logDebug("WATCHDOG: Re-enable result: \(isNowEnabled)")
        }
    }

    private func createEventTap() -> CFMachPort? {
        logDebug("Creating event tap with mask: \(eventMask)")
        
        // Создаем callback для обработки событий
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            let manager = Unmanaged<EventTapManager>.fromOpaque(refcon!).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }
        
        // Создаем event tap
        guard let tap = CGEvent.tapCreate(
            tap: tapLocation,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logDebug("CGEvent.tapCreate failed")
            return nil
        }
        
        // Создаем run loop source
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        
        // Включаем tap
        CGEvent.tapEnable(tap: tap, enable: true)
        
        if !CGEvent.tapIsEnabled(tap: tap) {
            logDebug("WARNING: Tap created but not enabled. Retrying enable...")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        
        logDebug("Event tap created successfully. Enabled: \(CGEvent.tapIsEnabled(tap: tap))")
        return tap
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        eventsProcessed += 1
        lastEventTime = Date().timeIntervalSince1970
        
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logDebug("WARNING: Event tap disabled by system (type=\(type.rawValue)). Re-enabling...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        let unicodePreview = event.getUnicodeString() ?? ""
        logDebug("Event received: type=\(type.rawValue) unicode='\(unicodePreview)' flags=\(event.flags.rawValue)")
        
        // Пропускаем системные события
        if shouldIgnoreEvent(type: type, event: event) {
            return Unmanaged.passUnretained(event)
        }
        
        // Обрабатываем событие
        let shouldBlock = processEvent(type: type, event: event)
        
        if shouldBlock {
            eventsBlocked += 1
            return nil // Блокируем событие
        }
        
        return Unmanaged.passUnretained(event) // Пропускаем событие
    }
    
    private func startFallback() {
        fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] ev in
            guard let self else { return }
            guard let processor = self.eventProcessor else { return }
            let keyCode = Int(ev.keyCode)
            let chars = ev.characters ?? ""
            let flags = ev.modifierFlags
            let kbEvent = KeyboardEvent(
                keyCode: keyCode,
                unicodeString: chars,
                flags: CGEventFlags(rawValue: UInt64(flags.rawValue)),
                timestamp: CGEventTimestamp(Date().timeIntervalSince1970 * 1_000_000),
                eventType: ev.type == .flagsChanged ? .flagsChanged : .keyDown
            )
            let result = processor.processEvent(kbEvent)
            if !result.eventsToSend.isEmpty {
                self.sendEvents(result.eventsToSend)
            }
        }
    }
    
    private func shouldIgnoreEvent(type: CGEventType, event: CGEvent) -> Bool {
        // Игнорируем события от самого BabylonFish
        let sourcePid = event.getIntegerValueField(.eventSourceUserData)
        if sourcePid == Int64(getpid()) {
            return true
        }
        
        // Игнорируем системные модификаторы
        let flags = event.flags
        if flags.contains(.maskNonCoalesced) {
            return true
        }
        
        // Игнорируем определенные типы событий
        switch type {
        case .keyUp:
            // Для простоты обрабатываем только keyDown и flagsChanged
            return true
        default:
            break
        }
        
        return false
    }
    
    private func processEvent(type: CGEventType, event: CGEvent) -> Bool {
        guard let processor = eventProcessor else {
            logDebug("No EventProcessor set")
            return false
        }
        
        do {
            // Конвертируем CGEvent в нашу структуру
            let keyboardEvent = try convertCGEventToKeyboardEvent(event)
            
            // Обрабатываем событие
            let result = processor.processEvent(keyboardEvent)
            
            // Если нужно заблокировать оригинальное событие
            if result.shouldBlockOriginalEvent {
                logDebug("Blocking original event: \(keyboardEvent)")
                return true
            }
            
            // Если нужно отправить новые события
            if !result.eventsToSend.isEmpty {
                var eventsToSend = result.eventsToSend
                // Если исходное событие содержит разделитель (unicodeString не пуст), добавим его в конец,
                // чтобы сохранить границу слова (например, пробел или пунктуацию)
                if let unicode = event.getUnicodeString(), !unicode.isEmpty {
                    let boundaryEvent = KeyboardEvent(
                        keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                        unicodeString: unicode,
                        flags: event.flags,
                        timestamp: event.timestamp,
                        eventType: .keyDown
                    )
                    eventsToSend.append(boundaryEvent)
                }
                
                sendEvents(eventsToSend)
                return true // Блокируем оригинальное событие
            }
            
            return false
        } catch {
            logDebug("Error processing event: \(error)")
            return false
        }
    }
    
    private func convertCGEventToKeyboardEvent(_ event: CGEvent) throws -> KeyboardEvent {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        var unicodeString = event.getUnicodeString() ?? ""
        if unicodeString.isEmpty && event.type == .keyDown {
            unicodeString = translateKeyCodeToUnicode(Int(keyCode), flags: event.flags) ?? ""
        }
        
        let flags = event.flags
        let timestamp = event.timestamp
        let eventType: KeyboardEventType
        switch event.type {
        case .keyDown:
            eventType = .keyDown
        case .keyUp:
            eventType = .keyUp
        case .flagsChanged:
            eventType = .flagsChanged
        default:
            eventType = .keyDown
        }
        
        return KeyboardEvent(
            keyCode: Int(keyCode),
            unicodeString: unicodeString,
            flags: flags,
            timestamp: timestamp,
            eventType: eventType
        )
    }
    
    private func translateKeyCodeToUnicode(_ keyCode: Int, flags: CGEventFlags) -> String? {
        let inputSource = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let rawPtr = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = unsafeBitCast(rawPtr, to: CFData.self)
        guard let layoutPtr = CFDataGetBytePtr(data) else { return nil }
        let keyboardLayout: UnsafePointer<UCKeyboardLayout> = layoutPtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 }
        
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 8)
        var length: Int = 0
        
        let modifierState = carbonModifierState(flags)
        let result = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDown),
            modifierState,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )
        
        if result == noErr && length > 0 {
            return String(utf16CodeUnits: chars, count: length)
        }
        return nil
    }
    
    private func carbonModifierState(_ flags: CGEventFlags) -> UInt32 {
        var state: UInt32 = 0
        if flags.contains(.maskShift) { state |= UInt32(shiftKeyBit) }
        if flags.contains(.maskControl) { state |= UInt32(controlKeyBit) }
        if flags.contains(.maskAlternate) { state |= UInt32(optionKeyBit) }
        if flags.contains(.maskCommand) { state |= UInt32(cmdKeyBit) }
        return state
    }
    
    private func sendEvents(_ events: [KeyboardEvent]) {
        for event in events {
            do {
                let cgEvent = try convertKeyboardEventToCGEvent(event)
                cgEvent.post(tap: .cghidEventTap)
                logDebug("Sent synthetic event: \(event)")
            } catch {
                logDebug("Error sending event: \(error)")
            }
        }
    }
    
    private func convertKeyboardEventToCGEvent(_ event: KeyboardEvent) throws -> CGEvent {
        guard let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(event.keyCode), keyDown: true) else {
            throw EventTapError.failedToCreateEvent
        }
        
        cgEvent.flags = event.flags
        cgEvent.timestamp = event.timestamp
        
        // Устанавливаем unicode string если есть
        if !event.unicodeString.isEmpty {
            let string = event.unicodeString as NSString
            let length = string.length
            var characters = [UniChar](repeating: 0, count: length)
            string.getCharacters(&characters, range: NSRange(location: 0, length: length))
            
            cgEvent.keyboardSetUnicodeString(stringLength: length, unicodeString: &characters)
        }
        
        // Помечаем как событие от BabylonFish
        cgEvent.setIntegerValueField(.eventSourceUserData, value: Int64(getpid()))
        
        return cgEvent
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        // Проверяем, есть ли у приложения Accessibility permissions
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options = [checkOptPrompt: false]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        logDebug("Accessibility permissions: \(trusted ? "granted" : "not granted")")
        return trusted
    }
    
    private func checkInputMonitoringPermissions() -> Bool {
        // В macOS 10.15+ нужно Input Monitoring permission
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let granted = (access == kIOHIDAccessTypeGranted)
        logDebug("Input Monitoring check: \(granted ? "granted" : "denied") (access=\(access))")
        return granted
    }
    
    deinit {
        stop()
        logDebug("EventTapManager deinitialized")
    }
}

// MARK: - Вспомогательные структуры

/// Событие клавиатуры
struct KeyboardEvent {
    let keyCode: Int
    let unicodeString: String
    let flags: CGEventFlags
    let timestamp: CGEventTimestamp
    let eventType: KeyboardEventType
    
    var description: String {
        return "KeyboardEvent(keyCode: \(keyCode), unicode: '\(unicodeString)', flags: \(flags.rawValue))"
    }
}

/// Тип события клавиатуры
enum KeyboardEventType {
    case keyDown
    case keyUp
    case flagsChanged
}

/// Результат обработки события
struct EventProcessingResult {
    let shouldBlockOriginalEvent: Bool
    let eventsToSend: [KeyboardEvent]
    
    static let `default` = EventProcessingResult(shouldBlockOriginalEvent: false, eventsToSend: [])
}

/// Ошибки EventTapManager
enum EventTapError: Error {
    case invalidKeyCode
    case invalidUnicode
    case failedToCreateEvent
    case permissionDenied
}

// MARK: - Расширения для CGEvent

extension CGEvent {
    func getUnicodeString() -> String? {
        // Получаем unicode string из события
        let maxLength = 16
        var actualLength = 0
        var characters = [UniChar](repeating: 0, count: maxLength)
        
        keyboardGetUnicodeString(maxStringLength: maxLength, actualStringLength: &actualLength, unicodeString: &characters)
        
        guard actualLength > 0 else { return nil }
        
        return String(utf16CodeUnits: characters, count: actualLength)
    }
}
