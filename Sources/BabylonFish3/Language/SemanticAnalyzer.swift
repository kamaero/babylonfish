import Foundation

/// Семантический анализатор для определения темы и контекста
class SemanticAnalyzer {
    
    // Словари тем
    private let programmingKeywords: Set<String>
    private let technicalKeywords: Set<String>
    private let workKeywords: Set<String>
    private let casualKeywords: Set<String>
    private let russianSpecificKeywords: Set<String>
    
    // Веса для разных типов ключевых слов
    private let programmingWeight = 2.0
    private let technicalWeight = 1.5
    private let workWeight = 1.2
    private let casualWeight = 1.0
    
    // Статистика
    private var analysisCount: Int = 0
    private var topicDistribution: [ConversationTopic: Int] = [:]
    
    /// Инициализирует семантический анализатор
    init() {
        // Инициализируем словари
        programmingKeywords = Set(LanguageConstants.programmingKeywords)
        
        technicalKeywords = [
            "computer", "software", "hardware", "network", "system", "code", "program",
            "algorithm", "database", "server", "client", "protocol", "interface",
            "компьютер", "программа", "система", "сеть", "база", "данных", "сервер"
        ]
        
        workKeywords = [
            "meeting", "project", "deadline", "report", "email", "client", "work",
            "office", "colleague", "boss", "salary", "task", "schedule",
            "встреча", "проект", "дедлайн", "отчет", "клиент", "работа",
            "офис", "коллега", "начальник", "зарплата", "задача"
        ]
        
        casualKeywords = [
            "hello", "hi", "how", "are", "you", "thanks", "please", "sorry",
            "good", "bad", "yes", "no", "maybe", "today", "tomorrow",
            "привет", "здравствуй", "как", "дела", "спасибо", "пожалуйста",
            "извини", "хорошо", "плохо", "да", "нет", "может", "сегодня", "завтра"
        ]
        
        russianSpecificKeywords = [
            "спасибо", "пожалуйста", "извините", "здравствуйте", "до свидания",
            "пока", "привет", "как дела", "что нового", "всего хорошего",
            "благодарю", "прошу", "извиняюсь", "добрый день", "доброе утро"
        ]
    }
    
    // MARK: - Public API
    
    /// Анализирует текст и определяет тему
    func analyzeText(_ text: String, language: Language? = nil) -> SemanticAnalysis {
        analysisCount += 1
        
        let lowercasedText = text.lowercased()
        let words = extractWords(from: lowercasedText)
        
        // Анализируем тему
        let topic = determineTopic(words: words, fullText: lowercasedText)
        
        // Определяем язык если не указан
        let detectedLanguage = language ?? detectLanguage(from: lowercasedText)
        
        // Анализируем тон
        let tone = analyzeTone(words: words)
        
        // Определяем вероятный контекст
        let context = determineContext(topic: topic, language: detectedLanguage, tone: tone)
        
        // Обновляем статистику
        topicDistribution[topic, default: 0] += 1
        
        return SemanticAnalysis(
            topic: topic,
            language: detectedLanguage,
            tone: tone,
            context: context,
            confidence: calculateConfidence(words: words, topic: topic),
            keywords: extractKeywords(words: words, topic: topic)
        )
    }
    
    /// Анализирует несколько предложений для определения общей темы
    func analyzeConversation(_ sentences: [String]) -> ConversationAnalysis {
        guard !sentences.isEmpty else {
            return ConversationAnalysis(
                primaryTopic: .unknown,
                languageMix: .monolingual(language: .english),
                tone: .neutral,
                consistency: 0,
                topics: []
            )
        }
        
        var analyses: [SemanticAnalysis] = []
        var topicCounts: [ConversationTopic: Int] = [:]
        var languageCounts: [Language: Int] = [:]
        var toneScores: [Tone: Int] = [:]
        
        // Анализируем каждое предложение
        for sentence in sentences {
            let analysis = analyzeText(sentence)
            analyses.append(analysis)
            
            topicCounts[analysis.topic, default: 0] += 1
            languageCounts[analysis.language, default: 0] += 1
            toneScores[analysis.tone, default: 0] += 1
        }
        
        // Определяем основную тему
        let primaryTopic = topicCounts.max(by: { $0.value < $1.value })?.key ?? .unknown
        
        // Определяем смешение языков
        let languageMix = determineLanguageMix(languageCounts: languageCounts)
        
        // Определяем общий тон
        let overallTone = determineOverallTone(toneScores: toneScores)
        
        // Рассчитываем консистентность
        let consistency = calculateConsistency(analyses: analyses)
        
        return ConversationAnalysis(
            primaryTopic: primaryTopic,
            languageMix: languageMix,
            tone: overallTone,
            consistency: consistency,
            topics: analyses.map { $0.topic }
        )
    }
    
    /// Определяет, является ли текст техническим/программистским
    func isTechnicalText(_ text: String) -> Bool {
        let analysis = analyzeText(text)
        return analysis.topic == .programming || analysis.topic == .technical
    }
    
    /// Определяет, является ли текст casual/разговорным
    func isCasualText(_ text: String) -> Bool {
        let analysis = analyzeText(text)
        return analysis.topic == .casual
    }
    
    /// Получает статистику анализатора
    func getStatistics() -> [String: Any] {
        return [
            "totalAnalyses": analysisCount,
            "topicDistribution": topicDistribution.map { ["topic": $0.key.description, "count": $0.value] },
            "mostCommonTopic": topicDistribution.max(by: { $0.value < $1.value })?.key.description ?? "None"
        ]
    }
    
    /// Очищает статистику
    func clearStatistics() {
        analysisCount = 0
        topicDistribution.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func extractWords(from text: String) -> [String] {
        // Удаляем пунктуацию и разделяем на слова
        let characterSet = CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
        let words = text.components(separatedBy: characterSet)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        
        return words
    }
    
    private func determineTopic(words: [String], fullText: String) -> ConversationTopic {
        var scores: [ConversationTopic: Double] = [:]
        
        // Проверяем ключевые слова для каждой темы
        for word in words {
            if programmingKeywords.contains(word) {
                scores[.programming, default: 0] += programmingWeight
            }
            if technicalKeywords.contains(word) {
                scores[.technical, default: 0] += technicalWeight
            }
            if workKeywords.contains(word) {
                scores[.work, default: 0] += workWeight
            }
            if casualKeywords.contains(word) {
                scores[.casual, default: 0] += casualWeight
            }
        }
        
        // Проверяем паттерны программирования
        if containsProgrammingPatterns(fullText) {
            scores[.programming, default: 0] += 3.0
        }
        
        // Проверяем русско-специфичные фразы
        if containsRussianSpecificPhrases(fullText) {
            scores[.casual, default: 0] += 2.0
        }
        
        // Находим тему с максимальным score
        if let bestTopic = scores.max(by: { $0.value < $1.value }) {
            // Если score достаточно высокий
            if bestTopic.value >= 2.0 {
                return bestTopic.key
            }
        }
        
        // Если не удалось определить, проверяем длину текста
        if words.count <= 3 {
            // Короткие тексты часто casual
            return .casual
        }
        
        return .unknown
    }
    
    private func containsProgrammingPatterns(_ text: String) -> Bool {
        // Паттерны программирования
        let patterns = [
            "function\\s+\\w+", "class\\s+\\w+", "var\\s+\\w+", "let\\s+\\w+",
            "if\\s*\\(.*\\)", "for\\s*\\(.*\\)", "while\\s*\\(.*\\)",
            "return\\s+", "import\\s+", "export\\s+", "public\\s+", "private\\s+"
        ]
        
        for pattern in patterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        return false
    }
    
    private func containsRussianSpecificPhrases(_ text: String) -> Bool {
        for phrase in russianSpecificKeywords {
            if text.contains(phrase) {
                return true
            }
        }
        return false
    }
    
    private func detectLanguage(from text: String) -> Language {
        // Проверяем наличие кириллицы
        let hasCyrillic = text.contains { char in
            let scalar = String(char).unicodeScalars.first?.value ?? 0
            return (0x0400...0x04FF).contains(scalar)
        }
        
        // Проверяем наличие латиницы
        let hasLatin = text.contains { char in
            let scalar = String(char).unicodeScalars.first?.value ?? 0
            return (0x0041...0x007A).contains(scalar)
        }
        
        if hasCyrillic && !hasLatin {
            return .russian
        } else if hasLatin && !hasCyrillic {
            return .english
        } else if hasCyrillic && hasLatin {
            // Смешанный текст - смотрим что преобладает
            let cyrillicCount = text.filter { char in
                let scalar = String(char).unicodeScalars.first?.value ?? 0
                return (0x0400...0x04FF).contains(scalar)
            }.count
            
            let latinCount = text.filter { char in
                let scalar = String(char).unicodeScalars.first?.value ?? 0
                return (0x0041...0x007A).contains(scalar)
            }.count
            
            return cyrillicCount > latinCount ? .russian : .english
        }
        
        // По умолчанию английский
        return .english
    }
    
    private func analyzeTone(words: [String]) -> Tone {
        // Положительные слова
        let positiveWords: Set<String> = [
            "good", "great", "excellent", "awesome", "perfect", "thanks", "thank",
            "хорошо", "отлично", "прекрасно", "замечательно", "спасибо"
        ]
        
        // Отрицательные слова
        let negativeWords: Set<String> = [
            "bad", "terrible", "awful", "sorry", "problem", "issue", "error",
            "плохо", "ужасно", "кошмар", "извините", "проблема", "ошибка"
        ]
        
        // Формальные слова
        let formalWords: Set<String> = [
            "please", "would", "could", "should", "kindly", "regards",
            "пожалуйста", "будьте", "любезны", "уважаемый", "с уважением"
        ]
        
        var positiveScore = 0
        var negativeScore = 0
        var formalScore = 0
        
        for word in words {
            if positiveWords.contains(word) {
                positiveScore += 1
            }
            if negativeWords.contains(word) {
                negativeScore += 1
            }
            if formalWords.contains(word) {
                formalScore += 1
            }
        }
        
        // Определяем тон
        if positiveScore > negativeScore && positiveScore > 0 {
            return .positive
        } else if negativeScore > positiveScore && negativeScore > 0 {
            return .negative
        } else if formalScore > 2 {
            return .formal
        } else if words.count <= 5 {
            return .brief
        }
        
        return .neutral
    }
    
    private func determineContext(topic: ConversationTopic, language: Language, tone: Tone) -> SemanticContext {
        var context = SemanticContext()
        
        // Определяем domain на основе темы
        switch topic {
        case .programming:
            context.domain = .programming
            context.suggestedLanguage = .english // Программирование обычно на английском
        case .technical:
            context.domain = .technical
            context.suggestedLanguage = language
        case .work:
            context.domain = .work
            context.suggestedLanguage = language
        case .casual:
            context.domain = .casual
            context.suggestedLanguage = language
        case .unknown:
            context.domain = .general
            context.suggestedLanguage = language
        }
        
        // Учитываем тон
        context.isFormal = tone == .formal
        context.isBrief = tone == .brief
        
        return context
    }
    
    private func calculateConfidence(words: [String], topic: ConversationTopic) -> Double {
        guard !words.isEmpty else { return 0 }
        
        var confidence = 0.5
        
        // Увеличиваем уверенность при большом количестве слов
        if words.count >= 5 {
            confidence += 0.2
        }
        
        // Увеличиваем уверенность для определенных тем
        if topic != .unknown {
            confidence += 0.2
        }
        
        // Уменьшаем уверенность для очень коротких текстов
        if words.count <= 2 {
            confidence -= 0.3
        }
        
        return min(max(confidence, 0.1), 0.95)
    }
    
    private func extractKeywords(words: [String], topic: ConversationTopic) -> [String] {
        var keywords: Set<String> = []
        
        // Добавляем слова, относящиеся к теме
        let topicKeywords: Set<String>
        switch topic {
        case .programming:
            topicKeywords = programmingKeywords
        case .technical:
            topicKeywords = technicalKeywords
        case .work:
            topicKeywords = workKeywords
        case .casual:
            topicKeywords = casualKeywords
        case .unknown:
            topicKeywords = []
        }
        
        for word in words {
            if topicKeywords.contains(word) {
                keywords.insert(word)
            }
        }
        
        // Ограничиваем количество ключевых слов
        return Array(keywords).prefix(5).map { $0 }
    }
    
    private func determineLanguageMix(languageCounts: [Language: Int]) -> LanguageMix {
        let total = languageCounts.values.reduce(0, +)
        guard total > 0 else { return .monolingual(language: .english) }
        
        if languageCounts.count == 1 {
            let language = languageCounts.keys.first!
            return .monolingual(language: language)
        } else {
            let primaryLanguage = languageCounts.max(by: { $0.value < $1.value })!.key
            let primaryPercentage = Double(languageCounts[primaryLanguage]!) / Double(total)
            
            if primaryPercentage >= 0.8 {
                return .mostlyMonolingual(language: primaryLanguage)
            } else if primaryPercentage >= 0.6 {
                return .bilingual(primary: primaryLanguage, secondary: .english)
            } else {
                return .mixed
            }
        }
    }
    
    private func determineOverallTone(toneScores: [Tone: Int]) -> Tone {
        guard !toneScores.isEmpty else { return .neutral }
        
        return toneScores.max(by: { $0.value < $1.value })?.key ?? .neutral
    }
    
    private func calculateConsistency(analyses: [SemanticAnalysis]) -> Double {
        guard analyses.count >= 2 else { return 1.0 }
        
        var consistentPairs = 0
        var totalPairs = 0
        
        for i in 0..<(analyses.count - 1) {
            for j in (i + 1)..<analyses.count {
                totalPairs += 1
                
                // Считаем пару consistent если темы совпадают
                if analyses[i].topic == analyses[j].topic {
                    consistentPairs += 1
                }
            }
        }
        
        return totalPairs > 0 ? Double(consistentPairs) / Double(totalPairs) : 1.0
    }
}

// MARK: - Вспомогательные структуры

/// Семантический анализ текста
struct SemanticAnalysis {
    let topic: ConversationTopic
    let language: Language
    let tone: Tone
    let context: SemanticContext
    let confidence: Double
    let keywords: [String]
    
    var description: String {
        return "\(topic) (\(language), \(tone), \(String(format: "%.0f", confidence * 100))%)"
    }
}

/// Анализ разговора (нескольких предложений)
struct ConversationAnalysis {
    let primaryTopic: ConversationTopic
    let languageMix: LanguageMix
    let tone: Tone
    let consistency: Double
    let topics: [ConversationTopic]
    
    var description: String {
        return "\(primaryTopic), \(languageMix), \(tone), consistency: \(String(format: "%.0f", consistency * 100))%"
    }
}

/// Семантический контекст
struct SemanticContext {
    var domain: SemanticDomain = .general
    var suggestedLanguage: Language = .english
    var isFormal: Bool = false
    var isBrief: Bool = false
}

/// Семантический домен
enum SemanticDomain {
    case programming
    case technical
    case work
    case casual
    case general
    
    var description: String {
        switch self {
        case .programming: return "Programming"
        case .technical: return "Technical"
        case .work: return "Work"
        case .casual: return "Casual"
        case .general: return "General"
        }
    }
}

/// Тон текста
enum Tone {
    case positive
    case negative
    case neutral
    case formal
    case brief
    
    var description: String {
        switch self {
        case .positive: return "Positive"
        case .negative: return "Negative"
        case .neutral: return "Neutral"
        case .formal: return "Formal"
        case .brief: return "Brief"
        }
    }
}

/// Смешение языков
enum LanguageMix {
    case monolingual(language: Language)
    case mostlyMonolingual(language: Language)
    case bilingual(primary: Language, secondary: Language)
    case mixed
    
    var description: String {
        switch self {
        case .monolingual(let lang):
            return "Monolingual (\(lang))"
        case .mostlyMonolingual(let lang):
            return "Mostly \(lang)"
        case .bilingual(let primary, let secondary):
            return "Bilingual (\(primary) + \(secondary))"
        case .mixed:
            return "Mixed languages"
        }
    }
}

/// Тема разговора
enum ConversationTopic {
    case programming
    case technical
    case work
    case casual
    case unknown
    
    var description: String {
        switch self {
        case .programming: return "Programming"
        case .technical: return "Technical"
        case .work: return "Work"
        case .casual: return "Casual"
        case .unknown: return "Unknown"
        }
    }
}