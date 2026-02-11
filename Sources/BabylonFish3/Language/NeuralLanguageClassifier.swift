import Foundation
import CoreML
import NaturalLanguage

/// Нейросетевой классификатор языка на основе CoreML
class NeuralLanguageClassifier {
    
    // Модель CoreML для классификации языка
    private var mlModel: MLModel?
    private var customModel: NLModel?
    private var nlpModel: NLLanguageRecognizer?
    
    // Конфигурация
    private var isEnabled: Bool = true
    private var confidenceThreshold: Double = 0.5 // Lowered from 0.7 for better responsiveness
    private var maxInputLength: Int = 100
    
    // Кэш для результатов
    private var predictionCache: [String: (Language, Double)] = [:]
    private let cacheQueue = DispatchQueue(label: "com.babylonfish.neuralcache")
    
    // Статистика
    private var totalPredictions: Int = 0
    private var cacheHits: Int = 0
    private var successfulPredictions: Int = 0
    
    /// Инициализирует нейросетевой классификатор
    init() {
        setupModels()
        logDebug("NeuralLanguageClassifier initialized")
    }
    
    /// Настраивает модели
    private func setupModels() {
        // 1. Пытаемся загрузить кастомную CoreML модель
        setupCustomModel()
        
        // 2. Настраиваем встроенный распознаватель языка от Apple
        setupAppleLanguageRecognizer()
        
        // 3. Настраиваем кэш
        setupCache()
    }
    
    /// Настраивает кастомную CoreML модель
    private func setupCustomModel() {
        do {
            // Try to find the compiled model in the bundle
            // SwiftPM compiles .mlmodel to .mlmodelc directory structure
            if let modelUrl = Bundle.module.url(forResource: "BabylonFishClassifier", withExtension: "mlmodelc") {
                // Initialize NLModel (since we trained a Text Classifier)
                let model = try NLModel(contentsOf: modelUrl)
                self.customModel = model
                logDebug("Custom CoreML model loaded successfully from \(modelUrl.path)")
            } else {
                logDebug("Could not find BabylonFishClassifier.mlmodelc in bundle")
            }
        } catch {
            logDebug("Failed to load custom model: \(error)")
        }
    }
    
    /// Настраивает встроенный распознаватель языка от Apple
    private func setupAppleLanguageRecognizer() {
        nlpModel = NLLanguageRecognizer()
        
        // Настраиваем языки, которые мы хотим распознавать
        let supportedLanguages: Set<NLLanguage> = [
            .english,
            .russian,
            .french,
            .german,
            .spanish,
            .italian,
            .portuguese,
            .dutch,
            .swedish,
            .danish,
            .norwegian,
            .finnish
        ]
        
        nlpModel?.languageConstraints = Array(supportedLanguages)
        logDebug("Apple NLLanguageRecognizer initialized with \(supportedLanguages.count) languages")
    }
    
    /// Настраивает кэш
    private func setupCache() {
        // Очищаем кэш каждые 10 минут
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.clearCache()
        }
    }
    
    // MARK: - Public API
    
    /// Классифицирует язык текста
    func classifyLanguage(_ text: String, context: ClassificationContext? = nil) -> NeuralClassificationResult {
        totalPredictions += 1
        
        logDebug("NeuralLanguageClassifier.classifyLanguage called with text: '\(text)'")
        
        guard isEnabled else {
            logDebug("NeuralLanguageClassifier is disabled")
            return NeuralClassificationResult(
                language: nil,
                confidence: 0,
                method: .disabled,
                features: nil
            )
        }
        
        // Проверяем кэш
        if let cached = getCachedPrediction(for: text) {
            cacheHits += 1
            logDebug("Cache hit for text: '\(text)' → \(cached.0) (\(cached.1))")
            return NeuralClassificationResult(
                language: cached.0,
                confidence: cached.1,
                method: .cached,
                features: nil
            )
        }
        
        // Подготавливаем текст
        let preparedText = prepareText(text)
        logDebug("Prepared text: '\(preparedText)'")
        
        guard !preparedText.isEmpty else {
            logDebug("Prepared text is empty")
            return NeuralClassificationResult(
                language: nil,
                confidence: 0,
                method: .insufficientInput,
                features: nil
            )
        }
        
        // Извлекаем фичи
        let features = extractFeatures(from: preparedText)
        
        // Классифицируем с помощью Apple NLLanguageRecognizer
        let appleResult = classifyWithAppleRecognizer(preparedText)
        logDebug("Apple NLP result: language=\(String(describing: appleResult.language)), confidence=\(appleResult.confidence), threshold=\(confidenceThreshold)")
        
        // Если уверенность высокая, используем результат Apple
        if appleResult.confidence >= confidenceThreshold {
            if let language = convertNLLanguageToOurLanguage(appleResult.language) {
                cachePrediction(text, language: language, confidence: appleResult.confidence)
                successfulPredictions += 1
                
                logDebug("Using Apple NLP result: \(language) with confidence \(appleResult.confidence)")
                return NeuralClassificationResult(
                    language: language,
                    confidence: appleResult.confidence,
                    method: .appleNLP,
                    features: features
                )
            }
        }
        
        // Пытаемся использовать кастомную модель (если есть)
        if let customResult = classifyWithCustomModel(preparedText, features: features) {
            cachePrediction(text, language: customResult.language, confidence: customResult.confidence)
            successfulPredictions += 1
            
            return NeuralClassificationResult(
                language: customResult.language,
                confidence: customResult.confidence,
                method: .customModel,
                features: features
            )
        }
        
        // Используем эвристики как fallback
        let heuristicResult = classifyWithHeuristics(preparedText, features: features, context: context)
        
        if let language = heuristicResult.language, heuristicResult.confidence > 0.3 {
            cachePrediction(text, language: language, confidence: heuristicResult.confidence)
        }
        
        return NeuralClassificationResult(
            language: heuristicResult.language,
            confidence: heuristicResult.confidence,
            method: .heuristics,
            features: features
        )
    }
    
    /// Настраивает классификатор
    func configure(isEnabled: Bool? = nil, confidenceThreshold: Double? = nil) {
        if let isEnabled = isEnabled {
            self.isEnabled = isEnabled
        }
        if let confidenceThreshold = confidenceThreshold {
            self.confidenceThreshold = max(0.1, min(0.99, confidenceThreshold))
        }
        
        logDebug("NeuralLanguageClassifier configured: enabled=\(self.isEnabled), confidenceThreshold=\(self.confidenceThreshold)")
    }
    
    /// Очищает кэш
    func clearCache() {
        cacheQueue.sync {
            predictionCache.removeAll()
        }
        logDebug("Neural language prediction cache cleared")
    }
    
    /// Получает статистику
    func getStatistics() -> [String: Any] {
        let cacheHitRate = totalPredictions > 0 ? Double(cacheHits) / Double(totalPredictions) : 0
        let successRate = totalPredictions > 0 ? Double(successfulPredictions) / Double(totalPredictions) : 0
        
        return [
            "totalPredictions": totalPredictions,
            "cacheHits": cacheHits,
            "cacheHitRate": cacheHitRate,
            "successfulPredictions": successfulPredictions,
            "successRate": successRate,
            "cacheSize": predictionCache.count,
            "configuration": [
                "isEnabled": isEnabled,
                "confidenceThreshold": confidenceThreshold,
                "maxInputLength": maxInputLength
            ]
        ]
    }
    
    /// Обучает модель на новых данных (заглушка для реальной реализации)
    func train(with examples: [(text: String, language: Language)]) -> Bool {
        logDebug("Training requested with \(examples.count) examples")
        
        // В реальной реализации здесь будет обучение модели
        // Пока просто логируем
        
        for (text, language) in examples.prefix(5) {
            logDebug("  Example: '\(text.prefix(20))...' → \(language)")
        }
        
        if examples.count > 5 {
            logDebug("  ... and \(examples.count - 5) more examples")
        }
        
        return true
    }
    
    // MARK: - Private Methods
    
    private func prepareText(_ text: String) -> String {
        // Обрезаем до максимальной длины
        let trimmed = String(text.prefix(maxInputLength))
        
        // Приводим к нижнему регистру
        let lowercased = trimmed.lowercased()
        
        // Удаляем лишние пробелы
        let normalized = lowercased.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return normalized
    }
    
    private func extractFeatures(from text: String) -> TextFeatures {
        var features = TextFeatures()
        
        // Базовые фичи
        features.length = text.count
        features.wordCount = text.split(separator: " ").count
        
        // Распределение символов
        let characters = Array(text)
        features.characterDistribution = calculateCharacterDistribution(characters)
        
        // N-граммы
        features.bigrams = extractNGrams(text, n: 2)
        features.trigrams = extractNGrams(text, n: 3)
        
        // Специальные символы
        features.hasNumbers = text.contains { $0.isNumber }
        features.hasPunctuation = text.contains { $0.isPunctuation }
        features.hasSpecialChars = text.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
        
        // Языковые фичи
        features.cyrillicRatio = calculateCyrillicRatio(text)
        features.latinRatio = calculateLatinRatio(text)
        
        // Сложность текста
        features.uniqueCharacterRatio = calculateUniqueCharacterRatio(text)
        
        return features
    }
    
    private func calculateCharacterDistribution(_ characters: [Character]) -> [Character: Int] {
        var distribution: [Character: Int] = [:]
        
        for char in characters {
            distribution[char, default: 0] += 1
        }
        
        return distribution
    }
    
    private func extractNGrams(_ text: String, n: Int) -> [String: Int] {
        var ngrams: [String: Int] = [:]
        let characters = Array(text)
        
        guard characters.count >= n else { return ngrams }
        
        for i in 0...(characters.count - n) {
            let ngram = String(characters[i..<(i + n)])
            ngrams[ngram, default: 0] += 1
        }
        
        return ngrams
    }
    
    private func calculateCyrillicRatio(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        
        let cyrillicCount = text.filter { char in
            let scalar = String(char).unicodeScalars.first?.value ?? 0
            return (0x0400...0x04FF).contains(scalar)
        }.count
        
        return Double(cyrillicCount) / Double(text.count)
    }
    
    private func calculateLatinRatio(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        
        let latinCount = text.filter { char in
            let scalar = String(char).unicodeScalars.first?.value ?? 0
            return (0x0041...0x007A).contains(scalar) || (0x0061...0x007A).contains(scalar)
        }.count
        
        return Double(latinCount) / Double(text.count)
    }
    
    private func calculateUniqueCharacterRatio(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        
        let uniqueChars = Set(text)
        return Double(uniqueChars.count) / Double(text.count)
    }
    
    private func classifyWithAppleRecognizer(_ text: String) -> (language: NLLanguage?, confidence: Double) {
        // Создаем новый распознаватель для каждого вызова
        let recognizer = NLLanguageRecognizer()
        
        // Настраиваем языки
        let supportedLanguages: Set<NLLanguage> = [
            .english,
            .russian,
            .french,
            .german,
            .spanish,
            .italian,
            .portuguese,
            .dutch,
            .swedish,
            .danish,
            .norwegian,
            .finnish
        ]
        
        recognizer.languageConstraints = Array(supportedLanguages)
        
        recognizer.processString(text)
        
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let bestLanguage = recognizer.dominantLanguage
        
        // Debug logging
        logDebug("Apple NLP: text='\(text)', bestLanguage=\(String(describing: bestLanguage)), hypotheses=\(hypotheses)")
        
        guard let language = bestLanguage else {
            return (nil, 0)
        }
        
        let confidence = hypotheses[language] ?? 0
        return (language, confidence)
    }
    
    private func convertNLLanguageToOurLanguage(_ nlLanguage: NLLanguage?) -> Language? {
        guard let nlLanguage = nlLanguage else { return nil }
        
        switch nlLanguage {
        case .english:
            return .english
        case .russian:
            return .russian
        case .french, .german, .spanish, .italian, .portuguese,
             .dutch, .swedish, .danish, .norwegian, .finnish:
            return .english // Другие европейские языки считаем английскими для наших целей
        default:
            return nil
        }
    }
    
    private func classifyWithCustomModel(_ text: String, features: TextFeatures) -> (language: Language, confidence: Double)? {
        if let model = customModel {
            // Use NLModel
            guard let label = model.predictedLabel(for: text) else {
                return nil
            }
            
            // Get confidence
            let hypothesis = model.predictedLabelHypotheses(for: text, maximumCount: 1)
            let confidence = hypothesis[label] ?? 0.0
            
            // Map label string to Language enum
            let language: Language
            if label == "ru" || label == "ru_wrong" {
                 language = .russian
            } else if label == "en" {
                 language = .english
            } else {
                 return nil
            }
            
            logDebug("Custom CoreML Prediction: \(label) (\(confidence))")
            return (language, confidence)
        }
        
        // В реальной реализации здесь будет вызов CoreML модели
        // Пока используем эвристики на основе фич
        
        // Если текст содержит кириллицу
        if features.cyrillicRatio > 0.5 {
            let confidence = min(0.9, features.cyrillicRatio * 1.5)
            return (.russian, confidence)
        }
        
        // Если текст содержит латиницу
        if features.latinRatio > 0.5 {
            let confidence = min(0.9, features.latinRatio * 1.5)
            return (.english, confidence)
        }
        
        return nil
    }
    
    private func classifyWithHeuristics(_ text: String, features: TextFeatures, context: ClassificationContext?) -> (language: Language?, confidence: Double) {
        var scores: [Language: Double] = [:]
        
        // 1. Фичи текста
        if features.cyrillicRatio > 0.7 {
            scores[.russian, default: 0] += 0.8
        } else if features.latinRatio > 0.7 {
            scores[.english, default: 0] += 0.8
        } else if features.cyrillicRatio > 0.3 {
            scores[.russian, default: 0] += 0.4
        } else if features.latinRatio > 0.3 {
            scores[.english, default: 0] += 0.4
        }
        
        // 2. Контекст (если есть)
        if let context = context {
            if context.applicationType == .ide || context.applicationType == .terminal {
                scores[.english, default: 0] += 0.3
            }
            
            if let previousLanguage = context.previousLanguage {
                scores[previousLanguage, default: 0] += 0.2
            }
        }
        
        // 3. Длина текста (короткие тексты менее надежны)
        if features.length < 3 {
            // Уменьшаем уверенность для коротких текстов
            for (language, _) in scores {
                scores[language] = scores[language]! * 0.5
            }
        }
        
        // Находим лучший язык
        let bestLanguage = scores.max(by: { $0.value < $1.value })
        
        guard let language = bestLanguage?.key, let score = bestLanguage?.value else {
            return (nil, 0)
        }
        
        let confidence = min(max(score, 0.1), 0.9)
        return (language, confidence)
    }
    
    private func getCachedPrediction(for text: String) -> (Language, Double)? {
        return cacheQueue.sync {
            return predictionCache[text]
        }
    }
    
    private func cachePrediction(_ text: String, language: Language, confidence: Double) {
        cacheQueue.sync {
            predictionCache[text] = (language, confidence)
            
            // Ограничиваем размер кэша
            if predictionCache.count > 1000 {
                // Удаляем старые записи
                let keysToRemove = Array(predictionCache.keys.prefix(200))
                for key in keysToRemove {
                    predictionCache.removeValue(forKey: key)
                }
            }
        }
    }
}

// MARK: - Вспомогательные структуры

/// Результат нейросетевой классификации
struct NeuralClassificationResult {
    let language: Language?
    let confidence: Double
    let method: ClassificationMethod
    let features: TextFeatures?
    
    var isConfident: Bool {
        confidence >= 0.7
    }
    
    var description: String {
        if let language = language {
            return "\(language) (\(String(format: "%.0f", confidence * 100))%) via \(method)"
        } else {
            return "Unknown (\(String(format: "%.0f", confidence * 100))%)"
        }
    }
}

/// Метод классификации
enum ClassificationMethod: String {
    case appleNLP = "Apple NLP"
    case customModel = "Custom Model"
    case heuristics = "Heuristics"
    case cached = "Cached"
    case disabled = "Disabled"
    case insufficientInput = "Insufficient Input"
}

/// Контекст для классификации
struct ClassificationContext {
    let applicationType: ApplicationType
    let previousLanguage: Language?
    let userPreferences: UserLanguagePreferences?
    let timestamp: Date
    
    init(
        applicationType: ApplicationType = .other,
        previousLanguage: Language? = nil,
        userPreferences: UserLanguagePreferences? = nil
    ) {
        self.applicationType = applicationType
        self.previousLanguage = previousLanguage
        self.userPreferences = userPreferences
        self.timestamp = Date()
    }
}

/// Фичи текста для классификации
struct TextFeatures {
    var length: Int = 0
    var wordCount: Int = 0
    var characterDistribution: [Character: Int] = [:]
    var bigrams: [String: Int] = [:]
    var trigrams: [String: Int] = [:]
    var hasNumbers: Bool = false
    var hasPunctuation: Bool = false
    var hasSpecialChars: Bool = false
    var cyrillicRatio: Double = 0
    var latinRatio: Double = 0
    var uniqueCharacterRatio: Double = 0
    
    var description: String {
        return """
        Length: \(length)
        Words: \(wordCount)
        Cyrillic: \(String(format: "%.1f", cyrillicRatio * 100))%
        Latin: \(String(format: "%.1f", latinRatio * 100))%
        Unique chars: \(String(format: "%.1f", uniqueCharacterRatio * 100))%
        """
    }
}