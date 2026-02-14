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
    
    /// Получает язык для раскладки
    func getLanguage(for layout: KeyboardLayout) -> Language? {
        return layout.supportedLanguages.first
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
        logDebug("getKeyEventsForWord called: word='\(word)', language=\(language)")
        
        // 1. Конвертируем слово в символы целевого языка
        let convertedWord = convertWordToLanguage(word, targetLanguage: language)
        logDebug("Converted word: '\(word)' → '\(convertedWord)' for language \(language)")
        
        var events: [KeyboardEvent] = []
        
        // 2. Для каждого символа в конвертированном слове создаем события
        for char in convertedWord {
            // Получаем keyCode для символа в целевой раскладке
            let keyCode = getKeyCodeForCharacter(char, inLanguage: language)
            
            logDebug("Character '\(char)' → keyCode: \(keyCode) for language \(language)")
            
            let downEvent = KeyboardEvent(
                keyCode: keyCode,
                unicodeString: String(char),
                flags: [],
                timestamp: 0,
                eventType: .keyDown
            )
            let upEvent = KeyboardEvent(
                keyCode: keyCode,
                unicodeString: "",
                flags: [],
                timestamp: 0,
                eventType: .keyUp
            )
            
            events.append(downEvent)
            events.append(upEvent)
        }
        
        logDebug("Generated \(events.count) key events for word '\(word)' (converted to '\(convertedWord)') in \(language)")
        return events
    }
    
    /// Конвертирует слово в символы целевого языка
    private func convertWordToLanguage(_ word: String, targetLanguage: Language) -> String {
        logDebug("Converting word '\(word)' to language \(targetLanguage)")
        
        // Используем KeyMapper для конвертации
        let converted = KeyMapper.shared.convertString(word)
        logDebug("KeyMapper conversion: '\(word)' → '\(converted)'")
        
        // Если конвертация не сработала (например, для цифр или символов),
        // возвращаем оригинальное слово
        if converted == word {
            logDebug("No conversion needed or conversion failed, returning original word")
            return word
        }
        
        // Проверяем, нужно ли конвертировать
        // Если слово уже выглядит как правильное слово в целевом языке,
        // возможно, оно уже в правильной раскладке
        // Для простоты возвращаем конвертированное слово
        // (основная логика проверки находится в EventProcessor)
        return converted
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
            supportedLanguages = [.english]
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
        let char = String(character).lowercased()
        
        // Маппинг символов на скан-коды (QWERTY / ЙЦУКЕН)
        // Коды соответствуют стандарту ANSI (US Keyboard)
        
        // English mapping (Character -> KeyCode)
        let enMapping: [String: Int] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
            "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
            "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
            "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
            "`": 50, " ": 49
        ]
        
        // Russian mapping (Character -> KeyCode)
        let ruMapping: [String: Int] = [
            "ф": 0, "ы": 1, "в": 2, "а": 3, "р": 4, "п": 5, "я": 6, "ч": 7, "с": 8, "м": 9,
            "и": 11, "й": 12, "ц": 13, "у": 14, "к": 15, "н": 16, "е": 17, "1": 18, "2": 19,
            "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
            "0": 29, "ъ": 30, "щ": 31, "г": 32, "х": 33, "ш": 34, "з": 35, "д": 37, "о": 38,
            "э": 39, "л": 40, "ж": 41, "ё": 50, "б": 43, ".": 44, "т": 45, "ь": 46, "ю": 47,
            " ": 49
        ]
        
        if language == .russian {
            if let code = ruMapping[char] { return code }
        } else {
            if let code = enMapping[char] { return code }
        }
        
        // Fallback checks for common punctuation that might be same
        if let code = enMapping[char] { return code }
        
        return 0 // Default fallback
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
