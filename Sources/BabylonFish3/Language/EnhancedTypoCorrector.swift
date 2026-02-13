import Foundation
import Cocoa
import CoreML
import NaturalLanguage

/// Улучшенный корректор опечаток с интеграцией CoreML и NSSpellChecker
class EnhancedTypoCorrector {
    
    // Зависимости
    private let systemDictionary: SystemDictionaryService
    private let neuralClassifier: NeuralLanguageClassifier
    private let cacheManager: CacheManager
    private let performanceMonitor: PerformanceMonitor
    
    // Конфигурация
    private var isEnabled: Bool = true
    private var autoCorrectEnabled: Bool = true
    private var suggestionEnabled: Bool = true
    private var maxEditDistance: Int = 2
    private var minConfidence: Double = 0.7
    private var contextWeight: Double = 0.3
    private var useNeuralForTypos: Bool = true
    private var neuralConfidenceThreshold: Double = 0.6
    
    // Кэши
    private var correctionCache: [String: [String]] = [:] // слово → исправления
    private var distanceCache: [String: [String: Int]] = [:] // (слово1, слово2) → расстояние
    private var neuralCache: [String: (Language, Double)] = [:] // слово → (язык, уверенность)
    
    // Статистика
    private var totalCorrections: Int = 0
    private var successfulCorrections: Int = 0
    private var cacheHits: Int = 0
    private var contextUsedCount: Int = 0
    private var neuralUsedCount: Int = 0
    private var spellCheckerUsedCount: Int = 0
    
    /// Инициализирует улучшенный корректор опечаток
    init(
        systemDictionary: SystemDictionaryService = .shared,
        neuralClassifier: NeuralLanguageClassifier = NeuralLanguageClassifier(),
        cacheManager: CacheManager = .shared,
        performanceMonitor: PerformanceMonitor = .shared
    ) {
        self.systemDictionary = systemDictionary
        self.neuralClassifier = neuralClassifier
        self.cacheManager = cacheManager
        self.performanceMonitor = performanceMonitor
        
        logDebug("EnhancedTypoCorrector initialized with CoreML+NSSpellChecker integration")
    }
    
    // MARK: - Public API
    
    /// Исправляет опечатки в тексте с учетом контекста
    func correctTypos(
        in text: String,
        language: Language? = nil,
        context: CorrectionContext? = nil
    ) -> CorrectionResult {
        
        performanceMonitor.startMeasurement("enhancedTypoCorrection")
        defer { performanceMonitor.endMeasurement("enhancedTypoCorrection") }
        
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
        
        // Получаем предложения с интеграцией CoreML и NSSpellChecker
        let suggestions = generateEnhancedSuggestions(for: word, language: detectedLanguage, context: context)
        
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
        contextWeight: Double? = nil,
        useNeuralForTypos: Bool? = nil,
        neuralConfidenceThreshold: Double? = nil
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
        if let useNeuralForTypos = useNeuralForTypos {
            self.useNeuralForTypos = useNeuralForTypos
        }
        if let neuralConfidenceThreshold = neuralConfidenceThreshold {
            self.neuralConfidenceThreshold = max(0.1, min(0.95, neuralConfidenceThreshold))
        }
        
        logDebug("""
        EnhancedTypoCorrector configured:
        - enabled: \(self.isEnabled)
        - auto-correct: \(self.autoCorrectEnabled)
        - suggestions: \(self.suggestionEnabled)
        - max edit distance: \(self.maxEditDistance)
        - min confidence: \(self.minConfidence)
        - context weight: \(self.contextWeight)
        - use neural for typos: \(self.useNeuralForTypos)
        - neural confidence threshold: \(self.neuralConfidenceThreshold)
        """)
    }
    
    /// Очищает кэш
    func clearCache() {
        correctionCache.removeAll()
        distanceCache.removeAll()
        neuralCache.removeAll()
        logDebug("Enhanced typo correction cache cleared")
    }
    
    /// Получает статистику
    func getStatistics() -> [String: Any] {
        let successRate = totalCorrections > 0 ? Double(successfulCorrections) / Double(totalCorrections) : 0
        let cacheHitRate = totalCorrections > 0 ? Double(cacheHits) / Double(totalCorrections) : 0
        let contextUsageRate = totalCorrections > 0 ? Double(contextUsedCount) / Double(totalCorrections) : 0
        let neuralUsageRate = totalCorrections > 0 ? Double(neuralUsedCount) / Double(totalCorrections) : 0
        let spellCheckerUsageRate = totalCorrections > 0 ? Double(spellCheckerUsedCount) / Double(totalCorrections) : 0
        
        return [
            "totalCorrections": totalCorrections,
            "successfulCorrections": successfulCorrections,
            "successRate": successRate,
            "cacheHits": cacheHits,
            "cacheHitRate": cacheHitRate,
            "contextUsedCount": contextUsedCount,
            "contextUsageRate": contextUsageRate,
            "neuralUsedCount": neuralUsedCount,
            "neuralUsageRate": neuralUsageRate,
            "spellCheckerUsedCount": spellCheckerUsedCount,
            "spellCheckerUsageRate": spellCheckerUsageRate,
            "cacheSizes": [
                "correctionCache": correctionCache.count,
                "distanceCache": distanceCache.count,
                "neuralCache": neuralCache.count
            ],
            "configuration": [
                "isEnabled": isEnabled,
                "autoCorrectEnabled": autoCorrectEnabled,
                "suggestionEnabled": suggestionEnabled,
                "maxEditDistance": maxEditDistance,
                "minConfidence": minConfidence,
                "contextWeight": contextWeight,
                "useNeuralForTypos": useNeuralForTypos,
                "neuralConfidenceThreshold": neuralConfidenceThreshold
            ]
        ]
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
            contextUsedCount += 1
            return contextLanguage
        }
        
        // Используем нейросеть для определения языка
        let text = words.joined(separator: " ")
        
        if useNeuralForTypos {
            neuralUsedCount += 1
            let neuralResult = neuralClassifier.classifyLanguage(text)
            
            if let language = neuralResult.language, neuralResult.confidence >= neuralConfidenceThreshold {
                logDebug("Neural language detection: \(language) with confidence \(neuralResult.confidence)")
                return language
            }
        }
        
        // Fallback: анализируем символы
        let hasCyrillic = text.contains { char in
            let scalar = String(char).unicodeScalars.first?.value ?? 0
            return (0x0400...0x04FF).contains(scalar)
        }
        
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
        
        // Пропускаем короткие слова и не-слова
        guard word.count >= 2 else {
            return WordCorrection(
                originalWord: word,
                correctedWord: word,
                confidence: 0,
                suggestions: [],
                isCorrected: false
            )
        }
        
        // Проверяем, является ли слово правильным
        let isCorrect = isWordCorrect(word, language: language)
        
        if isCorrect {
            return WordCorrection(
                originalWord: word,
                correctedWord: word,
                confidence: 1.0,
                suggestions: [],
                isCorrected: false
            )
        }
        
        // Получаем предложения по исправлению
        let suggestions = generateEnhancedSuggestions(for: word, language: language, context: context)
        
        guard let bestSuggestion = suggestions.first else {
            return WordCorrection(
                originalWord: word,
                correctedWord: word,
                confidence: 0,
                suggestions: [],
                isCorrected: false
            )
        }
        
        // Рассчитываем уверенность
        let confidence = calculateConfidence(
            original: word,
            corrected: bestSuggestion,
            language: language,
            context: context,
            index: index,
            words: words
        )
        
        return WordCorrection(
            originalWord: word,
            correctedWord: bestSuggestion,
            confidence: confidence,
            suggestions: suggestions,
            isCorrected: true
        )
    }
    
    private func isWordCorrect(_ word: String, language: Language) -> Bool {
        spellCheckerUsedCount += 1
        
        let languageCode = language == .russian ? "ru" : "en"
        return systemDictionary.checkSpelling(word, languageCode: languageCode)
    }
    
    private func generateEnhancedSuggestions(
        for word: String,
        language: Language,
        context: CorrectionContext?
    ) -> [String] {
        
        var allSuggestions: [String] = []
        
        // 1. Получаем предложения от NSSpellChecker
        let spellCheckerSuggestions = getSpellCheckerSuggestions(for: word, language: language)
        allSuggestions.append(contentsOf: spellCheckerSuggestions)
        
        // 2. Используем нейросеть для фильтрации и ранжирования
        if useNeuralForTypos {
            let neuralFiltered = filterSuggestionsWithNeural(
                word: word,
                suggestions: allSuggestions,
                language: language,
                context: context
            )
            allSuggestions = neuralFiltered
        }
        
        // 3. Учитываем контекст если есть
        if let context = context {
            let contextFiltered = filterSuggestionsWithContext(
                word: word,
                suggestions: allSuggestions,
                context: context
            )
            allSuggestions = contextFiltered
        }
        
        // 4. Удаляем дубликаты и ограничиваем количество
        allSuggestions = Array(Set(allSuggestions)).prefix(10).map { $0 }
        
        return allSuggestions
    }
    
    private func getSpellCheckerSuggestions(for word: String, language: Language) -> [String] {
        let languageCode = language == .russian ? "ru" : "en"
        return systemDictionary.getSuggestions(word, languageCode: languageCode)
    }
    
    private func filterSuggestionsWithNeural(
        word: String,
        suggestions: [String],
        language: Language,
        context: CorrectionContext?
    ) -> [String] {
        
        guard !suggestions.isEmpty else { return suggestions }
        
        var scoredSuggestions: [(suggestion: String, score: Double)] = []
        
        for suggestion in suggestions {
            // Используем нейросеть для оценки схожести
            let similarityScore = calculateNeuralSimilarity(word, suggestion, language: language)
            
            // Учитываем расстояние редактирования
            let editDistance = calculateEditDistance(word, suggestion)
            let editScore = max(0, 1.0 - Double(editDistance) / Double(max(word.count, suggestion.count)))
            
            // Комбинируем оценки
            let combinedScore = (similarityScore * 0.7) + (editScore * 0.3)
            
            scoredSuggestions.append((suggestion: suggestion, score: combinedScore))
        }
        
        // Сортируем по убыванию оценки
        scoredSuggestions.sort { $0.score > $1.score }
        
        // Фильтруем по порогу
        let threshold = 0.3
        let filtered = scoredSuggestions.filter { $0.score >= threshold }
        
        return filtered.map { $0.suggestion }
    }
    
    private func filterSuggestionsWithContext(
        word: String,
        suggestions: [String],
        context: CorrectionContext?
    ) -> [String] {
        
        guard let context = context else { return suggestions }
        
        var scoredSuggestions: [(suggestion: String, score: Double)] = []
        
        for suggestion in suggestions {
            var score = 0.0
            
            // Учитываем частоту слова в контексте
            if let frequency = context.wordFrequency[suggestion.lowercased()] {
                score += Double(frequency) * 0.1
            }
            
            // Учитываем пары слов
            // (в реальной реализации нужно анализировать соседние слова)
            
            scoredSuggestions.append((suggestion: suggestion, score: score))
        }
        
        // Сортируем по убыванию оценки
        scoredSuggestions.sort { $0.score > $1.score }
        
        return scoredSuggestions.map { $0.suggestion }
    }
    
    private func calculateNeuralSimilarity(_ word1: String, _ word2: String, language: Language) -> Double {
        // В реальной реализации здесь будет использование нейросети
        // для оценки семантической схожести слов
        
        // Временная реализация: используем расстояние Левенштейна
        let distance = calculateEditDistance(word1, word2)
        let maxLength = max(word1.count, word2.count)
        
        return max(0, 1.0 - Double(distance) / Double(maxLength))
    }
    
    private func calculateEditDistance(_ word1: String, _ word2: String) -> Int {
        // Проверяем кэш
        let cacheKey = "\(word1)|\(word2)"
        if let cached = distanceCache[cacheKey]?[word2] {
            return cached
        }
        
        // Вычисляем расстояние Левенштейна
        let empty = [Int](repeating: 0, count: word2.count)
        var last = [Int](0...word2.count)
        
        for (i, char1) in word1.enumerated() {
            var cur = [i + 1] + empty
            for (j, char2) in word2.enumerated() {
                cur[j + 1] = char1 == char2 ? last[j] : min(last[j], last[j + 1], cur[j]) + 1
            }
            last = cur
        }
        
        let distance = last.last!
        
        // Кэшируем результат
        if distanceCache[cacheKey] == nil {
            distanceCache[cacheKey] = [:]
        }
        distanceCache[cacheKey]?[word2] = distance
        
        return distance
    }
    
    private func calculateConfidence(
        original: String,
        corrected: String,
        language: Language,
        context: CorrectionContext?,
        index: Int,
        words: [String]
    ) -> Double {
        
        var confidence = 0.0
        
        // 1. Расстояние редактирования
        let editDistance = calculateEditDistance(original, corrected)
        let editScore = max(0, 1.0 - Double(editDistance) / Double(max(original.count, corrected.count)))
        confidence += editScore * 0.4
        
        // 2. Уверенность нейросети
        if useNeuralForTypos {
            let neuralScore = calculateNeuralSimilarity(original, corrected, language: language)
            confidence += neuralScore * 0.3
        }
        
        // 3. Контекст
        if let context = context {
            let contextScore = calculateContextScore(corrected, context: context, index: index, words: words)
            confidence += contextScore * 0.3
        }
        
        return min(1.0, confidence)
    }
    
    private func calculateContextScore(
        _ word: String,
        context: CorrectionContext,
        index: Int,
        words: [String]
    ) -> Double {
        
        var score = 0.0
        
        // Учитываем частоту слова в контексте
        if let frequency = context.wordFrequency[word.lowercased()] {
            score += min(1.0, Double(frequency) * 0.1)
        }
        
        // Учитываем пары слов с соседями
        if index > 0 {
            let prevWord = words[index - 1].lowercased()
            let pair = "\(prevWord) \(word.lowercased())"
            if let pairFrequency = context.wordPairs[pair] {
                score += min(1.0, Double(pairFrequency) * 0.05)
            }
        }
        
        if index < words.count - 1 {
            let nextWord = words[index + 1].lowercased()
            let pair = "\(word.lowercased()) \(nextWord)"
            if let pairFrequency = context.wordPairs[pair] {
                score += min(1.0, Double(pairFrequency) * 0.05)
            }
        }
        
        return min(1.0, score)
    }
    
    private func getCachedSuggestions(for key: String) -> [String]? {
        return correctionCache[key]
    }
    
    private func cacheSuggestions(_ key: String, suggestions: [String]) {
        correctionCache[key] = suggestions
    }
}