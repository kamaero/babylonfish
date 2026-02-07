import Foundation
import Cocoa

/// Улучшенный детектор языка с учетом контекста
class EnhancedLanguageDetector {
    
    // Зависимости
    private let sentenceBuffer: SentenceBuffer
    private let systemDictionary: SystemDictionaryService
    private let cacheManager: CacheManager
    private let performanceMonitor: PerformanceMonitor
    
    // Конфигурация
    private var useContext: Bool = true
    private var contextWeight: Double = 0.6
    private var wordWeight: Double = 0.4
    private var minConfidence: Double = 0.7
    
    // Статистика
    private var detectionCount: Int = 0
    private var contextUsedCount: Int = 0
    private var avgConfidence: Double = 0
    
    /// Инициализирует улучшенный детектор языка
    init(
        sentenceBuffer: SentenceBuffer = SentenceBuffer(),
        systemDictionary: SystemDictionaryService = .shared,
        cacheManager: CacheManager = .shared,
        performanceMonitor: PerformanceMonitor = .shared
    ) {
        self.sentenceBuffer = sentenceBuffer
        self.systemDictionary = systemDictionary
        self.cacheManager = cacheManager
        self.performanceMonitor = performanceMonitor
    }
    
    // MARK: - Public API
    
    /// Детектирует язык для последовательности кодов клавиш с учетом контекста
    func detectLanguage(for keyCodes: [Int], context: DetectionContext? = nil) -> LanguageDetectionResult {
        performanceMonitor.startMeasurement("enhancedLanguageDetection")
        defer { performanceMonitor.endMeasurement("enhancedLanguageDetection") }
        
        detectionCount += 1
        
        // Базовые проверки
        guard !keyCodes.isEmpty else {
            return LanguageDetectionResult(
                language: nil,
                confidence: 0,
                method: .insufficientInput,
                contextUsed: false
            )
        }
        
        // Конвертируем коды клавиш в строки
        let (enString, ruString) = convertKeyCodesToStrings(keyCodes)
        
        // Проверяем кэш
        let cacheKey = "\(enString)|\(ruString)"
        if let cached = cacheManager.getCachedLanguageDetection(key: cacheKey) {
            performanceMonitor.recordCacheHit()
            return LanguageDetectionResult(
                language: cached.0,
                confidence: cached.1,
                method: .cached,
                contextUsed: false
            )
        }
        
        performanceMonitor.recordCacheMiss()
        
        // Анализируем без контекста
        let basicAnalysis = analyzeWithoutContext(enString: enString, ruString: ruString)
        
        // Если уверенность высокая, возвращаем результат
        if basicAnalysis.confidence >= minConfidence {
            cacheResult(cacheKey, language: basicAnalysis.language, confidence: basicAnalysis.confidence)
            return LanguageDetectionResult(
                language: basicAnalysis.language,
                confidence: basicAnalysis.confidence,
                method: basicAnalysis.method,
                contextUsed: false
            )
        }
        
        // Используем контекст если включено
        if useContext {
            contextUsedCount += 1
            let contextualAnalysis = analyzeWithContext(
                enString: enString,
                ruString: ruString,
                basicAnalysis: basicAnalysis,
                externalContext: context
            )
            
            cacheResult(cacheKey, language: contextualAnalysis.language, confidence: contextualAnalysis.confidence)
            
            return LanguageDetectionResult(
                language: contextualAnalysis.language,
                confidence: contextualAnalysis.confidence,
                method: contextualAnalysis.method,
                contextUsed: true
            )
        }
        
        // Возвращаем базовый анализ
        return LanguageDetectionResult(
            language: basicAnalysis.language,
            confidence: basicAnalysis.confidence,
            method: basicAnalysis.method,
            contextUsed: false
        )
    }
    
    /// Обновляет контекст после детекции
    func updateContext(word: String, language: Language) {
        sentenceBuffer.addWord(word, language: language)
        logDebug("Context updated: '\(word)' → \(language)")
    }
    
    /// Настраивает параметры детектора
    func configure(useContext: Bool? = nil, contextWeight: Double? = nil, minConfidence: Double? = nil) {
        if let useContext = useContext {
            self.useContext = useContext
        }
        if let contextWeight = contextWeight {
            self.contextWeight = max(0, min(1, contextWeight))
        }
        if let minConfidence = minConfidence {
            self.minConfidence = max(0.1, min(0.95, minConfidence))
        }
        
        logDebug("EnhancedLanguageDetector configured: useContext=\(self.useContext), contextWeight=\(self.contextWeight), minConfidence=\(self.minConfidence)")
    }
    
    /// Получает статистику детектора
    func getStatistics() -> [String: Any] {
        let contextUsageRate = detectionCount > 0 ? Double(contextUsedCount) / Double(detectionCount) : 0
        
        return [
            "totalDetections": detectionCount,
            "contextUsedCount": contextUsedCount,
            "contextUsageRate": contextUsageRate,
            "avgConfidence": avgConfidence,
            "configuration": [
                "useContext": useContext,
                "contextWeight": contextWeight,
                "minConfidence": minConfidence
            ],
            "sentenceBufferStats": sentenceBuffer.getStatistics()
        ]
    }
    
    /// Очищает контекст
    func clearContext() {
        sentenceBuffer.clear()
        logDebug("Language detection context cleared")
    }
    
    // MARK: - Private Methods
    
    private func convertKeyCodesToStrings(_ keyCodes: [Int]) -> (en: String, ru: String) {
        var enString = ""
        var ruString = ""
        
        for code in keyCodes {
            if let chars = KeyMapper.shared.getChars(for: code) {
                enString += chars.en
                ruString += chars.ru
            }
        }
        
        logDebug("Key codes converted: EN='\(enString)', RU='\(ruString)'")
        return (enString, ruString)
    }
    
    private func analyzeWithoutContext(enString: String, ruString: String) -> BasicAnalysis {
        let enLower = enString.lowercased()
        let ruLower = ruString.lowercased()
        
        // 1. Проверка общих слов (быстрый путь)
        if LanguageConstants.commonRuShortWords.contains(ruLower) {
            return BasicAnalysis(language: .russian, confidence: 0.95, method: .commonWords)
        }
        
        if LanguageConstants.commonEnglishWords.contains(enLower) {
            return BasicAnalysis(language: .english, confidence: 0.95, method: .commonWords)
        }
        
        // 2. Проверка ключевых слов программирования
        if LanguageConstants.programmingKeywords.contains(enLower) {
            return BasicAnalysis(language: .english, confidence: 0.98, method: .programmingKeywords)
        }
        
        // 3. Проверка системного словаря
        let isRuValid = systemDictionary.isRussianWord(ruLower)
        let isEnValid = systemDictionary.isEnglishWord(enLower)
        
        if isRuValid && !isEnValid {
            return BasicAnalysis(language: .russian, confidence: 0.9, method: .dictionary)
        }
        
        if isEnValid && !isRuValid {
            return BasicAnalysis(language: .english, confidence: 0.9, method: .dictionary)
        }
        
        if isRuValid && isEnValid {
            // Оба варианта valid - нужен дополнительный анализ
            return analyzeAmbiguousCase(enString: enString, ruString: ruString)
        }
        
        // 4. Анализ биграмм
        let enScore = countBigrams(enString, dictionary: LanguageConstants.commonEnBigrams)
        let ruScore = countBigrams(ruString, dictionary: LanguageConstants.commonRuBigrams)
        
        if ruScore > 0 && enScore == 0 {
            return BasicAnalysis(language: .russian, confidence: 0.8, method: .bigrams)
        }
        
        if enScore > 0 && ruScore == 0 {
            return BasicAnalysis(language: .english, confidence: 0.8, method: .bigrams)
        }
        
        if ruScore > enScore + 1 {
            let confidence = min(0.85, 0.5 + Double(ruScore - enScore) * 0.1)
            return BasicAnalysis(language: .russian, confidence: confidence, method: .bigrams)
        } else if enScore > ruScore + 1 {
            let confidence = min(0.85, 0.5 + Double(enScore - ruScore) * 0.1)
            return BasicAnalysis(language: .english, confidence: confidence, method: .bigrams)
        }
        
        // 5. Невозможные паттерны
        for pattern in LanguageConstants.impossibleRuInEnKeys where pattern.count >= 3 {
            if enString.contains(pattern) {
                return BasicAnalysis(language: .russian, confidence: 0.85, method: .impossiblePatterns)
            }
        }
        
        for pattern in LanguageConstants.impossibleEnInRuKeys where pattern.count >= 4 {
            if ruString.contains(pattern) {
                return BasicAnalysis(language: .english, confidence: 0.85, method: .impossiblePatterns)
            }
        }
        
        // 6. Не удалось определить
        return BasicAnalysis(language: nil, confidence: 0, method: .unknown)
    }
    
    private func analyzeAmbiguousCase(enString: String, ruString: String) -> BasicAnalysis {
        // Для слов, которые valid в обоих языках
        
        // Проверяем длину слова
        if enString.count <= 2 {
            // Короткие слова часто ambiguous
            return BasicAnalysis(language: nil, confidence: 0.3, method: .ambiguous)
        }
        
        // Проверяем наличие специальных символов
        if enString.contains(where: { !$0.isLetter }) {
            // Содержит не-буквы, вероятно английский (программирование)
            return BasicAnalysis(language: .english, confidence: 0.7, method: .specialCharacters)
        }
        
        // Проверяем частотность в словаре
        let enSuggestions = systemDictionary.getEnglishSuggestions(enString)
        let ruSuggestions = systemDictionary.getRussianSuggestions(ruString)
        
        if !enSuggestions.isEmpty && ruSuggestions.isEmpty {
            return BasicAnalysis(language: .english, confidence: 0.75, method: .dictionarySuggestions)
        }
        
        if !ruSuggestions.isEmpty && enSuggestions.isEmpty {
            return BasicAnalysis(language: .russian, confidence: 0.75, method: .dictionarySuggestions)
        }
        
        // Не удалось разрешить ambiguity
        return BasicAnalysis(language: nil, confidence: 0.4, method: .ambiguous)
    }
    
    private func analyzeWithContext(
        enString: String,
        ruString: String,
        basicAnalysis: BasicAnalysis,
        externalContext: DetectionContext?
    ) -> ContextualAnalysis {
        
        // Получаем контекст из буфера
        let bufferContext = sentenceBuffer.getContext(forWord: enString)
        
        // Объединяем с внешним контекстом если есть
        let combinedContext = combineContexts(bufferContext: bufferContext, externalContext: externalContext)
        
        // Анализируем слово отдельно
        let wordAnalysis = analyzeWordAlone(enString: enString, ruString: ruString)
        
        // Комбинируем все факторы
        return combineAnalyses(
            basicAnalysis: basicAnalysis,
            wordAnalysis: wordAnalysis,
            context: combinedContext
        )
    }
    
    private func combineContexts(
        bufferContext: SentenceContext,
        externalContext: DetectionContext?
    ) -> CombinedContext {
        
        var context = CombinedContext()
        
        // Используем контекст из буфера
        context.bufferContext = bufferContext
        
        // Добавляем внешний контекст если есть
        if let external = externalContext {
            context.externalContext = external
            
            // Учитываем тип приложения
            if external.applicationType == .terminal || external.applicationType == .ide {
                context.applicationBias = .english // В терминалах и IDE обычно английский
            } else if external.applicationType == .textEditor || external.applicationType == .browser {
                context.applicationBias = .neutral
            }
            
            // Учитываем secure field
            if external.isSecureField {
                context.shouldIgnore = true
            }
        }
        
        return context
    }
    
    private func analyzeWordAlone(enString: String, ruString: String) -> EnhancedWordAnalysis {
        var analysis = EnhancedWordAnalysis()
        
        // Проверяем наличие кириллицы/латиницы
        let hasCyrillic = ruString.contains { char in
            let scalar = String(char).unicodeScalars.first?.value ?? 0
            return (0x0400...0x04FF).contains(scalar)
        }
        
        let hasLatin = enString.contains { char in
            let scalar = String(char).unicodeScalars.first?.value ?? 0
            return (0x0041...0x007A).contains(scalar)
        }
        
        if hasCyrillic && !hasLatin {
            analysis.suggestedLanguage = .russian
            analysis.confidence = 0.9
        } else if hasLatin && !hasCyrillic {
            analysis.suggestedLanguage = .english
            analysis.confidence = 0.9
        } else {
            // Смешанные или другие символы
            analysis.confidence = 0.5
        }
        
        analysis.containsCyrillic = hasCyrillic
        analysis.containsLatin = hasLatin
        
        return analysis
    }
    
    private func combineAnalyses(
        basicAnalysis: BasicAnalysis,
        wordAnalysis: EnhancedWordAnalysis,
        context: CombinedContext
    ) -> ContextualAnalysis {
        
        // Если контекст говорит игнорировать
        if context.shouldIgnore {
            return ContextualAnalysis(
                language: nil,
                confidence: 0,
                method: .contextIgnored
            )
        }
        
        var scores: [Language: Double] = [:]
        
        // Базовый анализ
        if let basicLang = basicAnalysis.language {
            scores[basicLang, default: 0] += basicAnalysis.confidence * (1 - contextWeight)
        }
        
        // Анализ слова
        if let wordLang = wordAnalysis.suggestedLanguage {
            scores[wordLang, default: 0] += wordAnalysis.confidence * wordWeight
        }
        
        // Контекст из буфера
        if let contextLang = context.bufferContext.suggestedLanguage {
            scores[contextLang, default: 0] += context.bufferContext.confidence * contextWeight
        }
        
        // Bias от приложения
        if let appBias = context.applicationBias {
            switch appBias {
            case .english:
                scores[.english, default: 0] += 0.3
            case .russian:
                scores[.russian, default: 0] += 0.3
            case .neutral:
                break
            }
        }
        
        // Находим язык с максимальным score
        let bestLanguage = scores.max(by: { $0.value < $1.value })
        
        guard let language = bestLanguage?.key, let score = bestLanguage?.value else {
            return ContextualAnalysis(
                language: nil,
                confidence: 0,
                method: .insufficientData
            )
        }
        
        // Нормализуем confidence
        let confidence = min(max(score, 0.1), 0.95)
        
        // Определяем метод
        let method: DetectionMethod = context.bufferContext.confidence > 0.6 ? .contextual : .combined
        
        return ContextualAnalysis(
            language: language,
            confidence: confidence,
            method: method
        )
    }
    
    private func countBigrams(_ text: String, dictionary: Set<String>) -> Int {
        var count = 0
        let chars = Array(text)
        if chars.count < 2 { return 0 }
        
        for i in 0..<(chars.count - 1) {
            let bigram = String(chars[i...i+1])
            if dictionary.contains(bigram) {
                var score = 1
                
                // Бонус для начала слова
                if i < 2 {
                    score += 2
                }
                
                count += score
            }
        }
        return count
    }
    
    private func cacheResult(_ key: String, language: Language?, confidence: Double) {
        guard let language = language else { return }
        
        cacheManager.cacheLanguageDetection(key: key, language: language, confidence: confidence)
        
        // Обновляем среднюю уверенность
        avgConfidence = (avgConfidence * Double(detectionCount - 1) + confidence) / Double(detectionCount)
    }
}

// MARK: - Вспомогательные структуры

/// Результат детекции языка
struct LanguageDetectionResult {
    let language: Language?
    let confidence: Double
    let method: DetectionMethod
    let contextUsed: Bool
    
    var isConfident: Bool {
        confidence >= 0.7
    }
    
    var description: String {
        if let lang = language {
            return "\(lang) (\(String(format: "%.0f", confidence * 100))%) via \(method)"
        } else {
            return "Unknown (\(String(format: "%.0f", confidence * 100))%)"
        }
    }
}

/// Метод детекции
enum DetectionMethod: String {
    case cached = "Cached"
    case commonWords = "Common Words"
    case programmingKeywords = "Programming Keywords"
    case dictionary = "Dictionary"
    case bigrams = "Bigrams"
    case impossiblePatterns = "Impossible Patterns"
    case specialCharacters = "Special Characters"
    case dictionarySuggestions = "Dictionary Suggestions"
    case ambiguous = "Ambiguous"
    case unknown = "Unknown"
    case contextual = "Contextual"
    case combined = "Combined"
    case contextIgnored = "Context Ignored"
    case insufficientData = "Insufficient Data"
    case insufficientInput = "Insufficient Input"
}

/// Базовый анализ (без контекста)
struct BasicAnalysis {
    let language: Language?
    let confidence: Double
    let method: DetectionMethod
}

/// Контекстный анализ
struct ContextualAnalysis {
    let language: Language?
    let confidence: Double
    let method: DetectionMethod
}

/// Внешний контекст для детекции
struct DetectionContext {
    let applicationType: ApplicationType
    let isSecureField: Bool
    let previousWords: [String]?
    let userPreferences: UserLanguagePreferences?
}

/// Тип приложения
enum ApplicationType: String, Codable {
    case terminal = "terminal"
    case ide = "ide"
    case textEditor = "textEditor"
    case browser = "browser"
    case game = "game"
    case other = "other"
}

/// Предпочтения пользователя по языкам
struct UserLanguagePreferences {
    let primaryLanguage: Language
    let secondaryLanguage: Language?
    let programmingLanguageBias: Bool // Склонность к английскому при программировании
}

/// Объединенный контекст
struct CombinedContext {
    var bufferContext: SentenceContext = SentenceContext()
    var externalContext: DetectionContext?
    var applicationBias: LanguageBias?
    var shouldIgnore: Bool = false
}

/// Смещение языка от приложения
enum LanguageBias {
    case english
    case russian
    case neutral
}

/// Анализ слова
struct EnhancedWordAnalysis {
    var suggestedLanguage: Language?
    var confidence: Double = 0.5
    var containsCyrillic: Bool = false
    var containsLatin: Bool = false
}