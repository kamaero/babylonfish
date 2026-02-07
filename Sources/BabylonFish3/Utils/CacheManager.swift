import Foundation

/// Тип кэшируемых данных
enum CacheType {
    case languageDetection
    case spellingCheck
    case suggestions
    case autoComplete
    case typoCorrection
    case learningData
    
    var maxSize: Int {
        switch self {
        case .languageDetection:
            return 1000
        case .spellingCheck:
            return 2000
        case .suggestions:
            return 500
        case .autoComplete:
            return 300
        case .typoCorrection:
            return 1000
        case .learningData:
            return 100 // Данные обучения меньше, но важнее
        }
    }
    
    var ttl: TimeInterval {
        switch self {
        case .languageDetection:
            return 3600 // 1 час
        case .spellingCheck:
            return 7200 // 2 часа
        case .suggestions:
            return 1800 // 30 минут
        case .autoComplete:
            return 900  // 15 минут
        case .typoCorrection:
            return 3600 // 1 час
        case .learningData:
            return 7 * 24 * 3600 // 1 неделя
        }
    }
}

/// Запись в кэше
struct CacheEntry<T> {
    let value: T
    let timestamp: Date
    let accessCount: Int
    
    init(value: T) {
        self.value = value
        self.timestamp = Date()
        self.accessCount = 1
    }
    
    mutating func incrementAccess() {
        // В реальной реализации нужно сделать структуру mutable
        // или использовать класс
    }
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > 3600 // 1 час по умолчанию
    }
}

/// Менеджер кэширования для BabylonFish
class CacheManager {
    static let shared = CacheManager()
    
    // Кэши для разных типов данных
    private var languageDetectionCache: [String: CacheEntry<(Language, Double)>] = [:]
    private var spellingCheckCache: [String: CacheEntry<Bool>] = [:]
    private var suggestionsCache: [String: CacheEntry<[String]>] = [:]
    private var autoCompleteCache: [String: CacheEntry<[String]>] = [:]
    private var typoCorrectionCache: [String: CacheEntry<String>] = [:]
    private var learningDataCache: [String: CacheEntry<Data>] = [:]
    private let cacheQueue = DispatchQueue(label: "com.babylonfish.cache")
    
    // Статистика
    private var hitCounts: [CacheType: Int] = [:]
    private var missCounts: [CacheType: Int] = [:]
    private var evictionCounts: [CacheType: Int] = [:]
    
    // Конфигурация
    private var isEnabled = true
    private var cleanupInterval: TimeInterval = 300 // 5 минут
    private var lastCleanupTime: Date = Date()
    
    private init() {
        // Запускаем периодическую очистку устаревших записей
        startCleanupTimer()
    }
    
    // MARK: - Public API
    
    /// Получает значение из кэша
    func get<T>(key: String, type: CacheType) -> T? {
        guard isEnabled else { return nil }
        
        let cache = getCache(for: type) as? [String: CacheEntry<T>]
        guard let entry = cache?[key] else {
            recordMiss(type: type)
            return nil
        }
        
        if Date().timeIntervalSince(entry.timestamp) > type.ttl {
            remove(key: key, type: type)
            recordMiss(type: type)
            return nil
        }
        
        recordHit(type: type)
        // Здесь нужно обновить счетчик доступа и timestamp
        return entry.value
    }
    
    /// Сохраняет значение в кэш
    func set<T>(key: String, value: T, type: CacheType) {
        guard isEnabled else { return }
        
        var cache = getCache(for: type) as? [String: CacheEntry<T>]
        if cache == nil {
            cache = [:]
        }
        
        // Проверяем размер кэша и удаляем старые записи если нужно
        if let count = cache?.count, count >= type.maxSize {
            evictOldEntries(for: type)
        }
        
        cache?[key] = CacheEntry(value: value)
        setCache(cache, for: type)
    }
    
    /// Удаляет значение из кэша
    func remove(key: String, type: CacheType) {
        var cache = getCache(for: type) as? [String: Any]
        cache?.removeValue(forKey: key)
        setCache(cache, for: type)
    }
    
    /// Очищает кэш определенного типа
    func clear(type: CacheType) {
        switch type {
        case .languageDetection:
            languageDetectionCache.removeAll()
        case .spellingCheck:
            spellingCheckCache.removeAll()
        case .suggestions:
            suggestionsCache.removeAll()
        case .autoComplete:
            autoCompleteCache.removeAll()
        case .typoCorrection:
            typoCorrectionCache.removeAll()
        case .learningData:
            // Learning data cache is handled separately
            break
        }
    }
    
    /// Очищает все кэши
    func clearAll() {
        languageDetectionCache.removeAll()
        spellingCheckCache.removeAll()
        suggestionsCache.removeAll()
        autoCompleteCache.removeAll()
        typoCorrectionCache.removeAll()
        learningDataCache.removeAll()
        
        hitCounts.removeAll()
        missCounts.removeAll()
        evictionCounts.removeAll()
    }
    
    /// Включает/выключает кэширование
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            clearAll()
        }
    }
    
    /// Получает статистику кэша
    func getStatistics() -> [String: Any] {
        let totalHits = hitCounts.values.reduce(0, +)
        let totalMisses = missCounts.values.reduce(0, +)
        let totalRequests = totalHits + totalMisses
        let hitRate = totalRequests > 0 ? Double(totalHits) / Double(totalRequests) : 0
        
        return [
            "enabled": isEnabled,
            "totalHits": totalHits,
            "totalMisses": totalMisses,
            "hitRate": hitRate,
            "cacheSizes": [
                "languageDetection": languageDetectionCache.count,
                "spellingCheck": spellingCheckCache.count,
                "suggestions": suggestionsCache.count,
                "autoComplete": autoCompleteCache.count,
                "typoCorrection": typoCorrectionCache.count,
                "learningData": learningDataCache.count
            ],
            "evictionCounts": evictionCounts,
            "lastCleanupTime": lastCleanupTime
        ]
    }
    
    // MARK: - Private Methods
    
    private func getCache(for type: CacheType) -> Any {
        switch type {
        case .languageDetection:
            return languageDetectionCache
        case .spellingCheck:
            return spellingCheckCache
        case .suggestions:
            return suggestionsCache
        case .autoComplete:
            return autoCompleteCache
        case .typoCorrection:
            return typoCorrectionCache
        case .learningData:
            // Learning data cache is handled separately in extension
            return [:] as [String: Any]
        }
    }
    
    private func setCache(_ cache: Any?, for type: CacheType) {
        switch type {
        case .languageDetection:
            languageDetectionCache = cache as? [String: CacheEntry<(Language, Double)>] ?? [:]
        case .spellingCheck:
            spellingCheckCache = cache as? [String: CacheEntry<Bool>] ?? [:]
        case .suggestions:
            suggestionsCache = cache as? [String: CacheEntry<[String]>] ?? [:]
        case .autoComplete:
            autoCompleteCache = cache as? [String: CacheEntry<[String]>] ?? [:]
        case .typoCorrection:
            typoCorrectionCache = cache as? [String: CacheEntry<String>] ?? [:]
        case .learningData:
            // Learning data cache is handled separately in extension
            break
        }
    }
    
    private func recordHit(type: CacheType) {
        hitCounts[type, default: 0] += 1
    }
    
    private func recordMiss(type: CacheType) {
        missCounts[type, default: 0] += 1
    }
    
    private func recordEviction(type: CacheType) {
        evictionCounts[type, default: 0] += 1
    }
    
    private func evictOldEntries(for type: CacheType) {
        var cache = getCache(for: type) as? [String: Any]
        let maxSize = type.maxSize
        
        if let count = cache?.count, count > maxSize {
            // Удаляем самые старые записи
            // В реальной реализации нужно отслеживать время доступа
            let entriesToRemove = count - maxSize
            if entriesToRemove > 0, let cacheDict = cache {
                let keys = Array(cacheDict.keys)
                let keysToRemove = Array(keys.prefix(entriesToRemove))
                
                var newCacheDict = cacheDict
                for key in keysToRemove {
                    newCacheDict.removeValue(forKey: key)
                }
                cache = newCacheDict
            }
            
            setCache(cache, for: type)
            recordEviction(type: type)
        }
    }
    
    private func startCleanupTimer() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                sleep(UInt32(self?.cleanupInterval ?? 300))
                self?.cleanupExpiredEntries()
            }
        }
    }
    
    private func cleanupExpiredEntries() {
        lastCleanupTime = Date()
        
        let now = Date()
        languageDetectionCache = languageDetectionCache.filter { now.timeIntervalSince($0.value.timestamp) <= CacheType.languageDetection.ttl }
        spellingCheckCache = spellingCheckCache.filter { now.timeIntervalSince($0.value.timestamp) <= CacheType.spellingCheck.ttl }
        suggestionsCache = suggestionsCache.filter { now.timeIntervalSince($0.value.timestamp) <= CacheType.suggestions.ttl }
        autoCompleteCache = autoCompleteCache.filter { now.timeIntervalSince($0.value.timestamp) <= CacheType.autoComplete.ttl }
        typoCorrectionCache = typoCorrectionCache.filter { now.timeIntervalSince($0.value.timestamp) <= CacheType.typoCorrection.ttl }
        
        logDebug("Cache cleanup completed at \(lastCleanupTime)")
    }
}

/// Упрощенный API для кэширования
extension CacheManager {
    
    /// Кэширует результат детекции языка
    func cacheLanguageDetection(key: String, language: Language, confidence: Double) {
        set(key: key, value: (language, confidence), type: .languageDetection)
    }
    
    /// Получает кэшированный результат детекции языка
    func getCachedLanguageDetection(key: String) -> (Language, Double)? {
        return get(key: key, type: .languageDetection)
    }
    
    /// Кэширует результат проверки орфографии
    func cacheSpellingCheck(key: String, isValid: Bool) {
        set(key: key, value: isValid, type: .spellingCheck)
    }
    
    /// Получает кэшированный результат проверки орфографии
    func getCachedSpellingCheck(key: String) -> Bool? {
        return get(key: key, type: .spellingCheck)
    }
    
    /// Кэширует исправление опечатки
    func cacheTypoCorrection(key: String, correction: String) {
        set(key: key, value: correction, type: .typoCorrection)
    }
    
    /// Получает кэшированное исправление опечатки
    func getCachedTypoCorrection(key: String) -> String? {
        return get(key: key, type: .typoCorrection)
    }
    
    // MARK: - Learning Data Cache
    
    /// Кэширует данные обучения
    func cacheLearningData(key: String, data: Data) -> Bool {
        cacheQueue.sync {
            learningDataCache[key] = CacheEntry(value: data)
            cleanupLearningDataIfNeeded()
        }
        return true
    }
    
    /// Получает кэшированные данные обучения
    func getCachedLearningData(key: String) -> Data? {
        return cacheQueue.sync {
            guard let entry = learningDataCache[key] else {
                return nil
            }
            
            // Проверяем TTL
            if Date().timeIntervalSince(entry.timestamp) > CacheType.learningData.ttl {
                learningDataCache.removeValue(forKey: key)
                return nil
            }
            
            return entry.value
        }
    }
    
    private func cleanupLearningDataIfNeeded() {
        let maxSize = CacheType.learningData.maxSize
        if learningDataCache.count > maxSize {
            // Удаляем самые старые записи
            let sortedKeys = learningDataCache.keys.sorted { key1, key2 in
                guard let entry1 = learningDataCache[key1], let entry2 = learningDataCache[key2] else {
                    return false
                }
                return entry1.timestamp < entry2.timestamp
            }
            
            let keysToRemove = sortedKeys.prefix(learningDataCache.count - maxSize)
            for key in keysToRemove {
                learningDataCache.removeValue(forKey: key)
            }
        }
    }
}
