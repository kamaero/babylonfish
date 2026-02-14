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
    private var tapReenableAttempts = 0
    private let maxTapReenableAttempts = 3
    private var lastTapReenableTime: TimeInterval = 0
    
    // Конфигурация
    private let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
    private let tapLocation: CGEventTapLocation = .cgSessionEventTap
    
    // Зависимости
    private weak var eventProcessor: EventProcessor?
    
    // Статистика
    private var eventsProcessed: Int = 0
    private var eventsBlocked: Int = 0
    private var startTime: Date?
    
    // Защита от рекурсии
    private var isSendingEvents = false
    
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
        
        // If Input Monitoring is missing, we must use fallback
        if !imOk {
            startFallback()
            isRunning = true
            startTime = Date()
            logDebug("EventTapManager started in fallback mode (Input Monitoring missing)")
            return true
        }
        
        // If Accessibility is missing, we warn but proceed with Event Tap
        if !axOk {
            logDebug("Warning: Accessibility missing. Context checks will fail, but Event Tap will work.")
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
        tapReenableAttempts = 0 // Сбрасываем счетчик при успешном старте
        
        logDebug("EventTapManager started successfully")
        
        // Запускаем watchdog
        startWatchdog()
        
        return true
    }
    
    /// Останавливает захват событий
    func stop() {
        stopWatchdog()
        guard isRunning else { return }

        if let monitor = fallbackMonitor {
            NSEvent.removeMonitor(monitor)
            fallbackMonitor = nil
            logDebug("Fallback monitor stopped")
        }
        
        guard let tap = eventTap else {
            isRunning = false
            return
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
        // Защита от слишком частых событий
        let now = Date().timeIntervalSince1970
        let timeSinceLastEvent = now - lastEventTime
        
        // Если события приходят слишком часто (менее 1ms), пропускаем для защиты от зависаний
        if timeSinceLastEvent < 0.001 && eventsProcessed > 100 {
            logDebug("⚠️ СЛИШКОМ ЧАСТЫЕ СОБЫТИЯ: пропускаем для защиты от зависаний")
            return Unmanaged.passUnretained(event)
        }
        
        eventsProcessed += 1
        lastEventTime = now
        
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let timeSinceLastReenable = now - lastTapReenableTime
            
            // Ограничиваем попытки повторного включения
            if tapReenableAttempts >= maxTapReenableAttempts && timeSinceLastReenable < 5.0 {
                logDebug("⚠️ СЛИШКОМ МНОГО ПОПЫТОК повторного включения (\(tapReenableAttempts)), ждем...")
                return Unmanaged.passUnretained(event)
            }
            
            logDebug("⚠️ Event tap отключен системой (type=\(type.rawValue)). Повторно включаем... (попытка \(tapReenableAttempts + 1)/\(maxTapReenableAttempts))")
            
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                tapReenableAttempts += 1
                lastTapReenableTime = now
                
                // Если слишком много попыток, переключаемся в fallback mode
                if tapReenableAttempts >= maxTapReenableAttempts {
                    logDebug("⚠️ СЛИШКОМ МНОГО ОШИБОК повторного включения, переключаемся в fallback mode")
                    DispatchQueue.main.async { [weak self] in
                        self?.stop()
                        self?.startFallback()
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        
        // Пропускаем системные события
        if shouldIgnoreEvent(type: type, event: event) {
            return Unmanaged.passUnretained(event)
        }
        
        // Обрабатываем событие с защитой от зависаний
        let shouldBlock: Bool
        do {
            // Используем try для защиты от исключений
            shouldBlock = try processEvent(type: type, event: event)
        } catch {
            logDebug("❌ ОШИБКА обработки события: \(error)")
            shouldBlock = false
        }
        
        if shouldBlock {
            eventsBlocked += 1
            return nil // Блокируем событие
        }
        
        return Unmanaged.passUnretained(event) // Пропускаем событие
    }
    
    private func startFallback() {
        logDebug("Starting fallback event monitor...")
        fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] ev in
            guard let self else { return }
            guard let processor = self.eventProcessor else { return }
            
            let keyCode = Int(ev.keyCode)
            let chars = ev.characters ?? ""
            let flags = ev.modifierFlags
            
            logDebug("Fallback monitor captured event: type=\(ev.type.rawValue), keyCode=\(keyCode), chars='\(chars)', flags=\(flags.rawValue)")
            
            let kbEvent = KeyboardEvent(
                keyCode: keyCode,
                unicodeString: chars,
                flags: CGEventFlags(rawValue: UInt64(flags.rawValue)),
                timestamp: CGEventTimestamp(Date().timeIntervalSince1970 * 1_000_000),
                eventType: ev.type == .flagsChanged ? .flagsChanged : .keyDown
            )
            
            let result = processor.processEvent(kbEvent)
            logDebug("Fallback processing result: eventsToSend=\(result.eventsToSend.count), shouldSwitch=\(result.shouldSwitchLayout), language=\(String(describing: result.detectedLanguage))")
            
            if !result.eventsToSend.isEmpty {
                self.sendEvents(result.eventsToSend)
            }
        }
        
        if fallbackMonitor != nil {
            logDebug("Fallback monitor started successfully")
        } else {
            logDebug("ERROR: Failed to create fallback monitor")
        }
    }
    
    private func shouldIgnoreEvent(type: CGEventType, event: CGEvent) -> Bool {
        // Игнорируем события от самого BabylonFish
        let sourcePid = event.getIntegerValueField(.eventSourceUserData)
        let currentPid = Int64(getpid())
        
        if sourcePid == currentPid {
            logDebug("Ignoring event from BabylonFish (PID: \(sourcePid) == \(currentPid))")
            return true
        }
        
        logDebug("Event source PID: \(sourcePid), BabylonFish PID: \(currentPid), type: \(type.rawValue)")
        
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
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
    
    private func processEvent(type: CGEventType, event: CGEvent) throws -> Bool {
        guard let processor = eventProcessor else {
            logDebug("No EventProcessor set")
            return false
        }
        
        // Конвертируем CGEvent в нашу структуру
        let keyboardEvent = try convertCGEventToKeyboardEvent(event)
        
        // Обрабатываем событие
        let result = processor.processEvent(keyboardEvent)
        
        // Если нужно отправить новые события
        if !result.eventsToSend.isEmpty {
            var eventsToSend = result.eventsToSend
            // Если исходное событие содержит разделитель (unicodeString не пуст), добавим его в конец,
            // чтобы сохранить границу слова (например, пробел или пунктуацию)
            if let unicode = event.getUnicodeString(), !unicode.isEmpty {
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                let downEvent = KeyboardEvent(
                    keyCode: keyCode,
                    unicodeString: unicode,
                    flags: event.flags,
                    timestamp: 0,
                    eventType: .keyDown
                )
                let upEvent = KeyboardEvent(
                    keyCode: keyCode,
                    unicodeString: "",
                    flags: event.flags,
                    timestamp: 0,
                    eventType: .keyUp
                )
                eventsToSend.append(downEvent)
                eventsToSend.append(upEvent)
            }
            
            logDebug("Calling sendEvents with \(eventsToSend.count) events")
            sendEvents(eventsToSend)
            logDebug("sendEvents completed, blocking original event")
            return true // Блокируем оригинальное событие
        }
        
        // Если нужно заблокировать оригинальное событие (без отправки новых событий)
        if result.shouldBlockOriginalEvent {
            logDebug("Blocking original event without sending new events: \(keyboardEvent)")
            return true
        }
        
        return false
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
        logDebug("=== SEND EVENTS START: \(events.count) events ===")
        
        if events.isEmpty {
            logDebug("No events to send")
            return
        }
        
        // Защита от рекурсии: если мы уже отправляем события, не обрабатываем новые
        if isSendingEvents {
            logDebug("⚠️ RECURSION DETECTED: Already sending events, skipping")
            return
        }
        
        // Ограничиваем количество событий для защиты от зависаний
        let maxEvents = 20
        let eventsToSend = Array(events.prefix(maxEvents))
        
        if events.count > maxEvents {
            logDebug("⚠️ СЛИШКОМ МНОГО СОБЫТИЙ: \(events.count) > \(maxEvents), отправляем только первые \(maxEvents)")
        }
        
        isSendingEvents = true
        defer { isSendingEvents = false }
        
        // Устанавливаем source PID для всех событий как PID BabylonFish
        let currentPid = Int64(getpid())
        
        // Таймаут для защиты от зависаний
        let startTime = Date()
        let timeoutSeconds = 5.0
        
        for (index, event) in eventsToSend.enumerated() {
            // Проверяем таймаут
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > timeoutSeconds {
                logDebug("⚠️ ТАЙМАУТ: Отправка событий превысила \(timeoutSeconds) секунд, прерываем")
                break
            }
            
            do {
                logDebug("[\(index+1)/\(eventsToSend.count)] Converting event: keyCode=\(event.keyCode), unicode='\(event.unicodeString)', type=\(event.eventType)")
                let cgEvent = try convertKeyboardEventToCGEvent(event)
                
                // Устанавливаем source PID как PID BabylonFish, чтобы shouldIgnoreEvent мог их игнорировать
                cgEvent.setIntegerValueField(.eventSourceUserData, value: currentPid)
                
                let sourcePid = cgEvent.getIntegerValueField(.eventSourceUserData)
                logDebug("[\(index+1)/\(eventsToSend.count)] Created CGEvent with source PID: \(sourcePid)")
                
                logDebug("[\(index+1)/\(eventsToSend.count)] Posting to .cgSessionEventTap...")
                
                // Защита от зависаний при отправке
                var postSuccess = false
                let postTimeout = 0.1 // 100ms таймаут на отправку
                
                DispatchQueue.global(qos: .userInitiated).async {
                    cgEvent.post(tap: .cgSessionEventTap)
                    postSuccess = true
                }
                
                // Ждем завершения отправки с таймаутом
                let postStart = Date()
                while !postSuccess && Date().timeIntervalSince(postStart) < postTimeout {
                    Thread.sleep(forTimeInterval: 0.001) // 1ms
                }
                
                if postSuccess {
                    logDebug("[\(index+1)/\(eventsToSend.count)] ✅ POSTED synthetic event")
                } else {
                    logDebug("[\(index+1)/\(eventsToSend.count)] ⚠️ ТАЙМАУТ отправки события")
                }
                
                // Небольшая задержка между событиями для стабильности
                if index < eventsToSend.count - 1 {
                    usleep(2000) // 2ms задержка для стабильности
                }
            } catch {
                logDebug("❌ Error sending event \(index+1): \(error)")
            }
        }
        
        logDebug("=== SEND EVENTS COMPLETE: \(eventsToSend.count)/\(events.count) events sent ===")
    }
    
    private func convertKeyboardEventToCGEvent(_ event: KeyboardEvent) throws -> CGEvent {
        logDebug("Converting KeyboardEvent to CGEvent: keyCode=\(event.keyCode), unicode='\(event.unicodeString)', type=\(event.eventType)")
        
        let keyDown = event.eventType != .keyUp
        guard let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(event.keyCode), keyDown: keyDown) else {
            logDebug("❌ Failed to create CGEvent for keyCode: \(event.keyCode), keyDown: \(keyDown)")
            throw EventTapError.failedToCreateEvent
        }
        
        logDebug("CGEvent created successfully")
        cgEvent.flags = event.flags
        
        if event.timestamp > 0 {
            cgEvent.timestamp = event.timestamp
        }
        
        // Устанавливаем unicode string если есть
        if keyDown && !event.unicodeString.isEmpty {
            let string = event.unicodeString as NSString
            let length = string.length
            var characters = [UniChar](repeating: 0, count: length)
            string.getCharacters(&characters, range: NSRange(location: 0, length: length))
            
            logDebug("Setting unicode string: '\(event.unicodeString)' (length: \(length))")
            cgEvent.keyboardSetUnicodeString(stringLength: length, unicodeString: &characters)
        }
        
        // Помечаем как событие от BabylonFish
        let pid = Int64(getpid())
        cgEvent.setIntegerValueField(.eventSourceUserData, value: pid)
        logDebug("Set source PID: \(pid)")
        
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
        
        // Log detailed status
        let statusDescription: String
        switch access.rawValue {
        case 0: statusDescription = "Denied (kIOHIDAccessTypeNone)"
        case 1: statusDescription = "Granted (kIOHIDAccessTypeMonitor)"
        case 2: statusDescription = "Granted+Modify (kIOHIDAccessTypeModify)"
        default: statusDescription = "Unknown (\(access.rawValue))"
        }
        
        // Check all possible granted states
        let granted = access == kIOHIDAccessTypeGranted || access.rawValue == 1 || access.rawValue == 2
        logDebug("Input Monitoring check: \(granted ? "granted" : "denied") (access=\(statusDescription))")
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
    let detectedLanguage: Language?
    let shouldSwitchLayout: Bool
    
    static let `default` = EventProcessingResult(
        shouldBlockOriginalEvent: false, 
        eventsToSend: [],
        detectedLanguage: nil,
        shouldSwitchLayout: false
    )
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
