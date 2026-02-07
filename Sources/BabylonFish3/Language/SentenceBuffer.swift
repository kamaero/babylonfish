import Foundation

/// Буфер для хранения контекста предложений
class SentenceBuffer {
    
    /// Запись в буфере предложения
    struct SentenceRecord {
        let text: String
        let language: Language
        let timestamp: Date
        let wordCount: Int
        
        init(text: String, language: Language) {
            self.text = text
            self.language = language
            self.timestamp = Date()
            self.wordCount = text.split(separator: " ").count
        }
        
        var age: TimeInterval {
            Date().timeIntervalSince(timestamp)
        }
    }
    
    // Конфигурация
    private let maxSentences: Int
    private let maxAge: TimeInterval
    private let maxTotalWords: Int
    
    // Буфер предложений
    private var sentences: [SentenceRecord] = []
    
    // Статистика
    private var totalWordsProcessed: Int = 0
    private var languageDistribution: [Language: Int] = [:]
    
    /// Инициализирует буфер предложений
    init(maxSentences: Int = 10, maxAge: TimeInterval = 300, maxTotalWords: Int = 100) {
        self.maxSentences = maxSentences
        self.maxAge = maxAge
        self.maxTotalWords = maxTotalWords
    }
    
    // MARK: - Public API
    
    /// Добавляет предложение в буфер
    func addSentence(_ text: String, language: Language) {
        // Очищаем старые записи перед добавлением
        cleanupOldEntries()
        
        let record = SentenceRecord(text: text, language: language)
        sentences.append(record)
        
        // Обновляем статистику
        totalWordsProcessed += record.wordCount
        languageDistribution[language, default: 0] += 1
        
        // Ограничиваем размер буфера
        if sentences.count > maxSentences {
            removeOldestSentence()
        }
        
        // Ограничиваем общее количество слов
        while totalWordsProcessed > maxTotalWords && !sentences.isEmpty {
            removeOldestSentence()
        }
        
        logDebug("Sentence added: '\(text)' (\(language)), buffer size: \(sentences.count) sentences, \(totalWordsProcessed) words")
    }
    
    /// Добавляет слово в текущий контекст
    func addWord(_ word: String, language: Language) {
        // Если последнее предложение того же языка, добавляем к нему
        if let last = sentences.last, last.language == language, last.age < 30 {
            // В реальной реализации нужно обновить существующую запись
            // Для простоты создаем новое объединенное предложение
            let newText = last.text + " " + word
            sentences.removeLast()
            addSentence(newText, language: language)
        } else {
            // Создаем новое предложение
            addSentence(word, language: language)
        }
    }
    
    /// Получает последние N предложений
    func getRecentSentences(_ count: Int = 3) -> [SentenceRecord] {
        cleanupOldEntries()
        return Array(sentences.suffix(count))
    }
    
    /// Получает контекст для текущего слова
    func getContext(forWord word: String? = nil) -> SentenceContext {
        cleanupOldEntries()
        
        var context = SentenceContext()
        
        // Добавляем последние предложения
        context.recentSentences = getRecentSentences(3)
        
        // Анализируем распределение языков
        context.languageTrend = analyzeLanguageTrend()
        
        // Анализируем тему разговора
        context.topic = analyzeTopic()
        
        // Определяем вероятный язык для нового слова
        if let word = word {
            context.suggestedLanguage = suggestLanguage(for: word)
            context.confidence = calculateConfidence(for: word)
        }
        
        return context
    }
    
    /// Очищает буфер
    func clear() {
        sentences.removeAll()
        totalWordsProcessed = 0
        languageDistribution.removeAll()
        logDebug("Sentence buffer cleared")
    }
    
    /// Получает статистику буфера
    func getStatistics() -> [String: Any] {
        return [
            "sentenceCount": sentences.count,
            "totalWordsProcessed": totalWordsProcessed,
            "languageDistribution": languageDistribution.mapValues { $0 },
            "oldestSentenceAge": sentences.first?.age ?? 0,
            "newestSentenceAge": sentences.last?.age ?? 0
        ]
    }
    
    // MARK: - Private Methods
    
    private func cleanupOldEntries() {
        let now = Date()
        sentences.removeAll { record in
            now.timeIntervalSince(record.timestamp) > maxAge
        }
        
        // Пересчитываем статистику после очистки
        recalculateStatistics()
    }
    
    private func removeOldestSentence() {
        guard let oldest = sentences.first else { return }
        
        sentences.removeFirst()
        totalWordsProcessed -= oldest.wordCount
        languageDistribution[oldest.language, default: 0] -= 1
        
        // Удаляем язык из распределения если счетчик стал 0
        if languageDistribution[oldest.language] == 0 {
            languageDistribution.removeValue(forKey: oldest.language)
        }
    }
    
    private func recalculateStatistics() {
        totalWordsProcessed = sentences.reduce(0) { $0 + $1.wordCount }
        languageDistribution = [:]
        
        for sentence in sentences {
            languageDistribution[sentence.language, default: 0] += 1
        }
    }
    
    private func analyzeLanguageTrend() -> BufferLanguageTrend {
        guard !sentences.isEmpty else { return .neutral }
        
        let recent = getRecentSentences(3)
        guard !recent.isEmpty else { return .neutral }
        
        // Считаем языки в последних предложениях
        var counts: [Language: Int] = [:]
        for sentence in recent {
            counts[sentence.language, default: 0] += 1
        }
        
        // Определяем тренд
        if let dominantLanguage = counts.max(by: { $0.value < $1.value }) {
            let dominantCount = dominantLanguage.value
            let total = recent.count
            
            if Double(dominantCount) / Double(total) > 0.67 { // > 2/3
                return .strong(language: dominantLanguage.key)
            } else if Double(dominantCount) / Double(total) > 0.5 { // > 1/2
                return .moderate(language: dominantLanguage.key)
            }
        }
        
        return .mixed
    }
    
    private func analyzeTopic() -> BufferConversationTopic {
        guard !sentences.isEmpty else { return .unknown }
        
        let recentText = getRecentSentences(3).map { $0.text }.joined(separator: " ").lowercased()
        
        // Ключевые слова для определения темы
        let programmingKeywords = ["function", "class", "var", "let", "if", "else", "return", "import", "protocol"]
        let technicalKeywords = ["computer", "software", "hardware", "network", "system", "code", "program"]
        let casualKeywords = ["hello", "hi", "how", "are", "you", "thanks", "please", "sorry"]
        let workKeywords = ["meeting", "project", "deadline", "report", "email", "client", "work"]
        
        // Проверяем наличие ключевых слов
        let isProgramming = programmingKeywords.contains { recentText.contains($0) }
        let isTechnical = technicalKeywords.contains { recentText.contains($0) }
        let isCasual = casualKeywords.contains { recentText.contains($0) }
        let isWork = workKeywords.contains { recentText.contains($0) }
        
        // Определяем тему
        if isProgramming {
            return .programming
        } else if isTechnical {
            return .technical
        } else if isWork {
            return .work
        } else if isCasual {
            return .casual
        } else {
            return .unknown
        }
    }
    
    private func suggestLanguage(for word: String) -> Language? {
        let context = getContext()
        
        // Если есть сильный тренд, следуем ему
        if case .strong(let language) = context.languageTrend {
            return language
        }
        
        // Анализируем само слово
        let wordAnalysis = analyzeWord(word)
        
        // Комбинируем контекст и анализ слова
        return combineSuggestions(context: context, wordAnalysis: wordAnalysis)
    }
    
    private func analyzeWord(_ word: String) -> WordAnalysis {
        var analysis = WordAnalysis()
        
        // Проверяем наличие кириллических символов
        let hasCyrillic = word.contains { char in
            let scalar = String(char).unicodeScalars.first?.value ?? 0
            return (0x0400...0x04FF).contains(scalar) // Кириллический диапазон
        }
        
        // Проверяем наличие латинских символов
        let hasLatin = word.contains { char in
            let scalar = String(char).unicodeScalars.first?.value ?? 0
            return (0x0041...0x007A).contains(scalar) // Латинский диапазон
        }
        
        if hasCyrillic && !hasLatin {
            analysis.suggestedLanguage = .russian
            analysis.confidence = 0.9
        } else if hasLatin && !hasCyrillic {
            analysis.suggestedLanguage = .english
            analysis.confidence = 0.9
        } else {
            // Смешанные символы или другие
            analysis.confidence = 0.5
        }
        
        return analysis
    }
    
    private func combineSuggestions(context: SentenceContext, wordAnalysis: WordAnalysis) -> Language? {
        // Веса для разных факторов
        let contextWeight = 0.6
        let wordWeight = 0.4
        
        var scores: [Language: Double] = [:]
        
        // Учитываем контекст
        switch context.languageTrend {
        case .strong(let language):
            scores[language, default: 0] += 0.7 * contextWeight
        case .moderate(let language):
            scores[language, default: 0] += 0.5 * contextWeight
        case .mixed:
            // Нейтральный контекст
            break
        case .neutral:
            break
        }
        
        // Учитываем анализ слова
        if let wordLanguage = wordAnalysis.suggestedLanguage {
            scores[wordLanguage, default: 0] += wordAnalysis.confidence * wordWeight
        }
        
        // Возвращаем язык с максимальным score
        return scores.max(by: { $0.value < $1.value })?.key
    }
    
    private func calculateConfidence(for word: String) -> Double {
        let context = getContext()
        let wordAnalysis = analyzeWord(word)
        
        var confidence = 0.5 // Базовая уверенность
        
        // Повышаем уверенность при сильном тренде
        if case .strong = context.languageTrend {
            confidence += 0.3
        }
        
        // Повышаем уверенность при четком анализе слова
        if wordAnalysis.confidence > 0.8 {
            confidence += 0.2
        }
        
        // Понижаем уверенность при смешанном контексте
        if case .mixed = context.languageTrend {
            confidence -= 0.2
        }
        
        return min(max(confidence, 0.1), 0.95) // Ограничиваем диапазон
    }
}

// MARK: - Вспомогательные структуры

/// Контекст предложения
struct SentenceContext {
    var recentSentences: [SentenceBuffer.SentenceRecord] = []
    var languageTrend: BufferLanguageTrend = .neutral
    var topic: BufferConversationTopic = .unknown
    var suggestedLanguage: Language?
    var confidence: Double = 0.5
    
    var description: String {
        var desc = "Context: "
        desc += "trend=\(languageTrend), "
        desc += "topic=\(topic), "
        if let lang = suggestedLanguage {
            desc += "suggested=\(lang) (\(String(format: "%.0f", confidence * 100))%)"
        }
        return desc
    }
}

/// Тренд языка в контексте
enum BufferLanguageTrend {
    case strong(language: Language)
    case moderate(language: Language)
    case mixed
    case neutral
    
    var description: String {
        switch self {
        case .strong(let lang):
            return "Strong \(lang)"
        case .moderate(let lang):
            return "Moderate \(lang)"
        case .mixed:
            return "Mixed languages"
        case .neutral:
            return "No trend"
        }
    }
}

/// Тема разговора
enum BufferConversationTopic {
    case programming
    case technical
    case work
    case casual
    case unknown
    
    var description: String {
        switch self {
        case .programming:
            return "Programming"
        case .technical:
            return "Technical"
        case .work:
            return "Work"
        case .casual:
            return "Casual"
        case .unknown:
            return "Unknown"
        }
    }
}

/// Анализ отдельного слова
struct WordAnalysis {
    var suggestedLanguage: Language?
    var confidence: Double = 0.5
    var containsCyrillic: Bool = false
    var containsLatin: Bool = false
}