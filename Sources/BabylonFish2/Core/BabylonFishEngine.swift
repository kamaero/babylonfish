import Foundation
import Cocoa

/// Главный движок BabylonFish 2.0
class BabylonFishEngine {
    // Компоненты
    private var config: AppConfig
    private let learningManager: LearningManager
    private let languageDetector: LanguageDetector
    private let suggestionEngine: SuggestionEngine
    private let contextAnalyzer: ContextAnalyzer
    private let bufferManager: BufferManager
    private let layoutSwitcher: LayoutSwitcher
    private let eventProcessor: EventProcessor
    private let eventTapManager: EventTapManager
    private let doubleShiftHandler: DoubleShiftHandler
    
    // UI компоненты
    weak var suggestionWindow: SuggestionWindow?
    
    /// Текущая конфигурация (только для чтения)
    var currentConfig: AppConfig {
        return config
    }
    
    /// Инициализирует движок с конфигурацией
    init(config: AppConfig = AppConfig.load()) {
        self.config = config
        
        // Инициализируем компоненты в правильном порядке
        learningManager = LearningManager()
        languageDetector = LanguageDetector(learningManager: learningManager)
        suggestionEngine = SuggestionEngine(learningManager: learningManager)
        contextAnalyzer = ContextAnalyzer()
        bufferManager = BufferManager()
        layoutSwitcher = LayoutSwitcher()
        doubleShiftHandler = DoubleShiftHandler(
            config: config.hotkeys,
            layoutSwitcher: layoutSwitcher,
            languageDetector: languageDetector
        )
        
        eventProcessor = EventProcessor(
            bufferManager: bufferManager,
            layoutSwitcher: layoutSwitcher,
            languageDetector: languageDetector,
            contextAnalyzer: contextAnalyzer,
            suggestionEngine: suggestionEngine
        )
        
        eventTapManager = EventTapManager(
            eventProcessor: eventProcessor,
            bufferManager: bufferManager,
            layoutSwitcher: layoutSwitcher
        )
        
        // Connect Double Shift
        eventProcessor.onDoubleShift = { [weak self] in
            self?.handleDoubleShift()
        }
        
        // Настраиваем связи
        eventProcessor.suggestionWindow = nil // Будет установлено позже
    }
    
    /// Запускает движок
    func start() -> Bool {
        logDebug("BabylonFishEngine: Starting...")
        
        // Применяем конфигурацию
        applyConfiguration()
        
        // Запускаем event tap
        let success = eventTapManager.start()
        
        if success {
            logDebug("BabylonFishEngine: Started successfully")
        } else {
            logDebug("BabylonFishEngine: Failed to start")
        }
        
        return success
    }
    
    /// Останавливает движок
    func stop() {
        logDebug("BabylonFishEngine: Stopping...")
        eventTapManager.stop()
    }
    
    /// Применяет конфигурацию к компонентам
    private func applyConfiguration() {
        logDebug("Applying configuration...")
        
        // 1. Применяем настройки производительности
        applyPerformanceSettings()
        
        // 2. Применяем правила исключений
        applyExceptionRules()
        
        // 3. Применяем настройки горячих клавиш
        applyHotkeySettings()
        
        logDebug("Configuration applied successfully")
    }
    
    /// Применяет настройки производительности
    private func applyPerformanceSettings() {
        // BufferManager
        bufferManager.setMaxBufferLength(config.performance.bufferSize)
        
        // EventProcessor delays
        eventProcessor.boundaryDebounce = config.performance.autoSwitchDelay
        eventProcessor.doubleShiftThreshold = 0.3 // Можно вынести в конфиг если нужно
        
        logDebug("Performance settings applied: bufferSize=\(config.performance.bufferSize), autoSwitchDelay=\(config.performance.autoSwitchDelay)")
    }
    
    /// Применяет правила исключений
    private func applyExceptionRules() {
        // Global auto-switch enabled
        eventProcessor.autoSwitchEnabled = config.exceptions.globalEnabled
        
        // Auto-correct typos enabled
        eventProcessor.autoCorrectTyposEnabled = config.exceptions.autoCorrectTypos
        
        // Word exceptions в LearningManager
        learningManager.setIgnoredWords(config.exceptions.wordExceptions)
        
        // Context rules в ContextAnalyzer
        contextAnalyzer.setContextRules(config.exceptions.contextRules)
        contextAnalyzer.setAppExceptions(config.exceptions.appExceptions)
        
        logDebug("Exception rules applied: globalEnabled=\(config.exceptions.globalEnabled), \(config.exceptions.wordExceptions.count) word exceptions, \(config.exceptions.contextRules.count) context rules")
    }
    
    /// Применяет настройки горячих клавиш
    private func applyHotkeySettings() {
        doubleShiftHandler.updateConfig(config.hotkeys)
        logDebug("Hotkey settings applied: doubleShiftEnabled=\(config.hotkeys.doubleShiftEnabled)")
    }
    
    /// Обновляет конфигурацию
    func updateConfiguration(_ newConfig: AppConfig) {
        logDebug("Updating configuration on the fly...")
        config = newConfig
        applyConfiguration()
        logDebug("Configuration updated successfully")
    }
    
    /// Обрабатывает событие двойного нажатия Shift
    func handleDoubleShift() {
        doubleShiftHandler.handleDoubleShift()
    }
    
    /// Возвращает статистику работы
    func getStatistics() -> EngineStatistics {
        // TODO: Собирать статистику
        return EngineStatistics()
    }
    
    // MARK: - UI Integration
    
    func setSuggestionWindow(_ window: SuggestionWindow?) {
        suggestionWindow = window
        eventProcessor.suggestionWindow = window
    }
}

/// Статистика работы движка
struct EngineStatistics {
    var wordsProcessed: Int = 0
    var switchesMade: Int = 0
    var correctionsMade: Int = 0
    var uptime: TimeInterval = 0
    var performanceMetrics: [String: Double] = [:]
}