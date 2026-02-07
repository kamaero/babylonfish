import Foundation
import Cocoa

/// Умный движок автодополнения слов
class AutoCompleteEngine {
    
    // Зависимости
    private let systemDictionary: SystemDictionaryService
    private let cacheManager: CacheManager
    private let performanceMonitor: PerformanceMonitor
    
    // Конфигурация
    private var isEnabled: Bool = true
    private var maxSuggestions: Int = 5
    private var minPrefixLength: Int = 2
    private var contextWeight: Double = 0.4
    private var learningWeight: Double = 0.3
    
    // Словари и кэши
    private var wordDictionary: Set<String> = []
    private var ngramDictionary: [String: [String]] = [:] // n-gram → слова
    private var completionCache: [String: [CompletionSuggestion]] = [:] // префикс → дополнения
    private var userHistory: [String: Int] = [:] // слово → частота использования
    
    // Модели
    private var markovModel: MarkovModel?
    
    // Статистика
    private var totalCompletions: Int = 0
    private var successfulCompletions: Int = 0
    private var cacheHits: Int = 0
    private var contextUsedCount: Int = 0
    
    /// Инициализирует движок автодополнения
    init(
        systemDictionary: SystemDictionaryService = .shared,
        cacheManager: CacheManager = .shared,
        performanceMonitor: PerformanceMonitor = .shared
    ) {
        self.systemDictionary = systemDictionary
        self.cacheManager = cacheManager
        self.performanceMonitor = performanceMonitor
        
        loadDictionaries()
        setupMarkovModel()
        
        logDebug("AutoCompleteEngine initialized")
    }
    
    // MARK: - Public API
    
    /// Получает автодополнения для префикса с учетом контекста
    func getCompletions(
        for prefix: String,
        language: Language? = nil,
        context: CompletionContext? = nil
    ) -> [CompletionSuggestion] {
        
        performanceMonitor.startMeasurement("autoComplete")
        defer { performanceMonitor.endMeasurement("autoComplete") }
        
        totalCompletions += 1
        
        guard isEnabled else {
            return []
        }
        
        guard prefix.count >= minPrefixLength else {
            return []
        }
        
        // Проверяем кэш
        let cacheKey = generateCacheKey(prefix: prefix, language: language, context: context)
        if let cached = getCachedCompletions(for: cacheKey) {
            cacheHits += 1
            return cached
        }
        
        // Определяем язык
        let detectedLanguage = language ?? detectLanguage(from: prefix, context: context)
        
        // Получаем базовые дополнения
        var completions = getBaseCompletions(for: prefix, language: detectedLanguage)
        
        // Применяем контекст если есть
        if let context = context, !completions.isEmpty {
            completions = applyContext(to: completions, prefix: prefix, context: context)
            contextUsedCount += 1
        }
        
        // Сортируем и ограничиваем
        completions.sort { $0.score > $1.score }
        completions = Array(completions.prefix(maxSuggestions))
        
        // Кэшируем результат
        cacheCompletions(cacheKey, completions: completions)
        
        if !completions.isEmpty {
            successfulCompletions += 1
        }
        
        return completions
    }
    
    /// Обучает движок на новом тексте
    func learn(from text: String, language: Language? = nil) {
        guard isEnabled else { return }
        
        let words = extractWords(from: text)
        
        // Добавляем слова в словарь
        for word in words {
            wordDictionary.insert(word.lowercased())
            userHistory[word.lowercased(), default: 0] += 1
        }
        
        // Обновляем n-gram модель
        updateNgramModel(with: words)
        
        // Обновляем марковскую модель
        markovModel?.train(with: words)
        
        // Очищаем кэш, так как словарь изменился
        clearCache()
        
        logDebug("AutoCompleteEngine learned from text with \(words.count) words")
    }
    
    /// Настраивает движок
    func configure(
        isEnabled: Bool? = nil,
        maxSuggestions: Int? = nil,
        minPrefixLength: Int? = nil,
        contextWeight: Double? = nil,
        learningWeight: Double? = nil
    ) {
        if let isEnabled = isEnabled {
            self.isEnabled = isEnabled
        }
        if let maxSuggestions = maxSuggestions {
            self.maxSuggestions = max(1, min(10, maxSuggestions))
        }
        if let minPrefixLength = minPrefixLength {
            self.minPrefixLength = max(1, min(5, minPrefixLength))
        }
        if let contextWeight = contextWeight {
            self.contextWeight = max(0, min(1, contextWeight))
        }
        if let learningWeight = learningWeight {
            self.learningWeight = max(0, min(1, learningWeight))
        }
        
        logDebug("""
        AutoCompleteEngine configured:
        - enabled: \(self.isEnabled)
        - max suggestions: \(self.maxSuggestions)
        - min prefix length: \(self.minPrefixLength)
        - context weight: \(self.contextWeight)
        - learning weight: \(self.learningWeight)
        """)
    }
    
    /// Очищает кэш
    func clearCache() {
        completionCache.removeAll()
        logDebug("Auto-complete cache cleared")
    }
    
    /// Сбрасывает историю пользователя
    func resetUserHistory() {
        userHistory.removeAll()
        logDebug("User history reset")
    }
    
    /// Получает статистику
    func getStatistics() -> [String: Any] {
        let successRate = totalCompletions > 0 ? Double(successfulCompletions) / Double(totalCompletions) : 0
        let cacheHitRate = totalCompletions > 0 ? Double(cacheHits) / Double(totalCompletions) : 0
        let contextUsageRate = totalCompletions > 0 ? Double(contextUsedCount) / Double(totalCompletions) : 0
        
        return [
            "totalCompletions": totalCompletions,
            "successfulCompletions": successfulCompletions,
            "successRate": successRate,
            "cacheHits": cacheHits,
            "cacheHitRate": cacheHitRate,
            "contextUsedCount": contextUsedCount,
            "contextUsageRate": contextUsageRate,
            "dictionarySize": wordDictionary.count,
            "userHistorySize": userHistory.count,
            "ngramDictionarySize": ngramDictionary.count,
            "cacheSize": completionCache.count,
            "configuration": [
                "isEnabled": isEnabled,
                "maxSuggestions": maxSuggestions,
                "minPrefixLength": minPrefixLength,
                "contextWeight": contextWeight,
                "learningWeight": learningWeight
            ]
        ]
    }
    
    /// Экспортирует данные для обучения
    func exportTrainingData() -> [String: Any] {
        return [
            "wordDictionary": Array(wordDictionary),
            "userHistory": userHistory,
            "ngramDictionary": ngramDictionary.mapValues { $0.joined(separator: ", ") }
        ]
    }
    
    // MARK: - Private Methods
    
    private func loadDictionaries() {
        // Загружаем базовый словарь из системного словаря
        // В реальной реализации здесь будет загрузка из файла или базы данных
        
        logDebug("Loading dictionaries...")
        
        // Инициализируем пустой словарь
        // В реальном приложении здесь будет загрузка предварительно обученного словаря
        
        wordDictionary = Set([
            "hello", "world", "test", "computer", "program",
            "привет", "мир", "тест", "компьютер", "программа"
        ])
        
        logDebug("Dictionary loaded with \(wordDictionary.count) words")
    }
    
    private func setupMarkovModel() {
        markovModel = MarkovModel(order: 2)
        logDebug("Markov model initialized")
    }
    
    private func extractWords(from text: String) -> [String] {
        // Разбиваем текст на слова, фильтруем короткие и специальные
        let words = text.split(separator: " ")
            .map { String($0) }
            .filter { word in
                word.count >= 2 &&
                !word.allSatisfy { $0.isNumber } &&
                !word.allSatisfy { $0.isPunctuation }
            }
            .map { $0.lowercased() }
        
        return words
    }
    
    private func updateNgramModel(with words: [String]) {
        // Обновляем n-gram словарь (для префиксов длиной 2-4 символа)
        for word in words {
            guard word.count >= 2 else { continue }
            
            let maxN = min(4, word.count)
            for n in 2...maxN {
                let prefix = String(word.prefix(n))
                
                if ngramDictionary[prefix] == nil {
                    ngramDictionary[prefix] = []
                }
                
                if !ngramDictionary[prefix]!.contains(word) {
                    ngramDictionary[prefix]!.append(word)
                }
            }
        }
    }
    
    private func generateCacheKey(prefix: String, language: Language?, context: CompletionContext?) -> String {
        var key = "\(prefix)|\(language?.rawValue ?? "unknown")"
        
        if let context = context {
            key += "|\(context.previousWords?.joined(separator: ",") ?? "")"
            key += "|\(context.topic ?? "")"
        }
        
        return key
    }
    
    private func detectLanguage(from text: String, context: CompletionContext?) -> Language {
        // Используем контекст если есть
        if let context = context, let contextLanguage = context.preferredLanguage {
            return contextLanguage
        }
        
        // Анализируем текст
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
    
    private func getBaseCompletions(for prefix: String, language: Language) -> [CompletionSuggestion] {
        var completions: [CompletionSuggestion] = []
        
        // 1. Ищем в n-gram словаре
        if let ngramCompletions = ngramDictionary[prefix] {
            for word in ngramCompletions {
                let score = calculateBaseScore(word: word, prefix: prefix, language: language)
                completions.append(CompletionSuggestion(
                    word: word,
                    score: score,
                    source: .ngramDictionary,
                    confidence: score
                ))
            }
        }
        
        // 2. Ищем в системном словаре
        let languageCode = language == .russian ? "ru" : "en"
        let systemCompletions = systemDictionary.getCompletions(prefix, languageCode: languageCode)
        
        for word in systemCompletions {
            let score = calculateBaseScore(word: word, prefix: prefix, language: language)
            completions.append(CompletionSuggestion(
                word: word,
                score: score,
                source: .systemDictionary,
                confidence: score
            ))
        }
        
        // 3. Ищем в нашем словаре
        for word in wordDictionary where word.hasPrefix(prefix) {
            let score = calculateBaseScore(word: word, prefix: prefix, language: language)
            completions.append(CompletionSuggestion(
                word: word,
                score: score,
                source: .internalDictionary,
                confidence: score
            ))
        }
        
        // Удаляем дубликаты
        var uniqueCompletions: [String: CompletionSuggestion] = [:]
        for completion in completions {
            if let existing = uniqueCompletions[completion.word] {
                // Берем вариант с максимальным score
                if completion.score > existing.score {
                    uniqueCompletions[completion.word] = completion
                }
            } else {
                uniqueCompletions[completion.word] = completion
            }
        }
        
        return Array(uniqueCompletions.values)
    }
    
    private func calculateBaseScore(word: String, prefix: String, language: Language) -> Double {
        var score = 0.0
        
        // 1. Совпадение префикса (обязательно)
        guard word.hasPrefix(prefix) else { return 0 }
        
        // 2. Длина слова (предпочитаем более короткие слова)
        let lengthRatio = Double(prefix.count) / Double(word.count)
        score += lengthRatio * 0.3
        
        // 3. Частота в истории пользователя
        if let frequency = userHistory[word] {
            let freqScore = min(1.0, Double(frequency) * 0.1)
            score += freqScore * learningWeight
        }
        
        // 4. Проверка в системном словаре
        let languageCode = language == .russian ? "ru" : "en"
        if systemDictionary.checkSpelling(word, languageCode: languageCode) {
            score += 0.2
        }
        
        // 5. Сложность слова (предпочитаем более простые слова)
        let uniqueChars = Set(word).count
        let complexity = Double(uniqueChars) / Double(word.count)
        score += (1.0 - complexity) * 0.1
        
        return min(max(score, 0.1), 1.0)
    }
    
    private func applyContext(
        to completions: [CompletionSuggestion],
        prefix: String,
        context: CompletionContext
    ) -> [CompletionSuggestion] {
        
        var contextualCompletions = completions
        
        for i in 0..<contextualCompletions.count {
            var completion = contextualCompletions[i]
            let contextualScore = calculateContextualScore(
                word: completion.word,
                prefix: prefix,
                context: context
            )
            
            // Комбинируем базовый score с контекстным
            let baseScore = completion.score * (1 - contextWeight)
            let contextScore = contextualScore * contextWeight
            completion.score = baseScore + contextScore
            completion.confidence = completion.score
            
            contextualCompletions[i] = completion
        }
        
        return contextualCompletions
    }
    
    private func calculateContextualScore(
        word: String,
        prefix: String,
        context: CompletionContext
    ) -> Double {
        
        var score = 0.5 // Базовый score без контекста
        
        // 1. Предыдущие слова
        if let previousWords = context.previousWords, !previousWords.isEmpty {
            let lastWord = previousWords.last ?? ""
            
            // Проверяем пару слов в марковской модели
            if let markovScore = markovModel?.getProbability(word: word, given: lastWord) {
                score += markovScore * 0.3
            }
            
            // Проверяем частоту пары в истории
            let pair = "\(lastWord) \(word)"
            if let pairFrequency = context.wordPairFrequency[pair] {
                let pairScore = min(0.2, Double(pairFrequency) * 0.05)
                score += pairScore
            }
        }
        
        // 2. Тематика
        if let topic = context.topic, let topicWords = context.topicWordFrequency[topic] {
            if topicWords.contains(word) {
                score += 0.15
            }
        }
        
        // 3. Тип приложения
        switch context.applicationType {
        case .ide, .terminal:
            // В IDE и терминалах предпочитаем технические слова
            if isTechnicalWord(word) {
                score += 0.1
            }
        case .textEditor, .browser:
            // В текстовых редакторах и браузерах нейтрально
            break
        case .game:
            // В играх могут быть специфичные слова
            break
        case .other:
            break
        }
        
        // 4. Время суток (простой пример контекста)
        let hour = Calendar.current.component(.hour, from: Date())
        if (hour >= 9 && hour <= 17) && isWorkRelatedWord(word) {
            score += 0.05
        }
        
        return min(max(score, 0.1), 0.9)
    }
    
    private func isTechnicalWord(_ word: String) -> Bool {
        let technicalWords: Set<String> = [
            "function", "class", "method", "variable", "constant",
            "import", "export", "return", "if", "else", "for", "while",
            "switch", "case", "break", "continue", "try", "catch",
            "throw", "new", "this", "super", "static", "final",
            "public", "private", "protected", "void", "int", "string",
            "boolean", "array", "list", "map", "set", "null", "true", "false"
        ]
        
        return technicalWords.contains(word.lowercased())
    }
    
    private func isWorkRelatedWord(_ word: String) -> Bool {
        let workWords: Set<String> = [
            "meeting", "report", "project", "deadline", "email",
            "document", "presentation", "conference", "schedule",
            "budget", "plan", "task", "goal", "objective", "result"
        ]
        
        return workWords.contains(word.lowercased())
    }
    
    private func getCachedCompletions(for key: String) -> [CompletionSuggestion]? {
        return completionCache[key]
    }
    
    private func cacheCompletions(_ key: String, completions: [CompletionSuggestion]) {
        completionCache[key] = completions
        
        // Ограничиваем размер кэша
        if completionCache.count > 1000 {
            let keysToRemove = Array(completionCache.keys.prefix(200))
            for key in keysToRemove {
                completionCache.removeValue(forKey: key)
            }
        }
    }
}

// MARK: - Вспомогательные структуры

/// Предложение автодополнения
struct CompletionSuggestion {
    let word: String
    var score: Double
    let source: CompletionSource
    var confidence: Double
    
    var description: String {
        return "\(word) (\(String(format: "%.0f", score * 100))%) [\(source)]"
    }
}

/// Источник дополнения
enum CompletionSource: String {
    case systemDictionary = "System"
    case internalDictionary = "Internal"
    case ngramDictionary = "N-gram"
    case markovModel = "Markov"
    case userHistory = "History"
}

/// Контекст для автодополнения
struct CompletionContext {
    let previousWords: [String]?
    let preferredLanguage: Language?
    let wordPairFrequency: [String: Int] // Частота пар слов
    let topic: String? // Текущая тема
    let topicWordFrequency: [String: Set<String>] // Слова по темам
    let applicationType: ApplicationType
    let timestamp: Date
    
    init(
        previousWords: [String]? = nil,
        preferredLanguage: Language? = nil,
        wordPairFrequency: [String: Int] = [:],
        topic: String? = nil,
        topicWordFrequency: [String: Set<String>] = [:],
        applicationType: ApplicationType = .other
    ) {
        self.previousWords = previousWords
        self.preferredLanguage = preferredLanguage
        self.wordPairFrequency = wordPairFrequency
        self.topic = topic
        self.topicWordFrequency = topicWordFrequency
        self.applicationType = applicationType
        self.timestamp = Date()
    }
    
    /// Создает контекст из истории текста
    static func fromTextHistory(_ texts: [String], language: Language? = nil, topic: String? = nil) -> CompletionContext {
        var wordPairFrequency: [String: Int] = [:]
        var topicWordFrequency: [String: Set<String>] = [:]
        
        for text in texts {
            let words = text.split(separator: " ").map { String($0).lowercased() }
            
            // Считаем пары слов
            for i in 0..<(words.count - 1) {
                let pair = "\(words[i]) \(words[i + 1])"
                wordPairFrequency[pair, default: 0] += 1
            }
            
            // Добавляем слова в тему если указана
            if let topic = topic {
                if topicWordFrequency[topic] == nil {
                    topicWordFrequency[topic] = Set()
                }
                for word in words {
                    topicWordFrequency[topic]?.insert(word)
                }
            }
        }
        
        return CompletionContext(
            previousWords: texts.last?.split(separator: " ").map { String($0) },
            preferredLanguage: language,
            wordPairFrequency: wordPairFrequency,
            topic: topic,
            topicWordFrequency: topicWordFrequency,
            applicationType: .other
        )
    }
}

/// Марковская модель для предсказания слов
class MarkovModel {
    private let order: Int
    private var transitions: [String: [String: Int]] = [:] // состояние → следующее слово → частота
    private var totalTransitions: [String: Int] = [:] // состояние → общее количество переходов
    
    init(order: Int = 2) {
        self.order = order
    }
    
    /// Обучает модель на последовательности слов
    func train(with words: [String]) {
        guard words.count > order else { return }
        
        for i in 0..<(words.count - order) {
            let state = words[i..<(i + order)].joined(separator: " ")
            let nextWord = words[i + order]
            
            // Обновляем переходы
            if transitions[state] == nil {
                transitions[state] = [:]
            }
            
            transitions[state]![nextWord, default: 0] += 1
            totalTransitions[state, default: 0] += 1
        }
    }
    
    /// Получает вероятность слова given состояние
    func getProbability(word: String, given state: String) -> Double {
        // Для простоты используем состояние из одного слова
        let fullState = state
        
        guard let stateTransitions = transitions[fullState],
              let total = totalTransitions[fullState],
              total > 0 else {
            return 0.0
        }
        
        let frequency = stateTransitions[word] ?? 0
        return Double(frequency) / Double(total)
    }
    
    /// Предсказывает следующее слово
    func predictNextWord(given state: String) -> String? {
        let fullState = state
        
        guard let stateTransitions = transitions[fullState],
              let total = totalTransitions[fullState],
              total > 0 else {
            return nil
        }
        
        // Находим слово с максимальной частотой
        return stateTransitions.max(by: { $0.value < $1.value })?.key
    }
    
    /// Получает статистику модели
    func getStatistics() -> [String: Any] {
        return [
            "order": order,
            "statesCount": transitions.count,
            "totalTransitions": totalTransitions.values.reduce(0, +)
        ]
    }
}