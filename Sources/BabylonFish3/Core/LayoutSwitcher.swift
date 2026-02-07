import Cocoa
import Carbon

/// Менеджер для переключения раскладок клавиатуры
class LayoutSwitcher {
    
    // Синглтон
    static let shared = LayoutSwitcher()
    
    // Системные API
    private let tisInstance = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    
    // Кэш раскладок
    private var availableLayouts: [KeyboardLayout] = []
    private var layoutCache: [String: KeyboardLayout] = [:] // sourceId → layout
    private var languageToLayoutMap: [Language: KeyboardLayout] = [:]
    
    // Текущее состояние
    private var currentLayout: KeyboardLayout?
    private var lastSwitchTime: Date?
    
    // Конфигурация
    private var isEnabled = true
    private var switchDelay: TimeInterval = 0.1 // Задержка между переключениями
    private var maxSwitchAttempts: Int = 3
    
    // Статистика
    private var totalSwitches: Int = 0
    private var successfulSwitches: Int = 0
    private var failedSwitches: Int = 0
    private var startTime: Date?
    
    private init() {
        loadAvailableLayouts()
        updateCurrentLayout()
        startTime = Date()
        
        logDebug("LayoutSwitcher initialized with \(availableLayouts.count) layouts")
    }
    
    // MARK: - Public API
    
    /// Получает текущую раскладку клавиатуры
    func getCurrentLayout() -> KeyboardLayout? {
        updateCurrentLayout()
        return currentLayout
    }
    
    /// Получает все доступные раскладки
    func getAvailableLayouts() -> [KeyboardLayout] {
        return availableLayouts
    }
    
    /// Переключает на указанную раскладку
    func switchToLayout(_ layout: KeyboardLayout) -> Bool {
        guard isEnabled else {
            logDebug("LayoutSwitcher is disabled")
            return false
        }
        
        // Проверяем задержку между переключениями
        if let lastSwitch = lastSwitchTime,
           Date().timeIntervalSince(lastSwitch) < switchDelay {
            logDebug("Switch too soon after last switch, delaying")
            return false
        }
        
        totalSwitches += 1
        
        // Пытаемся переключиться
        for attempt in 1...maxSwitchAttempts {
            logDebug("Switching to layout '\(layout.name)' (attempt \(attempt)/\(maxSwitchAttempts))")
            
            if performLayoutSwitch(layout) {
                successfulSwitches += 1
                lastSwitchTime = Date()
                currentLayout = layout
                
                logDebug("Successfully switched to layout '\(layout.name)'")
                return true
            }
            
            // Небольшая задержка между попытками
            if attempt < maxSwitchAttempts {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        
        failedSwitches += 1
        logDebug("Failed to switch to layout '\(layout.name)' after \(maxSwitchAttempts) attempts")
        return false
    }
    
    /// Переключает на раскладку для указанного языка
    func switchToLanguage(_ language: Language) -> Bool {
        guard let layout = getLayoutForLanguage(language) else {
            logDebug("No layout found for language: \(language)")
            return false
        }
        
        return switchToLayout(layout)
    }
    
    /// Получает раскладку для указанного языка
    func getLayoutForLanguage(_ language: Language) -> KeyboardLayout? {
        // Сначала проверяем кэш
        if let cached = languageToLayoutMap[language] {
            return cached
        }
        
        // Ищем подходящую раскладку
        for layout in availableLayouts {
            if layout.supportedLanguages.contains(language) {
                languageToLayoutMap[language] = layout
                return layout
            }
        }
        
        // Если не нашли точного совпадения, ищем по имени
        let languageName = language.rawValue.lowercased()
        for layout in availableLayouts {
            if layout.name.lowercased().contains(languageName) {
                languageToLayoutMap[language] = layout
                return layout
            }
        }
        
        return nil
    }
    
    /// Получает язык для указанной раскладки
    func getLanguageForLayout(_ layout: KeyboardLayout) -> Language? {
        // Возвращаем первый поддерживаемый язык
        return layout.supportedLanguages.first
    }
    
    /// Генерирует события клавиш для слова в указанном языке
    func getKeyEventsForWord(_ word: String, inLanguage language: Language) -> [KeyboardEvent] {
        var events: [KeyboardEvent] = []
        let timestamp = CGEventTimestamp(Date().timeIntervalSince1970 * 1_000_000)
        
        // Для каждого символа в слове создаем событие keyDown
        for (index, char) in word.enumerated() {
            // Получаем keyCode для символа в текущей раскладке
            // В реальной реализации нужно использовать mapping таблицы
            let keyCode = getKeyCodeForCharacter(char, inLanguage: language)
            
            let event = KeyboardEvent(
                keyCode: keyCode,
                unicodeString: String(char),
                flags: [],
                timestamp: timestamp + UInt64(index * 1000), // Небольшой offset для каждого символа
                eventType: .keyDown
            )
            
            events.append(event)
        }
        
        logDebug("Generated \(events.count) key events for word '\(word)' in \(language)")
        return events
    }
    
    /// Включает/выключает переключение раскладок
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        logDebug("LayoutSwitcher enabled: \(enabled)")
    }
    
    /// Получает статистику
    func getStatistics() -> [String: Any] {
        let uptime = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let successRate = totalSwitches > 0 ? Double(successfulSwitches) / Double(totalSwitches) : 0
        
        return [
            "isEnabled": isEnabled,
            "currentLayout": currentLayout?.name ?? "unknown",
            "availableLayouts": availableLayouts.count,
            "totalSwitches": totalSwitches,
            "successfulSwitches": successfulSwitches,
            "failedSwitches": failedSwitches,
            "successRate": successRate,
            "uptime": uptime,
            "lastSwitchTime": lastSwitchTime?.description ?? "never"
        ]
    }
    
    // MARK: - Private Methods
    
    private func loadAvailableLayouts() {
        availableLayouts.removeAll()
        layoutCache.removeAll()
        languageToLayoutMap.removeAll()
        
        // Получаем все доступные input sources
        let inputSourceNSArray = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        let inputSourceList = inputSourceNSArray as! [TISInputSource]
        
        for source in inputSourceList {
            guard let layout = createKeyboardLayout(from: source) else {
                continue
            }
            
            availableLayouts.append(layout)
            layoutCache[layout.sourceId] = layout
            
            logDebug("Loaded layout: \(layout.name) (ID: \(layout.sourceId))")
        }
        
        logDebug("Total layouts loaded: \(availableLayouts.count)")
    }
    
    private func createKeyboardLayout(from source: TISInputSource) -> KeyboardLayout? {
        guard let sourceId = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        
        let sourceIdString = Unmanaged<CFString>.fromOpaque(sourceId).takeUnretainedValue() as String
        
        // Получаем имя раскладки
        guard let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName),
              let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String? else {
            return nil
        }
        
        // Определяем поддерживаемые языки
        var supportedLanguages: [Language] = []
        
        // Пытаемся определить язык по имени раскладки
        let lowercasedName = name.lowercased()
        
        if lowercasedName.contains("russian") || lowercasedName.contains("кириллица") || lowercasedName.contains("русск") {
            supportedLanguages.append(.russian)
        }
        
        if lowercasedName.contains("english") || lowercasedName.contains("us") || lowercasedName.contains("англ") || lowercasedName.contains("латин") {
            supportedLanguages.append(.english)
        }
        
        // Если не определили язык, добавляем оба как fallback
        if supportedLanguages.isEmpty {
            supportedLanguages = [.english, .russian]
        }
        
        return KeyboardLayout(
            sourceId: sourceIdString,
            name: name,
            supportedLanguages: supportedLanguages,
            inputSource: source
        )
    }
    
    private func updateCurrentLayout() {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return
        }
        
        // Ищем раскладку в кэше
        if let sourceId = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) {
            let sourceIdString = Unmanaged<CFString>.fromOpaque(sourceId).takeUnretainedValue() as String
            
            if let cachedLayout = layoutCache[sourceIdString] {
                currentLayout = cachedLayout
                return
            }
        }
        
        // Создаем новую раскладку
        if let newLayout = createKeyboardLayout(from: currentSource) {
            currentLayout = newLayout
            layoutCache[newLayout.sourceId] = newLayout
            
            // Добавляем в availableLayouts если еще нет
            if !availableLayouts.contains(where: { $0.sourceId == newLayout.sourceId }) {
                availableLayouts.append(newLayout)
            }
        }
    }
    
    private func performLayoutSwitch(_ layout: KeyboardLayout) -> Bool {
        let inputSource = layout.inputSource
        
        // Пытаемся переключить раскладку
        let result = TISSelectInputSource(inputSource)
        
        if result == noErr {
            // Даем системе время на переключение
            Thread.sleep(forTimeInterval: 0.01)
            
            // Проверяем, что переключение произошло
            updateCurrentLayout()
            
            if currentLayout?.sourceId == layout.sourceId {
                return true
            }
        }
        
        logDebug("TISSelectInputSource failed with error: \(result)")
        return false
    }
    
    private func getKeyCodeForCharacter(_ character: Character, inLanguage language: Language) -> Int {
        // Упрощенная реализация
        // В реальном приложении нужно использовать mapping таблицы для каждой раскладки
        
        let char = String(character).lowercased()
        
        // Базовый mapping для QWERTY раскладки
        let qwertyMapping: [String: Int] = [
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
            "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31,
            "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9,
            "w": 13, "x": 7, "y": 16, "z": 6,
            " ": 49, ".": 47, ",": 43, "!": 44, "?": 44, ";": 41, ":": 41,
            "(": 44, ")": 44, "[": 33, "]": 30, "{": 33, "}": 30, "<": 43,
            ">": 47, "\"": 39, "'": 39, "-": 27, "=": 24, "`": 50,
            "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26,
            "8": 28, "9": 25, "0": 29
        ]
        
        // Для русского языка используем ту же раскладку, но с другими символами
        // В реальности нужно proper mapping для русской раскладки
        if language == .russian {
            // Упрощенный mapping для русских букв на той же раскладке
            let russianMapping: [String: Int] = [
                "а": 0, "б": 11, "в": 9, "г": 5, "д": 2, "е": 14, "ё": 50,
                "ж": 6, "з": 7, "и": 34, "й": 16, "к": 40, "л": 37, "м": 46,
                "н": 45, "о": 31, "п": 35, "р": 15, "с": 1, "т": 17, "у": 32,
                "ф": 3, "х": 4, "ц": 8, "ч": 38, "ш": 41, "щ": 44, "ъ": 39,
                "ы": 30, "ь": 43, "э": 27, "ю": 47, "я": 12
            ]
            
            if let keyCode = russianMapping[char] {
                return keyCode
            }
        }
        
        // Возвращаем QWERTY mapping или fallback
        return qwertyMapping[char] ?? 0 // 0 = 'A' key как fallback
    }
    
    deinit {
        logDebug("LayoutSwitcher deinitialized")
    }
}

// MARK: - Вспомогательные структуры

/// Раскладка клавиатуры
struct KeyboardLayout {
    let sourceId: String
    let name: String
    let supportedLanguages: [Language]
    let inputSource: TISInputSource
    
    var description: String {
        return "\(name) (\(supportedLanguages.map { $0.rawValue }.joined(separator: ", ")))"
    }
}

// MARK: - Расширения для сравнения

extension KeyboardLayout: Equatable {
    static func == (lhs: KeyboardLayout, rhs: KeyboardLayout) -> Bool {
        return lhs.sourceId == rhs.sourceId
    }
}

extension KeyboardLayout: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(sourceId)
    }
}