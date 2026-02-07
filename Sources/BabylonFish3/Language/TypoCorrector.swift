import Foundation
import Cocoa

/// Контекстно-зависимый корректор опечаток
class TypoCorrector {
    
    // Зависимости
    private let systemDictionary: SystemDictionaryService
    private let cacheManager: CacheManager
    private let performanceMonitor: PerformanceMonitor
    
    // Конфигурация
    private var isEnabled: Bool = true
    private var autoCorrectEnabled: Bool = true
    private var suggestionEnabled: Bool = true
    private var maxEditDistance: Int = 2
    private var minConfidence: Double = 0.7
    private var contextWeight: Double = 0.3
    
    // Кэши
    private var correctionCache: [String: [String]] = [:] // слово → исправления
    private var distanceCache: [String: [String: Int]] = [:] // (слово1, слово2) → расстояние
    
    // Статистика
    private var totalCorrections: Int = 0
    private var successfulCorrections: Int = 0
    private var cacheHits: Int = 0
    private var contextUsedCount: Int = 0
    
    /// Инициализирует корректор опечаток
    init(
        systemDictionary: SystemDictionaryService = .shared,
        cacheManager: CacheManager = .shared,
        performanceMonitor: PerformanceMonitor = .shared
    ) {
        self.systemDictionary = systemDictionary
        self.cacheManager = cacheManager
        self.performanceMonitor = performanceMonitor
        
        logDebug("TypoCorrector initialized")
    }
    
    // MARK: - Public API
    
    /// Исправляет опечатки в тексте с учетом контекста
    func correctTypos(
        in text: String,
        language: Language? = nil,
        context: CorrectionContext? = nil
    ) -> CorrectionResult {
        
        performanceMonitor.startMeasurement("typoCorrection")
        defer { performanceMonitor.endMeasurement("typoCorrection") }
        
        totalCorrections += 1
        
        guard isEnabled else {
            return CorrectionResult(
                originalText: text,
                correctedText: text,
                corrections: [],
                confidence: 0,
                applied: false
            )
        }
        
        // Разбиваем текст на слова
        let words = splitIntoWords(text)
        
        guard !words.isEmpty else {
            return CorrectionResult(
                originalText: text,
                correctedText: text,
                corrections: [],
                confidence: 0,
                applied: false
            )
        }
        
        // Определяем язык если не указан
        let detectedLanguage = language ?? detectLanguage(from: words, context: context)
        
        // Исправляем каждое слово
        var corrections: [WordCorrection] = []
        var correctedWords: [String] = []
        
        for (index, word) in words.enumerated() {
            let correction = correctWord(
                word,
                atIndex: index,
                inWords: words,
                language: detectedLanguage,
                context: context
            )
            
            if correction.isCorrected {
                corrections.append(correction)
                correctedWords.append(correction.correctedWord)
            } else {
                correctedWords.append(word)
            }
        }
        
        // Собираем исправленный текст
        let correctedText = joinWords(correctedWords, originalText: text)
        
        // Рассчитываем общую уверенность
        let totalConfidence = corrections.isEmpty ? 0 : 
            corrections.map { $0.confidence }.reduce(0, +) / Double(corrections.count)
        
        let shouldApply = autoCorrectEnabled && totalConfidence >= minConfidence && !corrections.isEmpty
        
        if shouldApply {
            successfulCorrections += 1
        }
        
        return CorrectionResult(
            originalText: text,
            correctedText: correctedText,
            corrections: corrections,
            confidence: totalConfidence,
            applied: shouldApply
        )
    }
    
    /// Получает предложения по исправлению для слова
    func getSuggestions(
        for word: String,
        language: Language? = nil,
        context: CorrectionContext? = nil
    ) -> [String] {
        
        guard suggestionEnabled else { return [] }
        
        // Проверяем кэш
        let cacheKey = "\(word)|\(language?.rawValue ?? "unknown")"
        if let cached = getCachedSuggestions(for: cacheKey) {
            cacheHits += 1
            return cached
        }
        
        // Определяем язык
        let detectedLanguage = language ?? detectLanguage(from: [word], context: context)
        
        // Получаем предложения
        let suggestions = generateSuggestions(for: word, language: detectedLanguage, context: context)
        
        // Кэшируем результат
        cacheSuggestions(cacheKey, suggestions: suggestions)
        
        return suggestions
    }
    
    /// Настраивает корректор
    func configure(
        isEnabled: Bool? = nil,
        autoCorrectEnabled: Bool? = nil,
        suggestionEnabled: Bool? = nil,
        maxEditDistance: Int? = nil,
        minConfidence: Double? = nil,
        contextWeight: Double? = nil
    ) {
        if let isEnabled = isEnabled {
            self.isEnabled = isEnabled
        }
        if let autoCorrectEnabled = autoCorrectEnabled {
            self.autoCorrectEnabled = autoCorrectEnabled
        }
        if let suggestionEnabled = suggestionEnabled {
            self.suggestionEnabled = suggestionEnabled
        }
        if let maxEditDistance = maxEditDistance {
            self.maxEditDistance = max(1, min(5, maxEditDistance))
        }
        if let minConfidence = minConfidence {
            self.minConfidence = max(0.1, min(0.95, minConfidence))
        }
        if let contextWeight = contextWeight {
            self.contextWeight = max(0, min(1, contextWeight))
        }
        
        logDebug("""
        TypoCorrector configured:
        - enabled: \(self.isEnabled)
        - auto-correct: \(self.autoCorrectEnabled)
        - suggestions: \(self.suggestionEnabled)
        - max edit distance: \(self.maxEditDistance)
        - min confidence: \(self.minConfidence)
        - context weight: \(self.contextWeight)
        """)
    }
    
    /// Очищает кэш
    func clearCache() {
        correctionCache.removeAll()
        distanceCache.removeAll()
        logDebug("Typo correction cache cleared")
    }
    
    /// Получает статистику
    func getStatistics() -> [String: Any] {
        let successRate = totalCorrections > 0 ? Double(successfulCorrections) / Double(totalCorrections) : 0
        let cacheHitRate = totalCorrections > 0 ? Double(cacheHits) / Double(totalCorrections) : 0
        let contextUsageRate = totalCorrections > 0 ? Double(contextUsedCount) / Double(totalCorrections) : 0
        
        return [
            "totalCorrections": totalCorrections,
            "successfulCorrections": successfulCorrections,
            "successRate": successRate,
            "cacheHits": cacheHits,
            "cacheHitRate": cacheHitRate,
            "contextUsedCount": contextUsedCount,
            "contextUsageRate": contextUsageRate,
            "cacheSizes": [
                "correctionCache": correctionCache.count,
                "distanceCache": distanceCache.count
            ],
            "configuration": [
                "isEnabled": isEnabled,
                "autoCorrectEnabled": autoCorrectEnabled,
                "suggestionEnabled": suggestionEnabled,
                "maxEditDistance": maxEditDistance,
                "minConfidence": minConfidence,
                "contextWeight": contextWeight
            ]
        ]
    }
    
    /// Обучает корректор на новых примерах
    func train(with examples: [(incorrect: String, correct: String, language: Language)]) -> Bool {
        logDebug("Training typo corrector with \(examples.count) examples")
        
        // В реальной реализации здесь будет обучение модели
        // Пока просто добавляем в кэш
        
        for (incorrect, correct, language) in examples.prefix(100) {
            let cacheKey = "\(incorrect)|\(language.rawValue)"
            var suggestions = getCachedSuggestions(for: cacheKey) ?? []
            
            if !suggestions.contains(correct) {
                suggestions.insert(correct, at: 0)
                cacheSuggestions(cacheKey, suggestions: suggestions)
            }
        }
        
        return true
    }
    
    // MARK: - Private Methods
    
    private func splitIntoWords(_ text: String) -> [String] {
        // Разбиваем текст на слова, сохраняя разделители
        let pattern = "([\\w']+|[^\\w\\s]+|\\s+)"
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsString = text as NSString
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: nsString.length)) ?? []
        
        return matches.map { nsString.substring(with: $0.range) }
    }
    
    private func joinWords(_ words: [String], originalText: String) -> String {
        // Просто соединяем слова (в реальной реализации нужно сохранять оригинальные разделители)
        return words.joined(separator: " ")
    }
    
    private func detectLanguage(from words: [String], context: CorrectionContext?) -> Language {
        // Используем контекст если есть
        if let context = context, let contextLanguage = context.preferredLanguage {
            return contextLanguage
        }
        
        // Анализируем слова
        let text = words.joined(separator: " ")
        
        // Проверяем наличие кириллицы
        let hasCyrillic = text.contains { char in
            let scalar = String(char).unicodeScalars.first?.value ?? 0
            return (0x0400...0x04FF).contains(scalar)
        }
        
        // Проверяем наличие латиницы
        let hasLatin = text.contains { char in
            let scalar = String(char).unicodeScalars.first?.value ?? 0
            return (0x0041...0x007A).contains(scalar) || (0x0061...0x007A).contains(scalar)
        }
        
        if hasCyrillic && !hasLatin {
            return .russian
        } else if hasLatin && !hasCyrillic {
            return .english
        }
        
        // По умолчанию английский
        return .english
    }
    
    private func correctWord(
        _ word: String,
        atIndex index: Int,
        inWords words: [String],
        language: Language,
        context: CorrectionContext?
    ) -> WordCorrection {
        
        // Пропускаем короткие слова и числа
        if word.count <= 2 || word.allSatisfy({ $0.isNumber }) {
            return WordCorrection(
                originalWord: word,
                correctedWord: word,
                confidence: 0,
                suggestions: [],
                isCorrected: false
            )
        }
        
        // Проверяем, правильно ли написано слово
        if isWordCorrect(word, language: language) {
            return WordCorrection(
                originalWord: word,
                correctedWord: word,
                confidence: 1.0,
                suggestions: [],
                isCorrected: false
            )
        }
        
        // Получаем предложения по исправлению
        let suggestions = getSuggestions(for: word, language: language, context: context)
        
        guard let bestSuggestion = suggestions.first else {
            return WordCorrection(
                originalWord: word,
                correctedWord: word,
                confidence: 0,
                suggestions: [],
                isCorrected: false
            )
        }
        
        // Рассчитываем уверенность с учетом контекста
        let baseConfidence = calculateBaseConfidence(word, correction: bestSuggestion)
        let contextualConfidence = calculateContextualConfidence(
            word: word,
            correction: bestSuggestion,
            index: index,
            words: words,
            context: context
        )
        
        let totalConfidence = baseConfidence * (1 - contextWeight) + contextualConfidence * contextWeight
        
        return WordCorrection(
            originalWord: word,
            correctedWord: bestSuggestion,
            confidence: totalConfidence,
            suggestions: Array(suggestions.prefix(3)),
            isCorrected: true
        )
    }
    
    private func isWordCorrect(_ word: String, language: Language) -> Bool {
        let languageCode = language == .russian ? "ru" : "en"
        return systemDictionary.checkSpelling(word, languageCode: languageCode)
    }
    
    private func generateSuggestions(
        for word: String,
        language: Language,
        context: CorrectionContext?
    ) -> [String] {
        
        let languageCode = language == .russian ? "ru" : "en"
        
        // 1. Получаем предложения от системного словаря
        var suggestions = systemDictionary.getSuggestions(word, languageCode: languageCode)
        
        // 2. Если системный словарь не дал результатов, используем наши алгоритмы
        if suggestions.isEmpty {
            suggestions = generateSuggestionsManually(for: word, language: language)
        }
        
        // 3. Сортируем по релевантности
        suggestions = sortSuggestions(suggestions, for: word, language: language, context: context)
        
        // 4. Ограничиваем количество
        return Array(suggestions.prefix(5))
    }
    
    private func generateSuggestionsManually(for word: String, language: Language) -> [String] {
        var suggestions: Set<String> = []
        
        // Генерируем варианты с опечатками
        let editDistance = min(maxEditDistance, word.count / 2 + 1)
        
        // Добавляем варианты с заменой букв
        suggestions.formUnion(generateReplacements(for: word, maxDistance: editDistance))
        
        // Добавляем варианты с удалением букв
        suggestions.formUnion(generateDeletions(for: word, maxDistance: editDistance))
        
        // Добавляем варианты с добавлением букв
        suggestions.formUnion(generateInsertions(for: word, maxDistance: editDistance))
        
        // Добавляем варианты с перестановкой соседних букв
        suggestions.formUnion(generateTranspositions(for: word))
        
        // Фильтруем невалидные слова
        let languageCode = language == .russian ? "ru" : "en"
        return suggestions.filter { systemDictionary.checkSpelling($0, languageCode: languageCode) }
    }
    
    private func generateReplacements(for word: String, maxDistance: Int) -> Set<String> {
        var replacements: Set<String> = []
        let chars = Array(word)
        
        // Для английского: частые опечатки (qwerty раскладка)
        let qwertyMap: [Character: [Character]] = [
            "q": ["w", "a"], "w": ["q", "e", "s"], "e": ["w", "r", "d"],
            "r": ["e", "t", "f"], "t": ["r", "y", "g"], "y": ["t", "u", "h"],
            "u": ["y", "i", "j"], "i": ["u", "o", "k"], "o": ["i", "p", "l"],
            "p": ["o", "["], "a": ["q", "w", "s", "z"], "s": ["a", "w", "e", "d", "x", "z"],
            "d": ["s", "e", "r", "f", "c", "x"], "f": ["d", "r", "t", "g", "v", "c"],
            "g": ["f", "t", "y", "h", "b", "v"], "h": ["g", "y", "u", "j", "n", "b"],
            "j": ["h", "u", "i", "k", "m", "n"], "k": ["j", "i", "o", "l", ",", "m"],
            "l": ["k", "o", "p", ";", ".", ","], "z": ["a", "s", "x"], "x": ["z", "s", "d", "c"],
            "c": ["x", "d", "f", "v"], "v": ["c", "f", "g", "b"], "b": ["v", "g", "h", "n"],
            "n": ["b", "h", "j", "m"], "m": ["n", "j", "k"]
        ]
        
        for i in 0..<chars.count {
            if let similarChars = qwertyMap[chars[i]] {
                for similarChar in similarChars {
                    var newWord = chars
                    newWord[i] = similarChar
                    replacements.insert(String(newWord))
                }
            }
        }
        
        return replacements
    }
    
    private func generateDeletions(for word: String, maxDistance: Int) -> Set<String> {
        var deletions: Set<String> = []
        let chars = Array(word)
        
        for i in 0..<chars.count {
            var newChars = chars
            newChars.remove(at: i)
            deletions.insert(String(newChars))
        }
        
        return deletions
    }
    
    private func generateInsertions(for word: String, maxDistance: Int) -> Set<String> {
        var insertions: Set<String> = []
        let chars = Array(word)
        let alphabet = "abcdefghijklmnopqrstuvwxyz"
        
        for i in 0...chars.count {
            for char in alphabet {
                var newChars = chars
                newChars.insert(char, at: i)
                insertions.insert(String(newChars))
            }
        }
        
        return insertions
    }
    
    private func generateTranspositions(for word: String) -> Set<String> {
        var transpositions: Set<String> = []
        let chars = Array(word)
        
        for i in 0..<(chars.count - 1) {
            var newChars = chars
            newChars.swapAt(i, i + 1)
            transpositions.insert(String(newChars))
        }
        
        return transpositions
    }
    
    private func sortSuggestions(
        _ suggestions: [String],
        for word: String,
        language: Language,
        context: CorrectionContext?
    ) -> [String] {
        
        return suggestions.sorted { suggestion1, suggestion2 in
            let score1 = calculateSuggestionScore(suggestion1, original: word, language: language, context: context)
            let score2 = calculateSuggestionScore(suggestion2, original: word, language: language, context: context)
            return score1 > score2
        }
    }
    
    private func calculateSuggestionScore(
        _ suggestion: String,
        original: String,
        language: Language,
        context: CorrectionContext?
    ) -> Double {
        
        var score = 0.0
        
        // 1. Расстояние Левенштейна (меньше = лучше)
        let distance = calculateEditDistance(original, suggestion)
        let maxLen = max(original.count, suggestion.count)
        let distanceScore = 1.0 - Double(distance) / Double(maxLen)
        score += distanceScore * 0.4
        
        // 2. Частота слова (если есть в контексте)
        if let context = context, context.wordFrequency[suggestion] != nil {
            score += 0.3
        }
        
        // 3. Длина слова (ближе к оригиналу = лучше)
        let lengthDiff = abs(original.count - suggestion.count)
        let lengthScore = 1.0 - Double(lengthDiff) / Double(max(original.count, 1))
        score += lengthScore * 0.2
        
        // 4. Совпадение первой буквы
        if let originalFirst = original.first, let suggestionFirst = suggestion.first,
           originalFirst == suggestionFirst {
            score += 0.1
        }
        
        return score
    }
    
    private func calculateEditDistance(_ s1: String, _ s2: String) -> Int {
        let cacheKey = "\(s1)|\(s2)"
        
        if let cached = distanceCache[cacheKey]?[cacheKey] {
            return cached
        }
        
        let chars1 = Array(s1)
        let chars2 = Array(s2)
        
        if chars1.isEmpty { return chars2.count }
        if chars2.isEmpty { return chars1.count }
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: chars2.count + 1), count: chars1.count + 1)
        
        for i in 0...chars1.count {
            matrix[i][0] = i
        }
        
        for j in 0...chars2.count {
            matrix[0][j] = j
        }
        
        for i in 1...chars1.count {
            for j in 1...chars2.count {
                let cost = chars1[i - 1] == chars2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }
        
        let distance = matrix[chars1.count][chars2.count]
        
        // Кэшируем результат
        if distanceCache[cacheKey] == nil {
            distanceCache[cacheKey] = [:]
        }
        distanceCache[cacheKey]?[cacheKey] = distance
        
        return distance
    }
    
    private func calculateBaseConfidence(_ original: String, correction: String) -> Double {
        let distance = calculateEditDistance(original, correction)
        let maxLen = max(original.count, correction.count)
        
        if distance == 0 {
            return 1.0
        } else if distance == 1 {
            return 0.9
        } else if distance == 2 {
            return 0.7
        } else {
            return max(0.3, 1.0 - Double(distance) / Double(maxLen))
        }
    }
    
    private func calculateContextualConfidence(
        word: String,
        correction: String,
        index: Int,
        words: [String],
        context: CorrectionContext?
    ) -> Double {
        
        guard let context = context else {
            return 0.5 // Без контекста средняя уверенность
        }
        
        contextUsedCount += 1
        var confidence = 0.5
        
        // 1. Частота слова в контексте
        if let frequency = context.wordFrequency[correction] {
            confidence += min(0.3, Double(frequency) * 0.1)
        }
        
        // 2. Соседние слова
        if index > 0 {
            let prevWord = words[index - 1]
            if context.wordPairs["\(prevWord) \(correction)"] != nil {
                confidence += 0.2
            }
        }
        
        if index < words.count - 1 {
            let nextWord = words[index + 1]
            if context.wordPairs["\(correction) \(nextWord)"] != nil {
                confidence += 0.2
            }
        }
        
        // 3. Тематика
        if context.topic != nil {
            // В реальной реализации здесь будет проверка тематики слова
            // Пока просто добавляем небольшой бонус
            confidence += 0.1
        }
        
        return min(max(confidence, 0.1), 0.9)
    }
    
    private func getCachedSuggestions(for key: String) -> [String]? {
        return correctionCache[key]
    }
    
    private func cacheSuggestions(_ key: String, suggestions: [String]) {
        correctionCache[key] = suggestions
        
        // Ограничиваем размер кэша
        if correctionCache.count > 5000 {
            let keysToRemove = Array(correctionCache.keys.prefix(1000))
            for key in keysToRemove {
                correctionCache.removeValue(forKey: key)
            }
        }
    }
}

// MARK: - Вспомогательные структуры

/// Результат коррекции опечаток
struct CorrectionResult {
    let originalText: String
    let correctedText: String
    let corrections: [WordCorrection]
    let confidence: Double
    let applied: Bool
    
    var description: String {
        if corrections.isEmpty {
            return "No corrections needed"
        } else {
            let correctionList = corrections.map { "\($0.originalWord) → \($0.correctedWord)" }.joined(separator: ", ")
            return "Corrections: \(correctionList) (confidence: \(String(format: "%.0f", confidence * 100))%)"
        }
    }
}

/// Исправление отдельного слова
struct WordCorrection {
    let originalWord: String
    let correctedWord: String
    let confidence: Double
    let suggestions: [String]
    let isCorrected: Bool
    
    var description: String {
        return "\(originalWord) → \(correctedWord) (\(String(format: "%.0f", confidence * 100))%)"
    }
}

/// Контекст для коррекции
struct CorrectionContext {
    let preferredLanguage: Language?
    let wordFrequency: [String: Int] // Частота слов в текущем контексте
    let wordPairs: [String: Int] // Частота пар слов
    let topic: String? // Тематика текста
    let applicationType: ApplicationType
    let timestamp: Date
    
    init(
        preferredLanguage: Language? = nil,
        wordFrequency: [String: Int] = [:],
        wordPairs: [String: Int] = [:],
        topic: String? = nil,
        applicationType: ApplicationType = .other
    ) {
        self.preferredLanguage = preferredLanguage
        self.wordFrequency = wordFrequency
        self.wordPairs = wordPairs
        self.topic = topic
        self.applicationType = applicationType
        self.timestamp = Date()
    }
    
    /// Создает контекст из истории текста
    static func fromTextHistory(_ texts: [String], language: Language? = nil) -> CorrectionContext {
        var wordFrequency: [String: Int] = [:]
        var wordPairs: [String: Int] = [:]
        
        for text in texts {
            let words = text.split(separator: " ").map { String($0).lowercased() }
            
            // Считаем частоту слов
            for word in words {
                wordFrequency[word, default: 0] += 1
            }
            
            // Считаем пары слов
            for i in 0..<(words.count - 1) {
                let pair = "\(words[i]) \(words[i + 1])"
                wordPairs[pair, default: 0] += 1
            }
        }
        
        return CorrectionContext(
            preferredLanguage: language,
            wordFrequency: wordFrequency,
            wordPairs: wordPairs,
            topic: nil,
            applicationType: .other
        )
    }
}
