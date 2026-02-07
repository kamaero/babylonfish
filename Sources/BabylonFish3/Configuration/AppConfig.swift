import Foundation

/// Основная конфигурация приложения BabylonFish 3.0
struct AppConfig: Codable {
    var version: Int
    var languageProfiles: [LanguageProfile]
    var hotkeys: HotkeyConfig
    var exceptions: ExceptionRules
    var performance: PerformanceSettings
    var features: FeatureFlags
    var cache: CacheSettings
    
    /// Создает конфигурацию по умолчанию
    static func `default`() -> AppConfig {
        return AppConfig(
            version: 3,
            languageProfiles: [LanguageProfile.englishRussian()],
            hotkeys: HotkeyConfig.default(),
            exceptions: ExceptionRules.default(),
            performance: PerformanceSettings.default(),
            features: FeatureFlags.default(),
            cache: CacheSettings.default()
        )
    }
    
    /// Сохраняет конфигурацию в UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "babylonfish_config_v3")
            logDebug("Configuration saved: version \(version)")
        }
    }
    
    /// Загружает конфигурацию из UserDefaults
    static func load() -> AppConfig {
        guard let data = UserDefaults.standard.data(forKey: "babylonfish_config_v3"),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return .default()
        }
        return config
    }
    
    /// Мигрирует данные из предыдущих версий
    static func migrateFromPreviousVersions() {
        // Проверяем, есть ли настройки v2
        if UserDefaults.standard.data(forKey: "babylonfish_config_v2") != nil {
            migrateFromV2()
        }
        // Проверяем, есть ли настройки v1
        else if UserDefaults.standard.object(forKey: "autoSwitchEnabled") != nil {
            migrateFromV1()
        }
    }
    
    /// Мигрирует из версии 2
    private static func migrateFromV2() {
        logDebug("Migrating settings from v2 to v3...")
        
        guard let data = UserDefaults.standard.data(forKey: "babylonfish_config_v2"),
              let v2Config = try? JSONDecoder().decode(AppConfigV2.self, from: data) else {
            logDebug("Failed to load v2 config")
            return
        }
        
        var config = AppConfig.default()
        
        // Мигрируем настройки производительности
        config.performance.bufferSize = v2Config.performance.bufferSize
        config.performance.autoSwitchDelay = v2Config.performance.autoSwitchDelay
        config.performance.suggestionDelay = v2Config.performance.suggestionDelay
        
        // Мигрируем исключения
        config.exceptions.globalEnabled = v2Config.exceptions.globalEnabled
        config.exceptions.autoCorrectTypos = v2Config.exceptions.autoCorrectTypos
        config.exceptions.wordExceptions = v2Config.exceptions.wordExceptions
        
        // Сохраняем новую конфигурацию
        config.save()
        
        // Помечаем миграцию как выполненную
        UserDefaults.standard.set(true, forKey: "migration_v2_to_v3_complete")
        
        logDebug("Migration from v2 completed successfully")
    }
    
    /// Мигрирует из версии 1
    private static func migrateFromV1() {
        logDebug("Migrating settings from v1 to v3...")
        
        var config = AppConfig.default()
        
        // Мигрируем настройки из UserDefaults
        if let autoSwitchEnabled = UserDefaults.standard.object(forKey: "autoSwitchEnabled") as? Bool {
            config.exceptions.globalEnabled = autoSwitchEnabled
        }
        
        // Мигрируем исключения
        if let exceptionsData = UserDefaults.standard.data(forKey: "exceptions"),
           let oldExceptions = try? JSONDecoder().decode([String].self, from: exceptionsData) {
            config.exceptions.wordExceptions.formUnion(oldExceptions)
        }
        
        // Мигрируем ignored words
        if let oldIgnored = UserDefaults.standard.array(forKey: "bf_ignored_words") as? [String] {
            config.exceptions.wordExceptions.formUnion(oldIgnored)
        }
        
        // Сохраняем новую конфигурацию
        config.save()
        
        // Помечаем миграцию как выполненную
        UserDefaults.standard.set(true, forKey: "migration_v1_to_v3_complete")
        
        logDebug("Migration from v1 completed successfully")
    }
}

// MARK: - Вспомогательные структуры для миграции

/// Конфигурация версии 2 (для миграции)
private struct AppConfigV2: Codable {
    var version: Int
    var languageProfiles: [LanguageProfile]
    var hotkeys: HotkeyConfigV2
    var exceptions: ExceptionRulesV2
    var performance: PerformanceSettingsV2
}

private struct HotkeyConfigV2: Codable {
    var doubleShiftEnabled: Bool
    var forceSwitchKey: KeyCombo?
    var quickFixPanelKey: KeyCombo?
    var toggleSwitchingKey: KeyCombo?
}

private struct ExceptionRulesV2: Codable {
    var globalEnabled: Bool
    var autoCorrectTypos: Bool
    var appExceptions: [AppException]
    var wordExceptions: Set<String>
    var contextRules: [ContextRule]
}

private struct PerformanceSettingsV2: Codable {
    var bufferSize: Int
    var autoSwitchDelay: TimeInterval
    var suggestionDelay: TimeInterval
    var enablePerformanceMonitoring: Bool
}

// MARK: - Основные структуры конфигурации

/// Маппинг клавиши
struct KeyMapping: Codable {
    var sourceChar: String
    var targetChar: String
    
    init(sourceChar: String, targetChar: String) {
        self.sourceChar = sourceChar
        self.targetChar = targetChar
    }
}

/// Профиль языка (пары раскладок)
struct LanguageProfile: Codable {
    var sourceLanguage: String // "en"
    var targetLanguage: String // "ru"
    var keyMapping: [Int: KeyMapping] // keyCode -> KeyMapping
    
    static func englishRussian() -> LanguageProfile {
        // Используем стандартный KeyMapper
        var mapping: [Int: KeyMapping] = [:]
        for (keyCode, chars) in KeyMapper.shared.allMappings {
            mapping[keyCode] = KeyMapping(sourceChar: chars.en, targetChar: chars.ru)
        }
        
        return LanguageProfile(
            sourceLanguage: "en",
            targetLanguage: "ru",
            keyMapping: mapping
        )
    }
}

/// Конфигурация горячих клавиш
struct HotkeyConfig: Codable {
    var doubleShiftEnabled: Bool
    var forceSwitchKey: KeyCombo?
    var quickFixPanelKey: KeyCombo?
    var toggleSwitchingKey: KeyCombo?
    var showStatisticsKey: KeyCombo?
    var toggleLearningModeKey: KeyCombo?
    
    static func `default`() -> HotkeyConfig {
        return HotkeyConfig(
            doubleShiftEnabled: true,
            forceSwitchKey: nil,
            quickFixPanelKey: nil,
            toggleSwitchingKey: nil,
            showStatisticsKey: nil,
            toggleLearningModeKey: nil
        )
    }
}

/// Правила исключений
struct ExceptionRules: Codable {
    var globalEnabled: Bool
    var autoCorrectTypos: Bool
    var autoCompleteEnabled: Bool
    var learningModeEnabled: Bool
    var appExceptions: [AppException]
    var wordExceptions: Set<String>
    var contextRules: [ContextRule]
    
    static func `default`() -> ExceptionRules {
        return ExceptionRules(
            globalEnabled: true,
            autoCorrectTypos: true,
            autoCompleteEnabled: true,
            learningModeEnabled: true,
            appExceptions: [],
            wordExceptions: [],
            contextRules: [
                ContextRule(type: .terminal, action: .disableSwitching),
                ContextRule(type: .game, action: .disableSwitching),
                ContextRule(type: .passwordField, action: .disableSwitching),
                ContextRule(type: .ide, action: .suggestOnly)
            ]
        )
    }
}

/// Настройки производительности
struct PerformanceSettings: Codable {
    var bufferSize: Int
    var autoSwitchDelay: TimeInterval
    var suggestionDelay: TimeInterval
    var autoCompleteDelay: TimeInterval
    var enablePerformanceMonitoring: Bool
    var enableAsyncProcessing: Bool
    var asyncQueuePriority: AsyncProcessor.QueuePriority
    var maxProcessingTime: TimeInterval
    
    static func `default`() -> PerformanceSettings {
        return PerformanceSettings(
            bufferSize: 20,
            autoSwitchDelay: 0.3,
            suggestionDelay: 0.4,
            autoCompleteDelay: 0.5,
            enablePerformanceMonitoring: true,
            enableAsyncProcessing: true,
            asyncQueuePriority: AsyncProcessor.QueuePriority.normal,
            maxProcessingTime: 0.05 // 50ms максимум на обработку
        )
    }
}

/// Флаги функций
struct FeatureFlags: Codable {
    var enableContextualAnalysis: Bool
    var enableNeuralLanguageDetection: Bool
    var enableTypoCorrection: Bool
    var enableAutoComplete: Bool
    var enableSystemDictionary: Bool
    var enableYandexSpeller: Bool
    var enableLearningMode: Bool
    var enableStatistics: Bool
    
    static func `default`() -> FeatureFlags {
        return FeatureFlags(
            enableContextualAnalysis: true,
            enableNeuralLanguageDetection: true, // Включено для тестирования Stage 3
            enableTypoCorrection: true,
            enableAutoComplete: true,
            enableSystemDictionary: true,
            enableYandexSpeller: false, // Опционально
            enableLearningMode: true,
            enableStatistics: true
        )
    }
}

/// Настройки кэширования
struct CacheSettings: Codable {
    var enabled: Bool
    var languageDetectionCacheSize: Int
    var spellingCheckCacheSize: Int
    var typoCorrectionCacheSize: Int
    var autoCompleteCacheSize: Int
    var cacheTTL: TimeInterval
    
    static func `default`() -> CacheSettings {
        return CacheSettings(
            enabled: true,
            languageDetectionCacheSize: 1000,
            spellingCheckCacheSize: 2000,
            typoCorrectionCacheSize: 1000,
            autoCompleteCacheSize: 500,
            cacheTTL: 3600 // 1 час
        )
    }
}

// MARK: - Вспомогательные типы



/// Тип контекста (для ContextRule)
enum ContextType: String, Codable {
    case terminal
    case ide
    case game
    case passwordField
    case browser
    case textEditor
    case custom
}

/// Действие в контексте
enum ContextAction: String, Codable {
    case disableSwitching
    case enableSwitching
    case suggestOnly
    case autoCorrectOnly
}

/// Правило для контекста
struct ContextRule: Codable {
    var type: ContextType
    var action: ContextAction
    var customIdentifier: String?
}

/// Исключение для приложения
struct AppException: Codable {
    var bundleId: String?
    var processName: String?
    var windowTitle: String?
    var action: ContextAction
    
    static func terminal() -> AppException {
        return AppException(
            bundleId: "com.apple.Terminal",
            processName: nil,
            windowTitle: nil,
            action: .disableSwitching
        )
    }
    
    static func xcode() -> AppException {
        return AppException(
            bundleId: "com.apple.dt.Xcode",
            processName: nil,
            windowTitle: nil,
            action: .suggestOnly
        )
    }
}