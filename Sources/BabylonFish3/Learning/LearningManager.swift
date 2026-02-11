import Foundation
import Cocoa

/// Менеджер обучения на предпочтениях пользователя
class LearningManager {
    
    // Зависимости
    private let cacheManager: CacheManager
    private let performanceMonitor: PerformanceMonitor
    
    // Конфигурация
    private var isEnabled: Bool = true
    private var learningRate: Double = 0.1
    private var decayRate: Double = 0.99
    private var maxHistorySize: Int = 10000
    private var saveInterval: TimeInterval = 300 // 5 минут
    
    // Данные обучения
    private var userPreferences: UserPreferences
    private var learningHistory: [LearningEvent] = []
    private var wordPreferences: [String: WordPreference] = [:] // слово → предпочтения
    private var appPreferences: [String: AppPreference] = [:] // bundleId → предпочтения
    private var contextPatterns: [ContextPattern] = []
    
    // Dataset collection
    private let datasetPath: URL? = {
        if let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let dir = root.appendingPathComponent("BabylonFish/ML/Data")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("user_corrections.csv")
        }
        return nil
    }()
    
    // Время последнего сохранения
    private var lastSaveTime: Date = Date()
    
    /// Инициализирует менеджер обучения
    init(
        cacheManager: CacheManager = .shared,
        performanceMonitor: PerformanceMonitor = .shared
    ) {
        self.cacheManager = cacheManager
        self.performanceMonitor = performanceMonitor
        self.userPreferences = UserPreferences()
        
        loadSavedData()
        setupAutoSave()
        
        logDebug("LearningManager initialized")
    }
    
    // MARK: - Public API
    
    /// Обучает модель на событии пользователя
    func learn(from event: LearningEvent) {
        guard isEnabled else { return }
        
        performanceMonitor.startMeasurement("learning")
        defer { performanceMonitor.endMeasurement("learning") }
        
        // Добавляем событие в историю
        learningHistory.append(event)
        
        // Ограничиваем размер истории
        if learningHistory.count > maxHistorySize {
            learningHistory.removeFirst(learningHistory.count - maxHistorySize)
        }
        
        // Обучаем на событии
        switch event.type {
        case .languageSelection:
            learnLanguageSelection(from: event)
        case .correctionAcceptance:
            learnCorrectionAcceptance(from: event)
            // Save positive example
            if let text = event.originalText, let lang = event.language {
                appendToDataset(text: text, label: lang.rawValue)
            }
        case .correctionRejection:
            learnCorrectionRejection(from: event)
            // Save negative example (user rejected our switch, so the original input was likely correct in the OTHER language)
            if let text = event.originalText, let rejectedLang = event.language {
                // If user rejected RU, it means it was EN (simplified)
                let correctLang = (rejectedLang == .russian) ? "en" : "ru"
                appendToDataset(text: text, label: correctLang)
            }
        case .autoCompleteSelection:
            learnAutoCompleteSelection(from: event)
        case .contextPattern:
            learnContextPattern(from: event)
        case .userFeedback:
            learnUserFeedback(from: event)
        }
        
        // Обновляем общие предпочтения пользователя
        updateUserPreferences(from: event)
        
        // Проверяем, нужно ли сохранить данные
        if Date().timeIntervalSince(lastSaveTime) >= saveInterval {
            saveData()
        }
        
        logDebug("Learned from event: \(event.description)")
    }
    
    /// Получает предпочтения для слова в контексте
    func getWordPreference(
        _ word: String,
        context: LearningContext? = nil
    ) -> WordPreference? {
        
        guard isEnabled else { return nil }
        
        // Базовые предпочтения для слова
        var preference = wordPreferences[word.lowercased()]
        
        // Применяем контекст если есть
        if let context = context, let basePreference = preference {
            preference = applyContext(to: basePreference, context: context)
        }
        
        return preference
    }
    
    /// Получает предпочтения для приложения
    func getAppPreference(_ bundleId: String) -> AppPreference? {
        return appPreferences[bundleId]
    }
    
    /// Получает предсказание языка для контекста
    func predictLanguage(for context: LearningContext) -> LanguagePrediction {
        guard isEnabled else {
            return LanguagePrediction(
                language: nil,
                confidence: 0,
                sources: []
            )
        }
        
        var predictions: [Language: Double] = [:]
        var sources: [PredictionSource] = []
        
        // 1. Предпочтения пользователя
        predictions[userPreferences.preferredLanguage, default: 0] += 0.3
        sources.append(.userPreferences)
        
        // 2. Предпочтения приложения
        if let bundleId = context.applicationBundleId,
           let appPreference = appPreferences[bundleId],
           let appLanguage = appPreference.preferredLanguage {
            predictions[appLanguage, default: 0] += 0.4
            sources.append(.appHistory)
        }
        
        // 3. Контекстные паттерны
        for pattern in contextPatterns where pattern.matches(context: context) {
            predictions[pattern.suggestedLanguage, default: 0] += pattern.confidence * 0.5
            sources.append(.contextPatterns)
        }
        
        // 4. Время суток
        if let timeBasedLanguage = getTimeBasedLanguagePreference() {
            predictions[timeBasedLanguage, default: 0] += 0.1
            sources.append(.timePattern)
        }
        
        // Находим лучший язык
        let bestPrediction = predictions.max(by: { $0.value < $1.value })
        
        guard let language = bestPrediction?.key, let confidence = bestPrediction?.value else {
            return LanguagePrediction(
                language: nil,
                confidence: 0,
                sources: []
            )
        }
        
        let normalizedConfidence = min(max(confidence, 0.1), 0.9)
        
        return LanguagePrediction(
            language: language,
            confidence: normalizedConfidence,
            sources: sources
        )
    }
    
    /// Настраивает менеджер обучения
    func configure(
        isEnabled: Bool? = nil,
        learningRate: Double? = nil,
        decayRate: Double? = nil,
        maxHistorySize: Int? = nil,
        saveInterval: TimeInterval? = nil
    ) {
        if let isEnabled = isEnabled {
            self.isEnabled = isEnabled
        }
        if let learningRate = learningRate {
            self.learningRate = max(0.01, min(1.0, learningRate))
        }
        if let decayRate = decayRate {
            self.decayRate = max(0.9, min(0.999, decayRate))
        }
        if let maxHistorySize = maxHistorySize {
            self.maxHistorySize = max(100, min(100000, maxHistorySize))
        }
        if let saveInterval = saveInterval {
            self.saveInterval = max(60, min(3600, saveInterval))
        }
        
        logDebug("""
        LearningManager configured:
        - enabled: \(self.isEnabled)
        - learning rate: \(self.learningRate)
        - decay rate: \(self.decayRate)
        - max history: \(self.maxHistorySize)
        - save interval: \(self.saveInterval)s
        """)
    }
    
    /// Сохраняет данные обучения
    @discardableResult
    func saveData() -> Bool {
        do {
            let data = try encodeLearningData()
            let success = cacheManager.cacheLearningData(key: "learning_data", data: data)
            
            if success {
                lastSaveTime = Date()
                logDebug("Learning data saved successfully")
            } else {
                logDebug("Failed to save learning data")
            }
            
            return success
        } catch {
            logDebug("Error saving learning data: \(error)")
            return false
        }
    }
    
    /// Загружает сохраненные данные
    @discardableResult
    func loadSavedData() -> Bool {
        guard let data = cacheManager.getCachedLearningData(key: "learning_data") else {
            logDebug("No saved learning data found")
            return false
        }
        
        do {
            try decodeLearningData(data)
            logDebug("Learning data loaded: \(learningHistory.count) events, \(wordPreferences.count) word prefs")
            return true
        } catch {
            logDebug("Error loading learning data: \(error)")
            return false
        }
    }
    
    /// Очищает историю обучения
    func clearLearningHistory() {
        learningHistory.removeAll()
        wordPreferences.removeAll()
        appPreferences.removeAll()
        contextPatterns.removeAll()
        userPreferences = UserPreferences()
        
        logDebug("Learning history cleared")
    }
    
    /// Экспортирует данные обучения
    func exportLearningData() -> [String: Any] {
        return [
            "userPreferences": userPreferences.toDictionary(),
            "learningHistoryCount": learningHistory.count,
            "wordPreferencesCount": wordPreferences.count,
            "appPreferencesCount": appPreferences.count,
            "contextPatternsCount": contextPatterns.count,
            "statistics": getStatistics()
        ]
    }
    
    /// Получает статистику
    func getStatistics() -> [String: Any] {
        let recentEvents = learningHistory.suffix(100)
        let eventTypes = Dictionary(grouping: recentEvents, by: { $0.type })
            .mapValues { $0.count }
        
        return [
            "totalEvents": learningHistory.count,
            "wordPreferences": wordPreferences.count,
            "appPreferences": appPreferences.count,
            "contextPatterns": contextPatterns.count,
            "recentEventTypes": eventTypes,
            "userPreferences": userPreferences.toDictionary(),
            "configuration": [
                "isEnabled": isEnabled,
                "learningRate": learningRate,
                "decayRate": decayRate,
                "maxHistorySize": maxHistorySize,
                "saveInterval": saveInterval
            ]
        ]
    }
    
    // MARK: - Dataset Collection
    
    private func appendToDataset(text: String, label: String) {
        guard let url = datasetPath else { return }
        
        let csvLine = "\"\(text)\",\(label)\n"
        
        if !FileManager.default.fileExists(atPath: url.path) {
            let header = "text,label\n"
            try? header.write(to: url, atomically: true, encoding: .utf8)
        }
        
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = csvLine.data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        }
    }

    // MARK: - Private Methods
    
    private func setupAutoSave() {
        // Автосохранение каждые 5 минут
        Timer.scheduledTimer(withTimeInterval: saveInterval, repeats: true) { [weak self] _ in
            self?.saveData()
        }
    }
    
    private func learnLanguageSelection(from event: LearningEvent) {
        guard let language = event.language,
              let appBundleId = event.applicationBundleId else {
            return
        }
        
        // Обновляем предпочтения пользователя
        userPreferences.updateLanguagePreference(language, weight: learningRate)
        
        // Обновляем предпочтения приложения
        if appPreferences[appBundleId] == nil {
            appPreferences[appBundleId] = AppPreference(bundleId: appBundleId)
        }
        appPreferences[appBundleId]?.updateLanguagePreference(language, weight: learningRate)
        
        // Если есть контекст, создаем/обновляем паттерн
        if let context = event.context {
            updateOrCreateContextPattern(for: context, suggestedLanguage: language)
        }
    }
    
    private func learnCorrectionAcceptance(from event: LearningEvent) {
        guard let original = event.originalText,
              let correction = event.correctedText,
              let language = event.language else {
            return
        }
        
        // Увеличиваем вес исправления
        let wordKey = original.lowercased()
        if wordPreferences[wordKey] == nil {
            wordPreferences[wordKey] = WordPreference(word: original)
        }
        
        wordPreferences[wordKey]?.addCorrection(correction, language: language, weight: learningRate)
        
        // Обновляем предпочтения языка для этого слова
        wordPreferences[wordKey]?.updateLanguagePreference(language, weight: learningRate * 0.5)
    }
    
    private func learnCorrectionRejection(from event: LearningEvent) {
        guard let original = event.originalText,
              let rejectedCorrection = event.correctedText else {
            return
        }
        
        // Уменьшаем вес отвергнутого исправления
        let wordKey = original.lowercased()
        if let preference = wordPreferences[wordKey] {
            preference.removeOrReduceCorrection(rejectedCorrection, decayRate: decayRate)
        }
    }
    
    private func learnAutoCompleteSelection(from event: LearningEvent) {
        guard let prefix = event.originalText,
              let selectedWord = event.correctedText else {
            return
        }
        
        // Увеличиваем вес выбранного автодополнения
        let prefixKey = prefix.lowercased()
        if wordPreferences[prefixKey] == nil {
            wordPreferences[prefixKey] = WordPreference(word: prefix)
        }
        
        wordPreferences[prefixKey]?.addAutoCompleteSelection(selectedWord, weight: learningRate)
    }
    
    private func learnContextPattern(from event: LearningEvent) {
        guard let context = event.context,
              let language = event.language else {
            return
        }
        
        updateOrCreateContextPattern(for: context, suggestedLanguage: language)
    }
    
    private func learnUserFeedback(from event: LearningEvent) {
        guard let feedback = event.feedback else { return }
        
        // Обрабатываем обратную связь пользователя
        switch feedback.type {
        case .positive:
            // Увеличиваем веса связанных событий
            if let relatedEventId = feedback.relatedEventId,
               let relatedEvent = learningHistory.first(where: { $0.id == relatedEventId }) {
                reinforceLearning(from: relatedEvent, multiplier: 1.5)
            }
        case .negative:
            // Уменьшаем веса связанных событий
            if let relatedEventId = feedback.relatedEventId,
               let relatedEvent = learningHistory.first(where: { $0.id == relatedEventId }) {
                reinforceLearning(from: relatedEvent, multiplier: 0.5)
            }
        case .suggestion:
            // Обрабатываем предложение пользователя
            logDebug("User suggestion: \(feedback.message ?? "No message")")
        }
    }
    
    private func reinforceLearning(from event: LearningEvent, multiplier: Double) {
        // Усиливаем или ослабляем обучение на основе обратной связи
        let adjustedLearningRate = learningRate * multiplier
        
        // Повторно применяем обучение с adjusted rate
        switch event.type {
        case .languageSelection:
            if let language = event.language,
               let appBundleId = event.applicationBundleId {
                userPreferences.updateLanguagePreference(language, weight: adjustedLearningRate)
                appPreferences[appBundleId]?.updateLanguagePreference(language, weight: adjustedLearningRate)
            }
        case .correctionAcceptance:
            if let original = event.originalText,
               let correction = event.correctedText,
               let language = event.language {
                let wordKey = original.lowercased()
                wordPreferences[wordKey]?.addCorrection(correction, language: language, weight: adjustedLearningRate)
            }
        default:
            break
        }
    }
    
    private func updateUserPreferences(from event: LearningEvent) {
        // Обновляем общие предпочтения пользователя
        userPreferences.totalEvents += 1
        userPreferences.lastActivity = Date()
        
        // Обновляем частоту типов событий
        userPreferences.eventTypeFrequency[event.type.rawValue, default: 0] += 1
        
        // Применяем decay к старым данным
        applyDecayToOldData()
    }
    
    private func applyDecayToOldData() {
        // Применяем decay к старым предпочтениям
        let decayThreshold = Date().addingTimeInterval(-7 * 24 * 3600) // 1 неделя
        
        // Decay к предпочтениям слов
        for (word, preference) in wordPreferences {
            if preference.lastUpdated < decayThreshold {
                preference.applyDecay(decayRate: decayRate)
                
                // Удаляем если вес слишком низкий
                if preference.totalWeight < 0.01 {
                    wordPreferences.removeValue(forKey: word)
                }
            }
        }
        
        // Decay к паттернам контекста
        contextPatterns = contextPatterns.filter { pattern in
            if pattern.lastMatched < decayThreshold {
                pattern.confidence *= decayRate
                return pattern.confidence > 0.1
            }
            return true
        }
    }
    
    private func updateOrCreateContextPattern(for context: LearningContext, suggestedLanguage: Language) {
        // Ищем существующий паттерн
        if let existingIndex = contextPatterns.firstIndex(where: { $0.matches(context: context) }) {
            // Обновляем существующий паттерн
            let pattern = contextPatterns[existingIndex]
            pattern.update(suggestedLanguage: suggestedLanguage, learningRate: learningRate)
            pattern.lastMatched = Date()
        } else {
            // Создаем новый паттерн
            let newPattern = ContextPattern(
                context: context,
                suggestedLanguage: suggestedLanguage,
                confidence: learningRate
            )
            contextPatterns.append(newPattern)
        }
        
        // Ограничиваем количество паттернов
        if contextPatterns.count > 1000 {
            contextPatterns.sort { $0.confidence > $1.confidence }
            contextPatterns = Array(contextPatterns.prefix(500))
        }
    }
    
    private func applyContext(to preference: WordPreference, context: LearningContext) -> WordPreference {
        // Создаем копию предпочтений с применением контекста
        let contextualPreference = preference.copy()
        
        // Применяем контекстные веса
        if let appBundleId = context.applicationBundleId,
           let appPreference = appPreferences[appBundleId],
           let appLanguage = appPreference.preferredLanguage {
            
            // Увеличиваем вес исправлений на том же языке что и приложение
            for i in 0..<contextualPreference.corrections.count {
                if contextualPreference.corrections[i].language == appLanguage {
                    contextualPreference.corrections[i].weight *= 1.2
                }
            }
        }
        
        // Применяем временные паттерны
        if let timeBasedLanguage = getTimeBasedLanguagePreference() {
            for i in 0..<contextualPreference.corrections.count {
                if contextualPreference.corrections[i].language == timeBasedLanguage {
                    contextualPreference.corrections[i].weight *= 1.1
                }
            }
        }
        
        return contextualPreference
    }
    
    private func getTimeBasedLanguagePreference() -> Language? {
        let hour = Calendar.current.component(.hour, from: Date())
        
        // Простая эвристика: утром и днем английский, вечером русский
        if hour >= 9 && hour <= 17 {
            return .english // Рабочее время
        } else if hour >= 18 && hour <= 22 {
            return .russian // Вечернее время
        }
        
        return nil
    }
    
    private func encodeLearningData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let data = LearningData(
            userPreferences: userPreferences,
            wordPreferences: Array(wordPreferences.values),
            appPreferences: Array(appPreferences.values),
            contextPatterns: contextPatterns,
            recentHistory: Array(learningHistory.suffix(1000))
        )
        
        return try encoder.encode(data)
    }
    
    private func decodeLearningData(_ data: Data) throws {
        let decoder = JSONDecoder()
        let learningData = try decoder.decode(LearningData.self, from: data)
        
        userPreferences = learningData.userPreferences
        
        for preference in learningData.wordPreferences {
            wordPreferences[preference.word.lowercased()] = preference
        }
        
        for preference in learningData.appPreferences {
            appPreferences[preference.bundleId] = preference
        }
        
        contextPatterns = learningData.contextPatterns
        learningHistory = learningData.recentHistory
    }
}

// MARK: - Вспомогательные структуры

/// Событие обучения
class LearningEvent: Codable {
    let id: String
    let type: LearningEventType
    let timestamp: Date
    let language: Language?
    let originalText: String?
    let correctedText: String?
    let applicationBundleId: String?
    let applicationType: ApplicationType?
    let context: LearningContext?
    let feedback: UserFeedback?
    
    init(
        type: LearningEventType,
        language: Language? = nil,
        originalText: String? = nil,
        correctedText: String? = nil,
        applicationBundleId: String? = nil,
        applicationType: ApplicationType? = nil,
        context: LearningContext? = nil,
        feedback: UserFeedback? = nil
    ) {
        self.id = UUID().uuidString
        self.type = type
        self.timestamp = Date()
        self.language = language
        self.originalText = originalText
        self.correctedText = correctedText
        self.applicationBundleId = applicationBundleId
        self.applicationType = applicationType
        self.context = context
        self.feedback = feedback
    }
    
    var description: String {
        var desc = "\(type) at \(timestamp)"
        if let language = language {
            desc += " → \(language)"
        }
        if let original = originalText, let corrected = correctedText {
            desc += " (\(original) → \(corrected))"
        }
        return desc
    }
}

/// Тип события обучения
enum LearningEventType: String, Codable {
    case languageSelection = "Language Selection"
    case correctionAcceptance = "Correction Acceptance"
    case correctionRejection = "Correction Rejection"
    case autoCompleteSelection = "Auto-Complete Selection"
    case contextPattern = "Context Pattern"
    case userFeedback = "User Feedback"
}

/// Контекст обучения
struct LearningContext: Codable {
    let applicationBundleId: String?
    let applicationType: ApplicationType?
    let textContext: String? // Окружающий текст
    let cursorPosition: Int?
    let selectedText: String?
    let isSecureField: Bool
    let timestamp: Date
    
    init(
        applicationBundleId: String? = nil,
        applicationType: ApplicationType? = nil,
        textContext: String? = nil,
        cursorPosition: Int? = nil,
        selectedText: String? = nil,
        isSecureField: Bool = false
    ) {
        self.applicationBundleId = applicationBundleId
        self.applicationType = applicationType
        self.textContext = textContext
        self.cursorPosition = cursorPosition
        self.selectedText = selectedText
        self.isSecureField = isSecureField
        self.timestamp = Date()
    }
}

/// Предпочтения пользователя
class UserPreferences: Codable {
    var preferredLanguage: Language = .english
    var secondaryLanguage: Language? = .russian
    var totalEvents: Int = 0
    var lastActivity: Date = Date()
    var eventTypeFrequency: [String: Int] = [:]
    var languageWeights: [Language: Double] = [:]
    
    init() {
        languageWeights[.english] = 1.0
        languageWeights[.russian] = 0.5
    }
    
    func updateLanguagePreference(_ language: Language, weight: Double) {
        languageWeights[language, default: 0] += weight
        
        // Нормализуем веса
        let totalWeight = languageWeights.values.reduce(0, +)
        if totalWeight > 0 {
            for (lang, _) in languageWeights {
                languageWeights[lang] = languageWeights[lang]! / totalWeight
            }
        }
        
        // Обновляем предпочтительный язык
        preferredLanguage = languageWeights.max(by: { $0.value < $1.value })?.key ?? .english
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "preferredLanguage": preferredLanguage.rawValue,
            "secondaryLanguage": secondaryLanguage?.rawValue ?? "nil",
            "totalEvents": totalEvents,
            "lastActivity": ISO8601DateFormatter().string(from: lastActivity),
            "languageWeights": languageWeights.mapValues { String(format: "%.3f", $0) }
        ]
    }
}

/// Предпочтения для слова
class WordPreference: Codable {
    let word: String
    var corrections: [CorrectionPreference] = []
    var autoCompletions: [AutoCompletePreference] = []
    var languageWeights: [Language: Double] = [:]
    var totalWeight: Double = 0
    var lastUpdated: Date = Date()
    
    init(word: String) {
        self.word = word
    }
    
    func addCorrection(_ correction: String, language: Language, weight: Double) {
        if let index = corrections.firstIndex(where: { $0.correction == correction }) {
            corrections[index].weight += weight
            corrections[index].lastUsed = Date()
        } else {
            corrections.append(CorrectionPreference(
                correction: correction,
                language: language,
                weight: weight
            ))
        }
        
        updateLanguagePreference(language, weight: weight * 0.5)
        totalWeight += weight
        lastUpdated = Date()
    }
    
    func removeOrReduceCorrection(_ correction: String, decayRate: Double) {
        if let index = corrections.firstIndex(where: { $0.correction == correction }) {
            corrections[index].weight *= decayRate
            
            if corrections[index].weight < 0.01 {
                corrections.remove(at: index)
            }
        }
        
        totalWeight *= decayRate
        lastUpdated = Date()
    }
    
    func addAutoCompleteSelection(_ word: String, weight: Double) {
        if let index = autoCompletions.firstIndex(where: { $0.word == word }) {
            autoCompletions[index].weight += weight
            autoCompletions[index].lastUsed = Date()
        } else {
            autoCompletions.append(AutoCompletePreference(
                word: word,
                weight: weight
            ))
        }
        
        totalWeight += weight
        lastUpdated = Date()
    }
    
    func updateLanguagePreference(_ language: Language, weight: Double) {
        languageWeights[language, default: 0] += weight
        lastUpdated = Date()
    }
    
    func applyDecay(decayRate: Double) {
        for i in 0..<corrections.count {
            corrections[i].weight *= decayRate
        }
        
        for i in 0..<autoCompletions.count {
            autoCompletions[i].weight *= decayRate
        }
        
        for (language, weight) in languageWeights {
            languageWeights[language] = weight * decayRate
        }
        
        totalWeight *= decayRate
    }
    
    func copy() -> WordPreference {
        let copy = WordPreference(word: word)
        copy.corrections = corrections.map { $0.copy() }
        copy.autoCompletions = autoCompletions.map { $0.copy() }
        copy.languageWeights = languageWeights
        copy.totalWeight = totalWeight
        copy.lastUpdated = lastUpdated
        return copy
    }
}

/// Предпочтения для приложения
class AppPreference: Codable {
    let bundleId: String
    var preferredLanguage: Language?
    var languageWeights: [Language: Double] = [:]
    var totalInteractions: Int = 0
    var lastUsed: Date = Date()
    
    init(bundleId: String) {
        self.bundleId = bundleId
    }
    
    func updateLanguagePreference(_ language: Language, weight: Double) {
        languageWeights[language, default: 0] += weight
        totalInteractions += 1
        lastUsed = Date()
        
        // Обновляем предпочтительный язык
        preferredLanguage = languageWeights.max(by: { $0.value < $1.value })?.key
    }
}

/// Паттерн контекста
class ContextPattern: Codable {
    let context: LearningContext
    var suggestedLanguage: Language
    var confidence: Double
    var matchCount: Int = 1
    var lastMatched: Date = Date()
    
    init(context: LearningContext, suggestedLanguage: Language, confidence: Double) {
        self.context = context
        self.suggestedLanguage = suggestedLanguage
        self.confidence = confidence
    }
    
    func matches(context: LearningContext) -> Bool {
        // Простая проверка совпадения контекста
        // В реальной реализации будет более сложная логика
        
        if self.context.applicationBundleId != context.applicationBundleId {
            return false
        }
        
        if self.context.applicationType != context.applicationType {
            return false
        }
        
        // Можно добавить больше проверок
        
        return true
    }
    
    func update(suggestedLanguage: Language, learningRate: Double) {
        if self.suggestedLanguage == suggestedLanguage {
            confidence = min(1.0, confidence + learningRate)
        } else {
            confidence = max(0.1, confidence - learningRate * 0.5)
            
            // Если уверенность упала ниже порога, меняем язык
            if confidence < 0.3 {
                self.suggestedLanguage = suggestedLanguage
                confidence = learningRate
            }
        }
        
        matchCount += 1
        lastMatched = Date()
    }
}

/// Предпочтение для исправления
class CorrectionPreference: Codable {
    let correction: String
    let language: Language
    var weight: Double
    var lastUsed: Date
    
    init(correction: String, language: Language, weight: Double) {
        self.correction = correction
        self.language = language
        self.weight = weight
        self.lastUsed = Date()
    }
    
    func copy() -> CorrectionPreference {
        return CorrectionPreference(
            correction: correction,
            language: language,
            weight: weight
        )
    }
}

/// Предпочтение для автодополнения
class AutoCompletePreference: Codable {
    let word: String
    var weight: Double
    var lastUsed: Date
    
    init(word: String, weight: Double) {
        self.word = word
        self.weight = weight
        self.lastUsed = Date()
    }
    
    func copy() -> AutoCompletePreference {
        return AutoCompletePreference(
            word: word,
            weight: weight
        )
    }
}

/// Предсказание языка
struct LanguagePrediction {
    let language: Language?
    let confidence: Double
    let sources: [PredictionSource]
    
    var description: String {
        if let language = language {
            return "\(language) (\(String(format: "%.0f", confidence * 100))%) via \(sources.map { $0.rawValue }.joined(separator: ", "))"
        } else {
            return "Unknown"
        }
    }
}

/// Источник предсказания
enum PredictionSource: String, Codable {
    case userPreferences = "User Preferences"
    case appHistory = "App History"
    case contextPatterns = "Context Patterns"
    case timePattern = "Time Pattern"
    case wordHistory = "Word History"
}

/// Обратная связь пользователя
struct UserFeedback: Codable {
    let type: FeedbackType
    let message: String?
    let rating: Int? // 1-5
    let relatedEventId: String?
    let timestamp: Date
    
    init(
        type: FeedbackType,
        message: String? = nil,
        rating: Int? = nil,
        relatedEventId: String? = nil
    ) {
        self.type = type
        self.message = message
        self.rating = rating
        self.relatedEventId = relatedEventId
        self.timestamp = Date()
    }
}

/// Тип обратной связи
enum FeedbackType: String, Codable {
    case positive = "Positive"
    case negative = "Negative"
    case suggestion = "Suggestion"
}

/// Данные обучения для сохранения
struct LearningData: Codable {
    let userPreferences: UserPreferences
    let wordPreferences: [WordPreference]
    let appPreferences: [AppPreference]
    let contextPatterns: [ContextPattern]
    let recentHistory: [LearningEvent]
    
    init(
        userPreferences: UserPreferences,
        wordPreferences: [WordPreference],
        appPreferences: [AppPreference],
        contextPatterns: [ContextPattern],
        recentHistory: [LearningEvent]
    ) {
        self.userPreferences = userPreferences
        self.wordPreferences = wordPreferences
        self.appPreferences = appPreferences
        self.contextPatterns = contextPatterns
        self.recentHistory = recentHistory
    }
}
