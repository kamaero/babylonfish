import Foundation
import Cocoa

/// Анализатор контекста - объединяет все контекстные компоненты
class ContextAnalyzer {
    
    // Компоненты контекста
    private let sentenceBuffer: SentenceBuffer
    private let semanticAnalyzer: SemanticAnalyzer
    private let enhancedLanguageDetector: EnhancedLanguageDetector
    
    // Конфигурация
    private var isEnabled: Bool = true
    private var contextWeight: Double = 0.6
    private var semanticWeight: Double = 0.2
    private var languageWeight: Double = 0.2
    
    // Состояние
    private var currentTopic: ConversationTopic = .unknown
    private var currentTone: Tone = .neutral
    private var languageTrend: LanguageTrend = .neutral
    private var lastUpdateTime: Date = Date()
    
    // Статистика
    private var analysisCount: Int = 0
    private var contextUsedCount: Int = 0
    private var topicChanges: Int = 0
    
    /// Инициализирует анализатор контекста
    init(
        sentenceBuffer: SentenceBuffer = SentenceBuffer(),
        semanticAnalyzer: SemanticAnalyzer = SemanticAnalyzer(),
        enhancedLanguageDetector: EnhancedLanguageDetector = EnhancedLanguageDetector()
    ) {
        self.sentenceBuffer = sentenceBuffer
        self.semanticAnalyzer = semanticAnalyzer
        self.enhancedLanguageDetector = enhancedLanguageDetector
        
        logDebug("ContextAnalyzer initialized")
    }
    
    // MARK: - Public API
    
    /// Анализирует контекст для текста
    func analyzeContext(for text: String, externalContext: DetectionContext? = nil) -> ContextAnalysisResult {
        analysisCount += 1
        
        guard isEnabled else {
            return ContextAnalysisResult(
                suggestedLanguage: nil,
                confidence: 0,
                topic: .unknown,
                tone: .neutral,
                languageTrend: .neutral,
                shouldIgnore: false,
                method: .unknown
            )
        }
        
        // Анализируем семантику
        let semanticResult = semanticAnalyzer.analyzeText(text)
        
        // Обновляем текущую тему если изменилась
        updateTopicIfNeeded(semanticResult.topic)
        
        // Обновляем тон
        currentTone = semanticResult.tone
        
        // Анализируем языковые тренды
        updateLanguageTrends()
        
        // Детектируем язык с учетом контекста
        let languageResult = detectLanguageWithContext(
            text: text,
            semanticResult: semanticResult,
            externalContext: externalContext
        )
        
        // Обновляем буфер если язык определен
        if let language = languageResult.suggestedLanguage {
            sentenceBuffer.addWord(text, language: language)
            contextUsedCount += 1
        }
        
        return ContextAnalysisResult(
            suggestedLanguage: languageResult.suggestedLanguage,
            confidence: languageResult.confidence,
            topic: currentTopic,
            tone: currentTone,
            languageTrend: languageTrend,
            shouldIgnore: languageResult.shouldIgnore,
            method: languageResult.method
        )
    }
    
    /// Обновляет контекст после ввода
    func updateContext(text: String, language: Language) {
        sentenceBuffer.addWord(text, language: language)
        
        // Обновляем семантический анализ
        let semanticResult = semanticAnalyzer.analyzeText(text)
        updateTopicIfNeeded(semanticResult.topic)
        currentTone = semanticResult.tone
        
        logDebug("Context updated: '\(text)' → \(language), topic: \(currentTopic)")
    }
    
    /// Получает текущий контекст
    func getCurrentContext() -> CurrentContext {
        let bufferStats = sentenceBuffer.getStatistics()
        let semanticStats = semanticAnalyzer.getStatistics()
        
        return CurrentContext(
            topic: currentTopic,
            tone: currentTone,
            languageTrend: languageTrend,
            bufferSize: bufferStats["totalWords"] as? Int ?? 0,
            languageDistribution: bufferStats["languageDistribution"] as? [String: Int] ?? [:],
            semanticConfidence: semanticStats["avgConfidence"] as? Double ?? 0,
            lastUpdate: lastUpdateTime
        )
    }
    
    /// Настраивает анализатор
    func configure(
        isEnabled: Bool? = nil,
        contextWeight: Double? = nil,
        semanticWeight: Double? = nil,
        languageWeight: Double? = nil
    ) {
        if let isEnabled = isEnabled {
            self.isEnabled = isEnabled
        }
        if let contextWeight = contextWeight {
            self.contextWeight = max(0, min(1, contextWeight))
        }
        if let semanticWeight = semanticWeight {
            self.semanticWeight = max(0, min(1, semanticWeight))
        }
        if let languageWeight = languageWeight {
            self.languageWeight = max(0, min(1, languageWeight))
        }
        
        // Нормализуем веса
        let totalWeight = self.contextWeight + self.semanticWeight + self.languageWeight
        if totalWeight > 0 {
            self.contextWeight /= totalWeight
            self.semanticWeight /= totalWeight
            self.languageWeight /= totalWeight
        }
        
        logDebug("ContextAnalyzer configured: enabled=\(self.isEnabled), weights: context=\(String(format: "%.2f", self.contextWeight)), semantic=\(String(format: "%.2f", self.semanticWeight)), language=\(String(format: "%.2f", self.languageWeight))")
    }
    
    /// Очищает контекст
    func clearContext() {
        sentenceBuffer.clear()
        semanticAnalyzer.clearStatistics()
        currentTopic = .unknown
        currentTone = .neutral
        languageTrend = .neutral
        lastUpdateTime = Date()
        
        logDebug("Context cleared")
    }
    
    /// Получает статистику
    func getStatistics() -> [String: Any] {
        let contextUsageRate = analysisCount > 0 ? Double(contextUsedCount) / Double(analysisCount) : 0
        
        return [
            "totalAnalyses": analysisCount,
            "contextUsedCount": contextUsedCount,
            "contextUsageRate": contextUsageRate,
            "topicChanges": topicChanges,
            "currentTopic": currentTopic.description,
            "currentTone": currentTone.description,
            "languageTrend": languageTrend.rawValue,
            "configuration": [
                "isEnabled": isEnabled,
                "contextWeight": contextWeight,
                "semanticWeight": semanticWeight,
                "languageWeight": languageWeight
            ],
            "sentenceBuffer": sentenceBuffer.getStatistics(),
            "semanticAnalyzer": semanticAnalyzer.getStatistics(),
            "languageDetector": enhancedLanguageDetector.getStatistics()
        ]
    }
    
    /// Проверяет, нужно ли игнорировать ввод на основе контекста
    func shouldIgnoreInput(text: String, externalContext: DetectionContext? = nil) -> Bool {
        // Проверяем secure field
        if let external = externalContext, external.isSecureField {
            return true
        }
        
        // Проверяем короткие слова (менее 3 символов)
        if text.count < 3 {
            return true
        }
        
        // Проверяем специальные символы (пароли, команды)
        let specialCharacterPatterns = ["/", "\\", "@", "#", "$", "%", "^", "&", "*", "(", ")", "-", "_", "=", "+"]
        if specialCharacterPatterns.contains(where: { text.contains($0) }) {
            return true
        }
        
        // Проверяем числовые вводы
        if text.allSatisfy({ $0.isNumber }) {
            return true
        }
        
        return false
    }
    
    // MARK: - Private Methods
    
    private func detectLanguageWithContext(
        text: String,
        semanticResult: SemanticAnalysis,
        externalContext: DetectionContext?
    ) -> LanguageDetectionWithContext {
        
        // Проверяем, нужно ли игнорировать
        if shouldIgnoreInput(text: text, externalContext: externalContext) {
            return LanguageDetectionWithContext(
                suggestedLanguage: nil,
                confidence: 0,
                shouldIgnore: true,
                method: .contextIgnored
            )
        }
        
        // Конвертируем текст в коды клавиш (упрощенно)
        let keyCodes = convertTextToKeyCodes(text)
        
        // Детектируем язык с помощью улучшенного детектора
        let detectionResult = enhancedLanguageDetector.detectLanguage(for: keyCodes, context: externalContext)
        
        // Если уверенность высокая, возвращаем результат
        if detectionResult.isConfident {
            return LanguageDetectionWithContext(
                suggestedLanguage: detectionResult.language,
                confidence: detectionResult.confidence,
                shouldIgnore: false,
                method: detectionResult.method
            )
        }
        
        // Применяем контекстные правила
        
        // 1. Тема разговора влияет на язык
        let topicBias = getTopicLanguageBias(semanticResult.topic)
        
        // 2. Языковой тренд влияет на выбор
        let trendBias = getTrendLanguageBias()
        
        // 3. Внешний контекст (приложение)
        let appBias = getApplicationLanguageBias(externalContext?.applicationType)
        
        // Комбинируем все факторы
        let combinedResult = combineLanguageFactors(
            detectionResult: detectionResult,
            topicBias: topicBias,
            trendBias: trendBias,
            appBias: appBias
        )
        
        return combinedResult
    }
    
    private func convertTextToKeyCodes(_ text: String) -> [Int] {
        // Используем KeyMapper для конвертации текста в коды клавиш
        // Для простоты используем ASCII коды, но в реальной реализации
        // нужно учитывать раскладку клавиатуры
        var keyCodes: [Int] = []
        
        for char in text {
            // Преобразуем символ в его ASCII/Unicode значение
            let scalar = String(char).unicodeScalars.first?.value ?? 0
            
            // Для буквенных символов используем их код
            if char.isLetter {
                // Для английских букв используем их ASCII код
                if let asciiValue = char.asciiValue {
                    keyCodes.append(Int(asciiValue))
                } else {
                    // Для не-ASCII символов (кириллица) используем Unicode скаляр
                    keyCodes.append(Int(scalar))
                }
            } else {
                // Для не-буквенных символов используем их код
                keyCodes.append(Int(scalar))
            }
        }
        
        return keyCodes
    }
    
    private func getTopicLanguageBias(_ topic: ConversationTopic) -> LanguageBias {
        switch topic {
        case .programming, .technical:
            return .english // Программирование и технические темы обычно на английском
        case .work:
            return .neutral // Рабочие темы могут быть на любом языке
        case .casual:
            return .neutral // Повседневные разговоры
        case .unknown:
            return .neutral
        }
    }
    
    private func getTrendLanguageBias() -> LanguageBias {
        switch languageTrend {
        case .strongRussian:
            return .russian
        case .strongEnglish:
            return .english
        case .moderateRussian:
            return .russian
        case .moderateEnglish:
            return .english
        case .mixed:
            return .neutral
        case .neutral:
            return .neutral
        }
    }
    
    private func getApplicationLanguageBias(_ appType: ApplicationType?) -> LanguageBias {
        guard let appType = appType else { return .neutral }
        
        switch appType {
        case .terminal, .ide:
            return .english // Терминалы и IDE обычно на английском
        case .textEditor, .browser:
            return .neutral // Текстовые редакторы и браузеры могут быть на любом языке
        case .game, .other:
            return .neutral
        }
    }
    
    private func combineLanguageFactors(
        detectionResult: LanguageDetectionResult,
        topicBias: LanguageBias,
        trendBias: LanguageBias,
        appBias: LanguageBias
    ) -> LanguageDetectionWithContext {
        
        var scores: [Language: Double] = [:]
        
        // Базовый результат детекции
        if let detectedLang = detectionResult.language {
            scores[detectedLang, default: 0] += detectionResult.confidence * languageWeight
        }
        
        // Bias от темы
        switch topicBias {
        case .english:
            scores[.english, default: 0] += 0.3 * semanticWeight
        case .russian:
            scores[.russian, default: 0] += 0.3 * semanticWeight
        case .neutral:
            break
        }
        
        // Bias от тренда
        switch trendBias {
        case .english:
            scores[.english, default: 0] += 0.4 * contextWeight
        case .russian:
            scores[.russian, default: 0] += 0.4 * contextWeight
        case .neutral:
            break
        }
        
        // Bias от приложения
        switch appBias {
        case .english:
            scores[.english, default: 0] += 0.2
        case .russian:
            scores[.russian, default: 0] += 0.2
        case .neutral:
            break
        }
        
        // Находим язык с максимальным score
        let bestLanguage = scores.max(by: { $0.value < $1.value })
        
        guard let language = bestLanguage?.key, let score = bestLanguage?.value else {
            return LanguageDetectionWithContext(
                suggestedLanguage: nil,
                confidence: 0,
                shouldIgnore: false,
                method: .insufficientData
            )
        }
        
        // Нормализуем confidence
        let confidence = min(max(score, 0.1), 0.95)
        
        // Определяем метод
        let method: DetectionMethod = detectionResult.contextUsed ? .contextual : .combined
        
        return LanguageDetectionWithContext(
            suggestedLanguage: language,
            confidence: confidence,
            shouldIgnore: false,
            method: method
        )
    }
    
    private func updateTopicIfNeeded(_ newTopic: ConversationTopic) {
        if newTopic != currentTopic {
            currentTopic = newTopic
            topicChanges += 1
            lastUpdateTime = Date()
            
            logDebug("Topic changed to: \(newTopic)")
        }
    }
    
    private func updateLanguageTrends() {
        let bufferStats = sentenceBuffer.getStatistics()
        let distribution = bufferStats["languageDistribution"] as? [String: Int] ?? [:]
        
        let ruCount = distribution["russian"] ?? 0
        let enCount = distribution["english"] ?? 0
        let total = ruCount + enCount
        
        guard total > 0 else {
            languageTrend = .neutral
            return
        }
        
        let ruRatio = Double(ruCount) / Double(total)
        let enRatio = Double(enCount) / Double(total)
        
        if ruRatio > 0.8 {
            languageTrend = .strongRussian
        } else if enRatio > 0.8 {
            languageTrend = .strongEnglish
        } else if ruRatio > 0.6 {
            languageTrend = .moderateRussian
        } else if enRatio > 0.6 {
            languageTrend = .moderateEnglish
        } else if abs(ruRatio - enRatio) < 0.2 {
            languageTrend = .mixed
        } else {
            languageTrend = .neutral
        }
    }
}

// MARK: - Вспомогательные структуры

/// Результат анализа контекста
struct ContextAnalysisResult {
    let suggestedLanguage: Language?
    let confidence: Double
    let topic: ConversationTopic
    let tone: Tone
    let languageTrend: LanguageTrend
    let shouldIgnore: Bool
    let method: DetectionMethod
    
    var isConfident: Bool {
        confidence >= 0.7 && !shouldIgnore
    }
    
    var description: String {
        if shouldIgnore {
            return "Ignored by context"
        } else if let lang = suggestedLanguage {
            return "\(lang) (\(String(format: "%.0f", confidence * 100))%) | Topic: \(topic) | Trend: \(languageTrend)"
        } else {
            return "Unknown | Topic: \(topic) | Trend: \(languageTrend)"
        }
    }
}

/// Текущий контекст
struct CurrentContext {
    let topic: ConversationTopic
    let tone: Tone
    let languageTrend: LanguageTrend
    let bufferSize: Int
    let languageDistribution: [String: Int]
    let semanticConfidence: Double
    let lastUpdate: Date
    
    var description: String {
        return """
        Topic: \(topic)
        Tone: \(tone)
        Language Trend: \(languageTrend)
        Buffer: \(bufferSize) words
        Distribution: \(languageDistribution)
        Last update: \(lastUpdate.timeIntervalSinceNow * -1)s ago
        """
    }
}

/// Результат детекции языка с контекстом
struct LanguageDetectionWithContext {
    let suggestedLanguage: Language?
    let confidence: Double
    let shouldIgnore: Bool
    let method: DetectionMethod
}

/// Тренд языка
enum LanguageTrend: String {
    case strongRussian = "Strong Russian"
    case moderateRussian = "Moderate Russian"
    case strongEnglish = "Strong English"
    case moderateEnglish = "Moderate English"
    case mixed = "Mixed"
    case neutral = "Neutral"
}