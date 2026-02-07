import Foundation
import Cocoa

/// Сервис для работы с системным словарем macOS
class SystemDictionaryService {
    static let shared = SystemDictionaryService()
    
    private let spellChecker = NSSpellChecker.shared
    private let cacheManager = CacheManager.shared
    private let performanceMonitor = PerformanceMonitor.shared
    
    // Поддерживаемые языки
    private let supportedLanguages: [String: String] = [
        "en": "en_US",  // Английский (США)
        "ru": "ru_RU",  // Русский
        "uk": "uk_UA",  // Украинский
        "de": "de_DE",  // Немецкий
        "fr": "fr_FR",  // Французский
        "es": "es_ES",  // Испанский
    ]
    
    // Кэш для проверенных слов
    private var wordCache: [String: Bool] = [:]
    private var suggestionCache: [String: [String]] = [:]
    private var completionCache: [String: [String]] = [:]
    
    // Статистика
    private var checkCount: Int = 0
    private var suggestionCount: Int = 0
    private var completionCount: Int = 0
    
    private init() {
        setupNotifications()
    }
    
    // MARK: - Public API
    
    /// Проверяет орфографию слова
    func checkSpelling(_ word: String, languageCode: String = "en") -> Bool {
        performanceMonitor.startMeasurement("spellCheck")
        defer { performanceMonitor.endMeasurement("spellCheck") }
        
        checkCount += 1
        
        // Проверяем кэш
        let cacheKey = "\(languageCode):\(word.lowercased())"
        if let cachedResult = cacheManager.getCachedSpellingCheck(key: cacheKey) {
            performanceMonitor.recordCacheHit()
            return cachedResult
        }
        
        performanceMonitor.recordCacheMiss()
        
        // Получаем код языка
        guard let language = getLanguageCode(languageCode) else {
            logDebug("Unsupported language: \(languageCode)")
            return false
        }
        
        // Проверяем орфографию
        let range = spellChecker.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        
        let isValid = range.location == NSNotFound
        
        // Кэшируем результат
        cacheManager.cacheSpellingCheck(key: cacheKey, isValid: isValid)
        
        return isValid
    }
    
    /// Получает предложения по исправлению слова
    func getSuggestions(_ word: String, languageCode: String = "en") -> [String] {
        performanceMonitor.startMeasurement("getSuggestions")
        defer { performanceMonitor.endMeasurement("getSuggestions") }
        
        suggestionCount += 1
        
        // Проверяем кэш
        let cacheKey = "suggestions:\(languageCode):\(word.lowercased())"
        if let cachedSuggestions = suggestionCache[cacheKey] {
            performanceMonitor.recordCacheHit()
            return cachedSuggestions
        }
        
        performanceMonitor.recordCacheMiss()
        
        // Получаем код языка
        guard let language = getLanguageCode(languageCode) else {
            logDebug("Unsupported language: \(languageCode)")
            return []
        }
        
        // Получаем предложения
        let range = NSRange(location: 0, length: word.utf16.count)
        let suggestions = spellChecker.guesses(
            forWordRange: range,
            in: word,
            language: language,
            inSpellDocumentWithTag: 0
        ) ?? []
        
        // Фильтруем результаты
        let filteredSuggestions = filterSuggestions(suggestions, for: word)
        
        // Кэшируем результат
        suggestionCache[cacheKey] = filteredSuggestions
        
        return filteredSuggestions
    }
    
    /// Получает автодополнения для частичного слова
    func getCompletions(_ partialWord: String, languageCode: String = "en") -> [String] {
        performanceMonitor.startMeasurement("getCompletions")
        defer { performanceMonitor.endMeasurement("getCompletions") }
        
        completionCount += 1
        
        // Проверяем кэш
        let cacheKey = "completions:\(languageCode):\(partialWord.lowercased())"
        if let cachedCompletions = completionCache[cacheKey] {
            performanceMonitor.recordCacheHit()
            return cachedCompletions
        }
        
        performanceMonitor.recordCacheMiss()
        
        // Получаем код языка
        guard let language = getLanguageCode(languageCode) else {
            logDebug("Unsupported language: \(languageCode)")
            return []
        }
        
        // Получаем автодополнения
        let range = NSRange(location: 0, length: partialWord.utf16.count)
        let completions = spellChecker.completions(
            forPartialWordRange: range,
            in: partialWord,
            language: language,
            inSpellDocumentWithTag: 0
        ) ?? []
        
        // Фильтруем результаты
        let filteredCompletions = filterCompletions(completions, for: partialWord)
        
        // Кэшируем результат
        completionCache[cacheKey] = filteredCompletions
        
        return filteredCompletions
    }
    
    /// Получает лучшее исправление для слова
    func getBestCorrection(_ word: String, languageCode: String = "en") -> String? {
        let suggestions = getSuggestions(word, languageCode: languageCode)
        
        // Ищем лучшее исправление
        for suggestion in suggestions {
            // Проверяем, что исправление действительно лучше
            if isBetterCorrection(suggestion, than: word, languageCode: languageCode) {
                return suggestion
            }
        }
        
        return nil
    }
    
    /// Проверяет, доступен ли язык в системном словаре
    func isLanguageAvailable(_ languageCode: String) -> Bool {
        guard let language = getLanguageCode(languageCode) else {
            return false
        }
        
        return spellChecker.availableLanguages.contains(language)
    }
    
    /// Получает список доступных языков
    func getAvailableLanguages() -> [String] {
        return spellChecker.availableLanguages
    }
    
    /// Очищает кэш
    func clearCache() {
        wordCache.removeAll()
        suggestionCache.removeAll()
        completionCache.removeAll()
        cacheManager.clear(type: .spellingCheck)
    }
    
    /// Получает статистику
    func getStatistics() -> [String: Any] {
        return [
            "checkCount": checkCount,
            "suggestionCount": suggestionCount,
            "completionCount": completionCount,
            "wordCacheSize": wordCache.count,
            "suggestionCacheSize": suggestionCache.count,
            "completionCacheSize": completionCache.count,
            "availableLanguages": getAvailableLanguages()
        ]
    }
    
    // MARK: - Private Methods
    
    private func getLanguageCode(_ languageCode: String) -> String? {
        // Если передан полный код языка (например, "en_US"), используем его
        if languageCode.contains("_") {
            return languageCode
        }
        
        // Иначе ищем в поддерживаемых языках
        return supportedLanguages[languageCode]
    }
    
    private func filterSuggestions(_ suggestions: [String], for word: String) -> [String] {
        return suggestions.filter { suggestion in
            // Игнорируем слишком короткие предложения
            guard suggestion.count >= 2 else { return false }
            
            // Игнорируем предложения, которые отличаются только регистром
            guard suggestion.lowercased() != word.lowercased() else { return false }
            
            // Игнорируем предложения, которые слишком сильно отличаются
            let distance = levenshteinDistance(word, suggestion)
            guard distance <= max(3, word.count / 2) else { return false }
            
            return true
        }
    }
    
    private func filterCompletions(_ completions: [String], for partialWord: String) -> [String] {
        return completions.filter { completion in
            // Игнорируем слишком короткие дополнения
            guard completion.count > partialWord.count else { return false }
            
            // Проверяем, что дополнение начинается с partialWord
            guard completion.lowercased().hasPrefix(partialWord.lowercased()) else { return false }
            
            return true
        }
    }
    
    private func isBetterCorrection(_ correction: String, than original: String, languageCode: String) -> Bool {
        // Проверяем, что исправление является допустимым словом
        guard checkSpelling(correction, languageCode: languageCode) else {
            return false
        }
        
        // Вычисляем расстояние Левенштейна
        let distance = levenshteinDistance(original, correction)
        
        // Чем меньше расстояние, тем лучше исправление
        // Но также учитываем длину слова
        let maxAllowedDistance = max(2, original.count / 3)
        
        return distance <= maxAllowedDistance
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let empty = [Int](repeating: 0, count: s2.count)
        var last = [Int](0...s2.count)
        
        for (i, char1) in s1.enumerated() {
            var cur = [i + 1] + empty
            for (j, char2) in s2.enumerated() {
                cur[j + 1] = char1 == char2 ? last[j] : min(last[j], last[j + 1], cur[j]) + 1
            }
            last = cur
        }
        
        return last.last ?? Int.max
    }
    
    private func setupNotifications() {
        // Очищаем кэш при изменении системного словаря
        // В macOS 14+ используется другое API для отслеживания изменений словаря
        // Пока просто логируем, что сервис инициализирован
        logDebug("SystemDictionaryService initialized")
    }
    
    deinit {
        // NotificationCenter.default.removeObserver(self)
    }
}

/// Упрощенный API для работы с системным словарем
extension SystemDictionaryService {
    
    /// Проверяет, является ли слово допустимым английским словом
    func isEnglishWord(_ word: String) -> Bool {
        return checkSpelling(word, languageCode: "en")
    }
    
    /// Проверяет, является ли слово допустимым русским словом
    func isRussianWord(_ word: String) -> Bool {
        return checkSpelling(word, languageCode: "ru")
    }
    
    /// Получает исправления для английского слова
    func getEnglishSuggestions(_ word: String) -> [String] {
        return getSuggestions(word, languageCode: "en")
    }
    
    /// Получает исправления для русского слова
    func getRussianSuggestions(_ word: String) -> [String] {
        return getSuggestions(word, languageCode: "ru")
    }
    
    /// Получает лучшее исправление для английского слова
    func getBestEnglishCorrection(_ word: String) -> String? {
        return getBestCorrection(word, languageCode: "en")
    }
    
    /// Получает лучшее исправление для русского слова
    func getBestRussianCorrection(_ word: String) -> String? {
        return getBestCorrection(word, languageCode: "ru")
    }
}