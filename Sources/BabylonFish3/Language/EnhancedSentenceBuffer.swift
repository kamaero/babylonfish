import Foundation

/// Улучшенный буфер предложений с анализом границ предложений
class EnhancedSentenceBuffer {
    
    /// Запись в буфере предложения
    struct SentenceRecord {
        let text: String
        let language: Language
        let timestamp: Date
        let wordCount: Int
        let isComplete: Bool  // Завершено ли предложение (есть точка и т.д.)
        
        init(text: String, language: Language, isComplete: Bool = false) {
            self.text = text
            self.language = language
            self.timestamp = Date()
            self.wordCount = text.split(separator: " ").count
            self.isComplete = isComplete
        }
        
        var age: TimeInterval {
            Date().timeIntervalSince(timestamp)
        }
    }
    
    /// Границы предложений
    struct SentenceBoundary {
        static let sentenceEnders: Set<Character> = [".", "!", "?", "…", "。", "！", "？"]
        static let sentenceSeparators: Set<Character> = [",", ";", ":", "，", "；", "："]
        
        /// Проверяет, завершает ли символ предложение
        static func isSentenceEnder(_ char: Character) -> Bool {
            sentenceEnders.contains(char)
        }
        
        /// Проверяет, является ли символ разделителем предложений
        static func isSentenceSeparator(_ char: Character) -> Bool {
            sentenceSeparators.contains(char)
        }
        
        /// Проверяет, содержит ли текст границу предложения
        static func containsSentenceBoundary(_ text: String) -> Bool {
            for char in text {
                if isSentenceEnder(char) || isSentenceSeparator(char) {
                    return true
                }
            }
            return false
        }
        
        /// Разделяет текст на предложения
        static func splitIntoSentences(_ text: String) -> [String] {
            var sentences: [String] = []
            var currentSentence = ""
            
            for char in text {
                currentSentence.append(char)
                if isSentenceEnder(char) {
                    sentences.append(currentSentence.trimmingCharacters(in: .whitespaces))
                    currentSentence = ""
                }
            }
            
            // Добавляем последнее неполное предложение
            if !currentSentence.isEmpty {
                sentences.append(currentSentence.trimmingCharacters(in: .whitespaces))
            }
            
            return sentences
        }
    }
    
    // Конфигурация
    private let maxSentences: Int
    private let maxAge: TimeInterval
    private let maxTotalWords: Int
    
    // Буфер предложений
    private var sentences: [SentenceRecord] = []
    
    // Текущее накапливаемое предложение
    private var currentSentenceText: String = ""
    private var currentSentenceLanguage: Language?
    private var currentSentenceStartTime: Date = Date()
    
    // Статистика
    private var totalWordsProcessed: Int = 0
    private var languageDistribution: [Language: Int] = [:]
    private var sentenceBoundariesDetected: Int = 0
    
    /// Инициализирует улучшенный буфер предложений
    init(maxSentences: Int = 10, maxAge: TimeInterval = 300, maxTotalWords: Int = 100) {
        self.maxSentences = maxSentences
        self.maxAge = maxAge
        self.maxTotalWords = maxTotalWords
        
        logDebug("EnhancedSentenceBuffer initialized with sentence boundary detection")
    }
    
    // MARK: - Public API
    
    /// Добавляет текст в буфер с анализом границ предложений
    func addText(_ text: String, language: Language) {
        // Проверяем, содержит ли текст границу предложения
        if SentenceBoundary.containsSentenceBoundary(text) {
            sentenceBoundariesDetected += 1
            
            // Разделяем на предложения
            let sentencesInText = SentenceBoundary.splitIntoSentences(text)
            
            for (index, sentence) in sentencesInText.enumerated() {
                let isComplete = index < sentencesInText.count - 1 || 
                                 SentenceBoundary.isSentenceEnder(sentence.last ?? Character(""))
                
                if !sentence.isEmpty {
                    addSentence(sentence, language: language, isComplete: isComplete)
                }
            }
            
            // Сбрасываем текущее накапливаемое предложение
            resetCurrentSentence()
        } else {
            // Нет границы предложения - добавляем к текущему предложению
            addToCurrentSentence(text, language: language)
        }
    }
    
    /// Добавляет слово в контекст
    func addWord(_ word: String, language: Language) {
        addText(word, language: language)
    }
    
    /// Получает контекст для текущего слова с учетом границ предложений
    func getContext(forWord word: String? = nil) -> EnhancedSentenceContext {
        cleanupOldEntries()
        
        var context = EnhancedSentenceContext()
        
        // Добавляем последние завершенные предложения
        let recentCompleteSentences = sentences
            .filter { $0.isComplete }
            .suffix(3)
        context.recentCompleteSentences = Array(recentCompleteSentences)
        
        // Добавляем текущее незавершенное предложение (если есть)
        if !currentSentenceText.isEmpty, let currentLanguage = currentSentenceLanguage {
            let currentRecord = SentenceRecord(
                text: currentSentenceText,
                language: currentLanguage,
                isComplete: false
            )
            context.currentIncompleteSentence = currentRecord
        }
        
        // Анализируем языковое распределение в текущем предложении
        if let word = word, let currentLanguage = currentSentenceLanguage {
            context.languageConsistency = analyzeLanguageConsistency(
                word: word,
                wordLanguage: currentLanguage,
                contextSentences: context.recentCompleteSentences
            )
        }
        
        // Статистика
        context.totalSentences = sentences.count
        context.completeSentences = sentences.filter { $0.isComplete }.count
        context.sentenceBoundariesDetected = sentenceBoundariesDetected
        
        logDebug("Enhanced context: \(context.completeSentences) complete sentences, \(context.currentIncompleteSentence?.text ?? "none") current")
        
        return context
    }
    
    /// Сбрасывает текущее предложение (например, после длинной паузы)
    func resetCurrentSentence() {
        if !currentSentenceText.isEmpty, let language = currentSentenceLanguage {
            // Сохраняем незавершенное предложение
            addSentence(currentSentenceText, language: language, isComplete: false)
        }
        
        currentSentenceText = ""
        currentSentenceLanguage = nil
        currentSentenceStartTime = Date()
    }
    
    /// Проверяет, не устарело ли текущее предложение
    func checkCurrentSentenceAge() -> Bool {
        let age = Date().timeIntervalSince(currentSentenceStartTime)
        return age > 30  // 30 секунд - максимальное время для одного предложения
    }
    
    // MARK: - Private Methods
    
    /// Добавляет предложение в буфер
    private func addSentence(_ text: String, language: Language, isComplete: Bool) {
        // Очищаем старые записи перед добавлением
        cleanupOldEntries()
        
        let record = SentenceRecord(text: text, language: language, isComplete: isComplete)
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
        
        logDebug("Enhanced sentence added: '\(text)' (\(language), complete: \(isComplete)), buffer: \(sentences.count) sentences")
    }
    
    /// Добавляет текст к текущему накапливаемому предложению
    private func addToCurrentSentence(_ text: String, language: Language) {
        // Проверяем возраст текущего предложения
        if checkCurrentSentenceAge() {
            resetCurrentSentence()
        }
        
        // Если язык изменился, начинаем новое предложение
        if let currentLanguage = currentSentenceLanguage, currentLanguage != language {
            resetCurrentSentence()
        }
        
        // Добавляем текст
        if currentSentenceText.isEmpty {
            currentSentenceText = text
        } else {
            currentSentenceText += " " + text
        }
        
        currentSentenceLanguage = language
        
        logDebug("Added to current sentence: '\(text)' (\(language)), current: '\(currentSentenceText)'")
    }
    
    /// Анализирует согласованность языка слова с контекстом
    private func analyzeLanguageConsistency(
        word: String,
        wordLanguage: Language,
        contextSentences: [SentenceRecord]
    ) -> LanguageConsistency {
        
        guard !contextSentences.isEmpty else {
            return .neutral  // Нет контекста
        }
        
        // Анализируем языки в последних предложениях
        var languageCounts: [Language: Int] = [:]
        for sentence in contextSentences {
            languageCounts[sentence.language, default: 0] += 1
        }
        
        // Определяем доминирующий язык в контексте
        let dominantLanguage = languageCounts.max(by: { $0.value < $1.value })?.key
        
        guard let dominant = dominantLanguage else {
            return .neutral
        }
        
        if wordLanguage == dominant {
            return .consistent
        } else {
            // Проверяем, является ли это смешанным предложением
            let mixedLanguageCount = Set(languageCounts.keys).count
            if mixedLanguageCount > 1 {
                return .mixed  // Смешанный контекст
            } else {
                return .inconsistent  // Несогласованный язык
            }
        }
    }
    
    /// Удаляет самое старое предложение
    private func removeOldestSentence() {
        guard !sentences.isEmpty else { return }
        
        let oldest = sentences.removeFirst()
        totalWordsProcessed -= oldest.wordCount
        
        // Обновляем распределение языков
        if let count = languageDistribution[oldest.language], count > 1 {
            languageDistribution[oldest.language] = count - 1
        } else {
            languageDistribution.removeValue(forKey: oldest.language)
        }
    }
    
    /// Очищает старые записи
    private func cleanupOldEntries() {
        let now = Date()
        sentences = sentences.filter { record in
            let age = now.timeIntervalSince(record.timestamp)
            return age <= maxAge
        }
        
        // Пересчитываем статистику
        totalWordsProcessed = sentences.reduce(0) { $0 + $1.wordCount }
        
        // Обновляем распределение языков
        languageDistribution = [:]
        for sentence in sentences {
            languageDistribution[sentence.language, default: 0] += 1
        }
    }
    
    /// Получает статистику буфера
    func getStatistics() -> [String: Any] {
        return [
            "totalSentences": sentences.count,
            "completeSentences": sentences.filter { $0.isComplete }.count,
            "incompleteSentences": sentences.filter { !$0.isComplete }.count,
            "languageDistribution": getLanguageDistribution(),
            "lastUpdateTime": Date().timeIntervalSince1970
        ]
    }
    
    /// Очищает буфер
    func clear() {
        sentences.removeAll()
        currentSentenceText = ""
        currentSentenceLanguage = nil
        currentSentenceStartTime = Date()
        totalWordsProcessed = 0
        languageDistribution = [:]
        sentenceBoundariesDetected = 0
        logDebug("EnhancedSentenceBuffer cleared")
    }
    
    /// Получает распределение языков
    private func getLanguageDistribution() -> [String: Int] {
        var distribution: [String: Int] = [:]
        
        for sentence in sentences {
            distribution[sentence.language.rawValue, default: 0] += 1
        }
        
        return distribution
    }
}

/// Контекст предложения с улучшенной информацией
struct EnhancedSentenceContext {
    var recentCompleteSentences: [EnhancedSentenceBuffer.SentenceRecord] = []
    var currentIncompleteSentence: EnhancedSentenceBuffer.SentenceRecord?
    var languageConsistency: LanguageConsistency = .neutral
    var totalSentences: Int = 0
    var completeSentences: Int = 0
    var sentenceBoundariesDetected: Int = 0
    
    /// Доминирующий язык в контексте
    var dominantLanguage: Language? {
        let languages = recentCompleteSentences.map { $0.language }
        guard !languages.isEmpty else { return nil }
        
        var counts: [Language: Int] = [:]
        for language in languages {
            counts[language, default: 0] += 1
        }
        
        return counts.max(by: { $0.value < $1.value })?.key
    }
    
    /// Уверенность в доминирующем языке
    var dominantLanguageConfidence: Double {
        guard let dominant = dominantLanguage, !recentCompleteSentences.isEmpty else {
            return 0
        }
        
        let dominantCount = recentCompleteSentences.filter { $0.language == dominant }.count
        return Double(dominantCount) / Double(recentCompleteSentences.count)
    }
    
    /// Следует ли использовать контекст для определения языка
    var shouldUseContext: Bool {
        // Используем контекст только если есть завершенные предложения
        // и уверенность в доминирующем языке высокая
        return completeSentences >= 1 && dominantLanguageConfidence >= 0.7
    }
}

/// Согласованность языка
enum LanguageConsistency {
    case consistent      // Язык слова согласуется с контекстом
    case inconsistent    // Язык слова не согласуется с контекстом
    case mixed          // Смешанный контекст (разные языки)
    case neutral        // Недостаточно контекста для анализа
}