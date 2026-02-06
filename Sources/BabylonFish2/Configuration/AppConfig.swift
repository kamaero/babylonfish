import Foundation

/// Основная конфигурация приложения
struct AppConfig: Codable {
    var version: Int
    var languageProfiles: [LanguageProfile]
    var hotkeys: HotkeyConfig
    var exceptions: ExceptionRules
    var performance: PerformanceSettings
    
    /// Создает конфигурацию по умолчанию
    static func `default`() -> AppConfig {
        return AppConfig(
            version: 2,
            languageProfiles: [LanguageProfile.englishRussian()],
            hotkeys: HotkeyConfig.default(),
            exceptions: ExceptionRules.default(),
            performance: PerformanceSettings.default()
        )
    }
    
    /// Сохраняет конфигурацию в UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "babylonfish_config_v2")
        }
    }
    
    /// Загружает конфигурацию из UserDefaults
    static func load() -> AppConfig {
        guard let data = UserDefaults.standard.data(forKey: "babylonfish_config_v2"),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return .default()
        }
        return config
    }
    
    /// Мигрирует данные из старой версии (UserDefaults)
    static func migrateFromV1() {
        // Проверяем, есть ли старые настройки
        let hasOldSettings = UserDefaults.standard.object(forKey: "autoSwitchEnabled") != nil
        
        guard hasOldSettings else { return }
        
        logDebug("Migrating settings from v1 to v2...")
        
        var config = AppConfig.default()
        
        // Мигрируем настройки
        if let autoSwitchEnabled = UserDefaults.standard.object(forKey: "autoSwitchEnabled") as? Bool {
            config.exceptions.globalEnabled = autoSwitchEnabled
        }
        
        // Мигрируем исключения
        if let exceptionsData = UserDefaults.standard.data(forKey: "exceptions"),
           let oldExceptions = try? JSONDecoder().decode([String].self, from: exceptionsData) {
            config.exceptions.wordExceptions.formUnion(oldExceptions)
        }
        
        // Мигрируем ignored words из LanguageManager (старый ключ)
        if let oldIgnored = UserDefaults.standard.array(forKey: "bf_ignored_words") as? [String] {
            config.exceptions.wordExceptions.formUnion(oldIgnored)
        }
        
        // Мигрируем learned words (остаются в старых ключах, которые загружает LearningManager)
        // Ключи "bf_user_words_en" и "bf_user_words_ru" уже используются новым LearningManager
        
        // Сохраняем новую конфигурацию
        config.save()
        
        // Помечаем миграцию как выполненную
        UserDefaults.standard.set(true, forKey: "migration_v1_to_v2_complete")
        
        logDebug("Migration completed successfully")
    }
}

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
    
    static func `default`() -> HotkeyConfig {
        return HotkeyConfig(
            doubleShiftEnabled: true,
            forceSwitchKey: nil,
            quickFixPanelKey: nil,
            toggleSwitchingKey: nil
        )
    }
}

/// Правила исключений
struct ExceptionRules: Codable {
    var globalEnabled: Bool
    var appExceptions: [AppException]
    var wordExceptions: Set<String>
    var contextRules: [ContextRule]
    
    static func `default`() -> ExceptionRules {
        return ExceptionRules(
            globalEnabled: true,
            appExceptions: [],
            wordExceptions: [],
            contextRules: [
                ContextRule(type: .terminal, action: .disableSwitching),
                ContextRule(type: .game, action: .disableSwitching),
                ContextRule(type: .passwordField, action: .disableSwitching)
            ]
        )
    }
}

/// Настройки производительности
struct PerformanceSettings: Codable {
    var bufferSize: Int
    var autoSwitchDelay: TimeInterval
    var suggestionDelay: TimeInterval
    var enablePerformanceMonitoring: Bool
    
    static func `default`() -> PerformanceSettings {
        return PerformanceSettings(
            bufferSize: 15,
            autoSwitchDelay: 0.35,
            suggestionDelay: 0.5,
            enablePerformanceMonitoring: false
        )
    }
}

/// Тип контекста (для ContextRule)
enum ContextType: String, Codable {
    case terminal
    case ide
    case game
    case passwordField
    case custom
}

/// Действие в контексте
enum ContextAction: String, Codable {
    case disableSwitching
    case enableSwitching
    case suggestOnly
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
}