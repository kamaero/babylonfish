import Foundation
import Cocoa

/// Главный движок BabylonFish 3.0
class BabylonFishEngine {
    // Компоненты
    private var config: AppConfig
    private let asyncProcessor: AsyncProcessor
    private let cacheManager: CacheManager
    private let performanceMonitor: PerformanceMonitor
    private let systemDictionaryService: SystemDictionaryService
    
    // Основные компоненты
    private var contextAnalyzer: ContextAnalyzer?
    private var neuralLanguageClassifier: NeuralLanguageClassifier?
    private var typoCorrector: TypoCorrector?
    private var autoCompleteEngine: AutoCompleteEngine?
    private var learningManager: LearningManager?
    private var bufferManager: BufferManager?
    private var layoutSwitcher: LayoutSwitcher?
    private var eventProcessor: EventProcessor?
    private var eventTapManager: EventTapManager?
    
    // UI компоненты
    weak var suggestionWindow: SuggestionWindow?
    
    // Состояние
    private var isRunning = false
    private var startTime: Date?
    
    /// Текущая конфигурация (только для чтения)
    var currentConfig: AppConfig {
        return config
    }
    
    /// Инициализирует движок с конфигурацией
    init(config: AppConfig = AppConfig.load()) {
        self.config = config
        
        // Инициализируем основные утилиты
        asyncProcessor = AsyncProcessor.shared
        cacheManager = CacheManager.shared
        performanceMonitor = PerformanceMonitor.shared
        systemDictionaryService = SystemDictionaryService.shared
        
        // Настраиваем компоненты на основе конфигурации
        configureComponents()
        
        // Настраиваем мониторинг производительности
        setupPerformanceMonitoring()
        
        logDebug("BabylonFishEngine 3.0 initialized with config version \(config.version)")
    }
    
    /// Устанавливает окно подсказок
    func setSuggestionWindow(_ window: SuggestionWindow?) {
        suggestionWindow = window
        logDebug("Suggestion window set: \(window != nil ? "yes" : "no")")
    }
    
    /// Запускает движок
    func start() -> Bool {
        guard !isRunning else {
            logDebug("Engine is already running")
            return false
        }
        
        logDebug("BabylonFishEngine: Starting version 3.0...")
        
        do {
            // Применяем конфигурацию
            try applyConfiguration()
            
            // Включаем мониторинг производительности
            performanceMonitor.setEnabled(config.performance.enablePerformanceMonitoring)
            
            // Инициализируем основные компоненты
            try initializeCoreComponents()
            
            // Запускаем event tap (если настроен)
            if let eventTapManager = eventTapManager {
                let success = eventTapManager.start()
                if success {
                    isRunning = true
                    startTime = Date()
                    logInfo("BabylonFishEngine: Started successfully with event tap")
                } else {
                    logWarning("BabylonFishEngine: Failed to start event tap, running in configuration mode")
                    isRunning = true
                    startTime = Date()
                }
                return success
            }
            
            logInfo("BabylonFishEngine: Started in configuration mode (no event tap)")
            isRunning = true
            startTime = Date()
            return true
        } catch {
            logError(error, context: "Failed to start BabylonFishEngine")
            return false
        }
    }
    
    /// Останавливает движок
    func stop() {
        guard isRunning else { return }
        
        logDebug("BabylonFishEngine: Stopping...")
        
        // Останавливаем event tap
        eventTapManager?.stop()
        
        // Отключаем мониторинг производительности
        performanceMonitor.setEnabled(false)
        
        // Очищаем кэш если нужно
        if !config.cache.enabled {
            cacheManager.clearAll()
        }
        
        isRunning = false
        logDebug("BabylonFishEngine: Stopped")
    }
    
    /// Обновляет конфигурацию
    func updateConfiguration(_ newConfig: AppConfig) {
        logDebug("Updating configuration...")
        
        let oldConfig = config
        config = newConfig
        
        // Применяем изменения конфигурации
        applyConfigurationChanges(from: oldConfig, to: newConfig)
        
        // Сохраняем новую конфигурацию
        config.save()
        
        logDebug("Configuration updated successfully")
    }
    
    /// Получает текущую конфигурацию
    func getConfiguration() -> AppConfig {
        return config
    }
    
    /// Получает статистику производительности
    func getPerformanceMetrics() -> [String: Any] {
        var metrics: [String: Any] = [:]
        
        // Метрики движка
        metrics["isRunning"] = isRunning
        metrics["uptime"] = startTime.map { Date().timeIntervalSince($0) } ?? 0
        metrics["configVersion"] = config.version
        
        // Метрики производительности
        let perfMetrics = performanceMonitor.getMetrics()
        metrics["performance"] = perfMetrics.toDictionary()
        
        // Статистика кэша
        metrics["cache"] = cacheManager.getStatistics()
        
        // Статистика асинхронного процессора
        metrics["asyncProcessor"] = asyncProcessor.getStatistics()
        
        // Статистика системного словаря
        metrics["systemDictionary"] = systemDictionaryService.getStatistics()
        
        return metrics
    }
    
    /// Экспортирует статистику в файл
    func exportStatistics(to filePath: String) -> Bool {
        let metrics = getPerformanceMetrics()
        
        // Convert metrics to a serializable dictionary
        var serializableMetrics: [String: Any] = [:]
        
        for (key, value) in metrics {
            // Convert Date to string
            if let date = value as? Date {
                serializableMetrics[key] = ISO8601DateFormatter().string(from: date)
            }
            // Convert other non-serializable types
            else if let dictValue = value as? [String: Any] {
                var serializableDict: [String: Any] = [:]
                for (dictKey, dictVal) in dictValue {
                    if let dateVal = dictVal as? Date {
                        serializableDict[dictKey] = ISO8601DateFormatter().string(from: dateVal)
                    } else {
                        serializableDict[dictKey] = dictVal
                    }
                }
                serializableMetrics[key] = serializableDict
            }
            else {
                serializableMetrics[key] = value
            }
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: serializableMetrics, options: .prettyPrinted)
            try data.write(to: URL(fileURLWithPath: filePath))
            logDebug("Statistics exported to \(filePath)")
            return true
        } catch {
            logDebug("Failed to export statistics: \(error)")
            return false
        }
    }
    
    /// Очищает кэш
    func clearCache() {
        cacheManager.clearAll()
        systemDictionaryService.clearCache()
        logDebug("Cache cleared")
    }
    
    /// Сбрасывает статистику
    func resetStatistics() {
        performanceMonitor.resetMetrics()
        asyncProcessor.clearStatistics()
        logDebug("Statistics reset")
    }
    
    /// Тестирует системный словарь
    func testSystemDictionary(word: String, languageCode: String = "en") -> [String: Any] {
        let isValid = systemDictionaryService.checkSpelling(word, languageCode: languageCode)
        let suggestions = systemDictionaryService.getSuggestions(word, languageCode: languageCode)
        let completions = systemDictionaryService.getCompletions(word, languageCode: languageCode)
        
        return [
            "word": word,
            "language": languageCode,
            "isValid": isValid,
            "suggestions": suggestions,
            "completions": completions,
            "bestCorrection": systemDictionaryService.getBestCorrection(word, languageCode: languageCode) as Any
        ]
    }
    
    /// Тестирует контекстный анализ
    func testContextualAnalysis(text: String, appType: ApplicationType = .textEditor, isSecure: Bool = false) -> [String: Any] {
        guard let analyzer = contextAnalyzer else {
            return ["error": "ContextAnalyzer not initialized"]
        }
        
        let context = DetectionContext(
            applicationType: appType,
            isSecureField: isSecure,
            previousWords: nil,
            userPreferences: nil
        )
        
        let result = analyzer.analyzeContext(for: text, externalContext: context)
        
        return [
            "text": text,
            "analysis": result.description,
            "suggestedLanguage": String(describing: result.suggestedLanguage),
            "confidence": result.confidence,
            "topic": result.topic.description,
            "tone": result.tone.description,
            "languageTrend": result.languageTrend.rawValue,
            "shouldIgnore": result.shouldIgnore,
            "method": result.method.rawValue,
            "isConfident": result.isConfident
        ]
    }
    
    /// Обновляет контекст вручную
    func updateContext(text: String, language: Language) {
        contextAnalyzer?.updateContext(text: text, language: language)
        logDebug("Context manually updated: '\(text)' → \(language)")
    }
    
    /// Получает текущий контекст
    func getCurrentContext() -> [String: Any] {
        guard let analyzer = contextAnalyzer else {
            return ["error": "ContextAnalyzer not initialized"]
        }
        
        let context = analyzer.getCurrentContext()
        let stats = analyzer.getStatistics()
        
        return [
            "currentContext": context.description,
            "statistics": stats
        ]
    }
    
    /// Очищает контекст
    func clearContext() {
        contextAnalyzer?.clearContext()
        logDebug("Context cleared")
    }
    
    /// Тестирует нейросетевой классификатор языка
    func testNeuralLanguageClassifier(text: String, context: ClassificationContext? = nil) -> [String: Any] {
        guard let classifier = neuralLanguageClassifier else {
            return ["error": "NeuralLanguageClassifier not initialized"]
        }
        
        let result = classifier.classifyLanguage(text, context: context)
        
        return [
            "text": text,
            "result": result.description,
            "language": String(describing: result.language),
            "confidence": result.confidence,
            "method": result.method.rawValue,
            "isConfident": result.isConfident,
            "features": result.features?.description ?? "nil"
        ]
    }
    
    /// Тестирует корректор опечаток
    func testTypoCorrector(text: String, language: Language? = nil, context: CorrectionContext? = nil) -> [String: Any] {
        guard let corrector = typoCorrector else {
            return ["error": "TypoCorrector not initialized"]
        }
        
        let result = corrector.correctTypos(in: text, language: language, context: context)
        
        return [
            "originalText": result.originalText,
            "correctedText": result.correctedText,
            "description": result.description,
            "confidence": result.confidence,
            "applied": result.applied,
            "corrections": result.corrections.map { $0.description }
        ]
    }
    
    /// Тестирует движок автодополнения
    func testAutoCompleteEngine(prefix: String, language: Language? = nil, context: CompletionContext? = nil) -> [String: Any] {
        guard let engine = autoCompleteEngine else {
            return ["error": "AutoCompleteEngine not initialized"]
        }
        
        let completions = engine.getCompletions(for: prefix, language: language, context: context)
        
        return [
            "prefix": prefix,
            "completions": completions.map { $0.description },
            "count": completions.count,
            "suggestions": completions.map { $0.word }
        ]
    }
    
    /// Тестирует менеджер обучения
    func testLearningManager() -> [String: Any] {
        guard let manager = learningManager else {
            return ["error": "LearningManager not initialized"]
        }
        
        // Создаем тестовое событие обучения
        let testEvent = LearningEvent(
            type: .languageSelection,
            language: .english,
            applicationBundleId: "com.apple.TextEdit",
            applicationType: .textEditor,
            context: LearningContext(
                applicationBundleId: "com.apple.TextEdit",
                applicationType: .textEditor,
                textContext: "Hello world",
                isSecureField: false
            )
        )
        
        // Обучаем на событии
        manager.learn(from: testEvent)
        
        // Получаем статистику
        let stats = manager.getStatistics()
        
        return [
            "eventProcessed": testEvent.description,
            "statistics": stats,
            "exportData": manager.exportLearningData()
        ]
    }
    
    /// Получает статистику всех компонентов
    func getAllStatistics() -> [String: Any] {
        var statistics: [String: Any] = [:]
        
        if let analyzer = contextAnalyzer {
            statistics["contextAnalyzer"] = analyzer.getStatistics()
        }
        
        if let classifier = neuralLanguageClassifier {
            statistics["neuralLanguageClassifier"] = classifier.getStatistics()
        }
        
        if let corrector = typoCorrector {
            statistics["typoCorrector"] = corrector.getStatistics()
        }
        
        if let engine = autoCompleteEngine {
            statistics["autoCompleteEngine"] = engine.getStatistics()
        }
        
        if let manager = learningManager {
            statistics["learningManager"] = manager.getStatistics()
        }
        
        // Базовая статистика движка
        statistics["engine"] = [
            "isRunning": isRunning,
            "uptime": startTime.map { Date().timeIntervalSince($0) } ?? 0,
            "configVersion": config.version
        ]
        
        return statistics
    }
    
    // MARK: - Private Methods
    
    private func configureComponents() {
        // Настраиваем асинхронный процессор
        asyncProcessor.configureConcurrencyLimits(
            high: 2,
            normal: 4,
            low: 8
        )
        
        // Настраиваем кэш-менеджер
        cacheManager.setEnabled(config.cache.enabled)
        
        // Настраиваем мониторинг производительности
        performanceMonitor.setSamplingInterval(60) // Каждую минуту
    }
    
    private func setupPerformanceMonitoring() {
        // Настраиваем обработчик обновления метрик
        performanceMonitor.onMetricsUpdated = { [weak self] metrics in
            self?.handleMetricsUpdate(metrics)
        }
    }
    
    private func initializeCoreComponents() throws {
        do {
            // Инициализируем анализатор контекста
            contextAnalyzer = ContextAnalyzer()
            
            // Настраиваем анализатор контекста на основе конфигурации
            if let analyzer = contextAnalyzer {
                try analyzer.configure(
                    isEnabled: config.features.enableContextualAnalysis,
                    contextWeight: 0.6,
                    semanticWeight: 0.2,
                    languageWeight: 0.2
                )
            }
            
            // Инициализируем нейросетевой классификатор языка
            neuralLanguageClassifier = NeuralLanguageClassifier()
            if let classifier = neuralLanguageClassifier {
                // Force enable for testing Stage 3
                try classifier.configure(
                    isEnabled: true, // config.features.enableNeuralLanguageDetection,
                    confidenceThreshold: 0.7
                )
            }
            
            // Инициализируем корректор опечаток
            typoCorrector = TypoCorrector()
            if let corrector = typoCorrector {
                try corrector.configure(
                    isEnabled: config.features.enableTypoCorrection,
                    autoCorrectEnabled: config.exceptions.autoCorrectTypos,
                    suggestionEnabled: true,
                    maxEditDistance: 2,
                    minConfidence: 0.7,
                    contextWeight: 0.3
                )
            }
            
            // Инициализируем движок автодополнения
            autoCompleteEngine = AutoCompleteEngine()
            if let engine = autoCompleteEngine {
                try engine.configure(
                    isEnabled: config.features.enableAutoComplete,
                    maxSuggestions: 5,
                    minPrefixLength: 2,
                    contextWeight: 0.4,
                    learningWeight: 0.3
                )
            }
        } catch {
            logError(error, context: "Failed to initialize core components")
            throw EngineError.componentInitializationError(error)
        }
        
        // Инициализируем менеджер обучения
        learningManager = LearningManager()
        if let manager = learningManager {
            // Загружаем сохраненные данные обучения
            _ = manager.loadSavedData()
        }
        
        // Инициализируем компоненты Этапа 4
        bufferManager = BufferManager()
        layoutSwitcher = LayoutSwitcher.shared
        
        // Инициализируем EventProcessor со всеми зависимостями
        if let bufferManager = bufferManager,
           let contextAnalyzer = contextAnalyzer,
           let layoutSwitcher = layoutSwitcher,
           let neuralLanguageClassifier = neuralLanguageClassifier,
           let typoCorrector = typoCorrector,
           let autoCompleteEngine = autoCompleteEngine,
           let learningManager = learningManager {
            
            eventProcessor = EventProcessor(
                bufferManager: bufferManager,
                contextAnalyzer: contextAnalyzer,
                layoutSwitcher: layoutSwitcher,
                neuralLanguageClassifier: neuralLanguageClassifier,
                typoCorrector: typoCorrector,
                autoCompleteEngine: autoCompleteEngine,
                learningManager: learningManager,
                config: ProcessingConfig.default
            )
        }
        
        // Инициализируем EventTapManager
        eventTapManager = EventTapManager.shared
        if let eventProcessor = eventProcessor {
            eventTapManager?.setEventProcessor(eventProcessor)
        }
        
        logDebug("""
        Core components initialized:
        - ContextAnalyzer: \(contextAnalyzer != nil)
        - NeuralLanguageClassifier: \(neuralLanguageClassifier != nil)
        - TypoCorrector: \(typoCorrector != nil)
        - AutoCompleteEngine: \(autoCompleteEngine != nil)
        - LearningManager: \(learningManager != nil)
        - BufferManager: \(bufferManager != nil)
        - LayoutSwitcher: \(layoutSwitcher != nil)
        - EventProcessor: \(eventProcessor != nil)
        - EventTapManager: \(eventTapManager != nil)
        """)
    }
    
    private func applyConfiguration() throws {
        logDebug("Applying configuration...")
        
        do {
            // 1. Применяем настройки производительности
            try applyPerformanceSettings()
            
            // 2. Применяем настройки кэширования
            try applyCacheSettings()
            
            // 3. Применяем настройки функций
            try applyFeatureSettings()
            
            // 4. Применяем правила исключений
            try applyExceptionRules()
            
            logInfo("Configuration applied successfully")
        } catch {
            logError(error, context: "Failed to apply configuration")
            throw EngineError.configurationError(error)
        }
    }
    
    private func applyPerformanceSettings() throws {
        let perf = config.performance
        
        // Проверяем валидность настроек производительности
        guard perf.bufferSize > 0 else {
            throw EngineError.invalidConfiguration("Buffer size must be greater than 0")
        }
        
        guard perf.maxProcessingTime > 0 else {
            throw EngineError.invalidConfiguration("Max processing time must be greater than 0")
        }
        
        // Настраиваем асинхронную обработку
        if !perf.enableAsyncProcessing {
            logDebug("Async processing disabled")
        }
        
        // Настраиваем максимальное время обработки
        logDebug("Performance settings: bufferSize=\(perf.bufferSize), maxProcessingTime=\(perf.maxProcessingTime)s")
    }
    
    private func applyCacheSettings() throws {
        let cache = config.cache
        
        // Проверяем валидность настроек кэша
        guard cache.cacheTTL >= 0 else {
            throw EngineError.invalidConfiguration("Cache TTL must be non-negative")
        }
        
        if !cache.enabled {
            logDebug("Cache disabled")
            cacheManager.clearAll()
        } else {
            logDebug("Cache enabled with TTL: \(cache.cacheTTL)s")
        }
    }
    
    private func applyFeatureSettings() throws {
        let features = config.features
        
        logDebug("Feature flags:")
        logDebug("  - Contextual analysis: \(features.enableContextualAnalysis)")
        logDebug("  - Neural language detection: \(features.enableNeuralLanguageDetection)")
        logDebug("  - Typo correction: \(features.enableTypoCorrection)")
        logDebug("  - Auto-complete: \(features.enableAutoComplete)")
        logDebug("  - System dictionary: \(features.enableSystemDictionary)")
        logDebug("  - Yandex.Speller: \(features.enableYandexSpeller)")
        logDebug("  - Learning mode: \(features.enableLearningMode)")
        logDebug("  - Statistics: \(features.enableStatistics)")
    }
    
    private func applyExceptionRules() throws {
        let exceptions = config.exceptions
        
        logDebug("Exception rules:")
        logDebug("  - Global enabled: \(exceptions.globalEnabled)")
        logDebug("  - Auto-correct typos: \(exceptions.autoCorrectTypos)")
        logDebug("  - Auto-complete: \(exceptions.autoCompleteEnabled)")
        logDebug("  - Learning mode: \(exceptions.learningModeEnabled)")
        logDebug("  - Word exceptions: \(exceptions.wordExceptions.count)")
        logDebug("  - App exceptions: \(exceptions.appExceptions.count)")
        logDebug("  - Context rules: \(exceptions.contextRules.count)")
    }
    
    private func applyConfigurationChanges(from oldConfig: AppConfig, to newConfig: AppConfig) {
        // Проверяем изменения в настройках производительности
        if oldConfig.performance.enableAsyncProcessing != newConfig.performance.enableAsyncProcessing {
            logDebug("Async processing changed to: \(newConfig.performance.enableAsyncProcessing)")
        }
        
        if oldConfig.performance.enablePerformanceMonitoring != newConfig.performance.enablePerformanceMonitoring {
            performanceMonitor.setEnabled(newConfig.performance.enablePerformanceMonitoring)
        }
        
        // Проверяем изменения в настройках кэширования
        if oldConfig.cache.enabled != newConfig.cache.enabled {
            cacheManager.setEnabled(newConfig.cache.enabled)
        }
        
        // Проверяем изменения в функциях
        if oldConfig.features.enableSystemDictionary != newConfig.features.enableSystemDictionary {
            logDebug("System dictionary changed to: \(newConfig.features.enableSystemDictionary)")
        }
        
        // Проверяем изменения в исключениях
        if oldConfig.exceptions.globalEnabled != newConfig.exceptions.globalEnabled {
            logDebug("Global enabled changed to: \(newConfig.exceptions.globalEnabled)")
        }
    }
    
    private func handleMetricsUpdate(_ metrics: PerformanceMetrics) {
        // Логируем метрики если включен мониторинг
        if config.performance.enablePerformanceMonitoring {
            logDebug("""
            Performance update:
            - Events processed: \(metrics.totalEventsProcessed)
            - Cache hit rate: \(String(format: "%.1f", metrics.cacheHitRate * 100))%
            - Memory usage: \(formatBytes(metrics.memoryUsage))
            - Uptime: \(String(format: "%.1f", metrics.uptime))s
            """)
        }
        
        // Проверяем аномалии производительности
        checkForPerformanceAnomalies(metrics)
    }
    
    private func checkForPerformanceAnomalies(_ metrics: PerformanceMetrics) {
        // Проверяем высокую загрузку памяти
        if metrics.memoryUsage > 100 * 1024 * 1024 { // 100MB
            logDebug("Warning: High memory usage detected: \(formatBytes(metrics.memoryUsage))")
        }
        
        // Проверяем низкий hit rate кэша
        if metrics.cacheHitRate < 0.3 && metrics.cacheHits + metrics.cacheMisses > 100 {
            logDebug("Warning: Low cache hit rate: \(String(format: "%.1f", metrics.cacheHitRate * 100))%")
        }
        
        // Проверяем медленную обработку событий
        if metrics.eventProcessingTime > 0.01 && metrics.totalEventsProcessed > 0 {
            let avgTime = metrics.eventProcessingTime / Double(metrics.totalEventsProcessed)
            if avgTime > 0.005 { // 5ms
                logDebug("Warning: Slow event processing: \(String(format: "%.3f", avgTime * 1000))ms avg")
        }
    }
    
    // MARK: - Test Methods for Stage 4 Components
    
    /// Тестирует BufferManager
    func testBufferManager() -> [String: Any] {
        guard let bufferManager = bufferManager else {
            return ["error": "BufferManager not initialized"]
        }
        
        // Тест 1: Добавление символов
        bufferManager.clear()
        bufferManager.addCharacter("H")
        bufferManager.addCharacter("e")
        bufferManager.addCharacter("l")
        bufferManager.addCharacter("l")
        bufferManager.addCharacter("o")
        
        let word1 = bufferManager.getCurrentWord()
        
        // Тест 2: Добавление пробела (граница слова)
        bufferManager.addCharacter(" ")
        
        let shouldProcess1 = bufferManager.shouldProcessWord()
        if shouldProcess1 {
            bufferManager.clearWord()
        }
        
        // Тест 3: Добавление другого слова
        bufferManager.addCharacter("W")
        bufferManager.addCharacter("o")
        bufferManager.addCharacter("r")
        bufferManager.addCharacter("l")
        bufferManager.addCharacter("d")
        
        let word2 = bufferManager.getCurrentWord()
        let shouldProcess2 = bufferManager.shouldProcessWord()
        
        // Тест 4: Полная очистка
        bufferManager.clear()
        
        let state = bufferManager.getState()
        
        return [
            "test1_word": word1 ?? "nil",
            "test1_shouldProcess": shouldProcess1,
            "test2_word": word2 ?? "nil",
            "test2_shouldProcess": shouldProcess2,
            "finalState": state,
            "description": "BufferManager tests completed"
        ]
    }
    
    /// Тестирует LayoutSwitcher
    func testLayoutSwitcher() -> [String: Any] {
        guard let layoutSwitcher = layoutSwitcher else {
            return ["error": "LayoutSwitcher not initialized"]
        }
        
        // Тест 1: Получение текущей раскладки
        let currentLayout = layoutSwitcher.getCurrentLayout()
        
        // Тест 2: Получение доступных раскладок
        let availableLayouts = layoutSwitcher.getAvailableLayouts()
        
        // Тест 3: Поиск раскладки для языка
        let englishLayout = layoutSwitcher.getLayoutForLanguage(.english)
        let russianLayout = layoutSwitcher.getLayoutForLanguage(.russian)
        
        // Тест 4: Генерация событий клавиш
        let keyEvents = layoutSwitcher.getKeyEventsForWord("test", inLanguage: .english)
        
        let stats = layoutSwitcher.getStatistics()
        
        return [
            "currentLayout": currentLayout?.description ?? "nil",
            "availableLayoutsCount": availableLayouts.count,
            "englishLayout": englishLayout?.description ?? "nil",
            "russianLayout": russianLayout?.description ?? "nil",
            "keyEventsGenerated": keyEvents.count,
            "statistics": stats,
            "description": "LayoutSwitcher tests completed"
        ]
    }
    
    /// Тестирует EventTapManager
    func testEventTapManager() -> [String: Any] {
        guard let eventTapManager = eventTapManager else {
            return ["error": "EventTapManager not initialized"]
        }
        
        let stats = eventTapManager.getStatistics()
        
        return [
            "statistics": stats,
            "description": "EventTapManager tests completed"
        ]
    }
    
    /// Тестирует EventProcessor
    func testEventProcessor() -> [String: Any] {
        guard let eventProcessor = eventProcessor else {
            return ["error": "EventProcessor not initialized"]
        }
        
        let stats = eventProcessor.getStatistics()
        
        return [
            "statistics": stats,
            "description": "EventProcessor tests completed"
        ]
    }
    
    /// Тестирует все компоненты Этапа 4
    func testStage4Components() -> [String: Any] {
        logDebug("=== Testing Stage 4 Components ===")
        
        let bufferManagerTest = testBufferManager()
        let layoutSwitcherTest = testLayoutSwitcher()
        let eventTapManagerTest = testEventTapManager()
        let eventProcessorTest = testEventProcessor()
        
        logDebug("BufferManager: \(bufferManagerTest["description"] ?? "nil")")
        logDebug("LayoutSwitcher: \(layoutSwitcherTest["description"] ?? "nil")")
        logDebug("EventTapManager: \(eventTapManagerTest["description"] ?? "nil")")
        logDebug("EventProcessor: \(eventProcessorTest["description"] ?? "nil")")
        
        return [
            "bufferManager": bufferManagerTest,
            "layoutSwitcher": layoutSwitcherTest,
            "eventTapManager": eventTapManagerTest,
            "eventProcessor": eventProcessorTest,
            "description": "Stage 4 components tests completed"
        ]
    }
}
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var size = Double(bytes)
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", size, units[unitIndex])
    }
    
    deinit {
        stop()
        logDebug("BabylonFishEngine deinitialized")
    }
}

// MARK: - Ошибки движка

enum EngineError: Error {
    case invalidConfiguration(String)
    case configurationError(Error)
    case componentInitializationError(Error)
    case eventTapError(String)
    case permissionError(String)
}
