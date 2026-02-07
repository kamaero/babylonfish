import Foundation

/// Метрики производительности
struct PerformanceMetrics {
    // Время обработки
    var eventProcessingTime: TimeInterval = 0
    var languageDetectionTime: TimeInterval = 0
    var layoutSwitchTime: TimeInterval = 0
    var typoCorrectionTime: TimeInterval = 0
    var autoCompleteTime: TimeInterval = 0
    
    // Статистика операций
    var totalEventsProcessed: Int = 0
    var languageDetections: Int = 0
    var layoutSwitches: Int = 0
    var typoCorrections: Int = 0
    var autoCompletions: Int = 0
    
    // Кэш статистика
    var cacheHits: Int = 0
    var cacheMisses: Int = 0
    var cacheHitRate: Double {
        let total = cacheHits + cacheMisses
        return total > 0 ? Double(cacheHits) / Double(total) : 0
    }
    
    // Ошибки
    var errors: [String: Int] = [:]
    
    // Использование памяти (в байтах)
    var memoryUsage: UInt64 = 0
    
    // Время работы
    var uptime: TimeInterval = 0
    
    /// Сбрасывает метрики
    mutating func reset() {
        eventProcessingTime = 0
        languageDetectionTime = 0
        layoutSwitchTime = 0
        typoCorrectionTime = 0
        autoCompleteTime = 0
        
        totalEventsProcessed = 0
        languageDetections = 0
        layoutSwitches = 0
        typoCorrections = 0
        autoCompletions = 0
        
        cacheHits = 0
        cacheMisses = 0
        errors.removeAll()
    }
    
    /// Возвращает метрики в виде словаря
    func toDictionary() -> [String: Any] {
        return [
            "eventProcessingTime": eventProcessingTime,
            "languageDetectionTime": languageDetectionTime,
            "layoutSwitchTime": layoutSwitchTime,
            "typoCorrectionTime": typoCorrectionTime,
            "autoCompleteTime": autoCompleteTime,
            
            "totalEventsProcessed": totalEventsProcessed,
            "languageDetections": languageDetections,
            "layoutSwitches": layoutSwitches,
            "typoCorrections": typoCorrections,
            "autoCompletions": autoCompletions,
            
            "cacheHits": cacheHits,
            "cacheMisses": cacheMisses,
            "cacheHitRate": cacheHitRate,
            
            "errors": errors,
            "memoryUsage": memoryUsage,
            "uptime": uptime
        ]
    }
}

/// Монитор производительности для BabylonFish
class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private var metrics = PerformanceMetrics()
    private var startTimes: [String: Date] = [:]
    private var startTime: Date = Date()
    
    // Конфигурация
    private var isEnabled = false
    private var samplingInterval: TimeInterval = 60 // 1 минута
    private var lastSampleTime: Date = Date()
    
    // Обработчики событий
    var onMetricsUpdated: ((PerformanceMetrics) -> Void)?
    
    private init() {
        // Запускаем периодический сбор метрик
        startSamplingTimer()
    }
    
    // MARK: - Public API
    
    /// Включает/выключает мониторинг
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            startTime = Date()
            metrics.reset()
        }
    }
    
    /// Начинает измерение операции
    func startMeasurement(_ operation: String) {
        guard isEnabled else { return }
        startTimes[operation] = Date()
    }
    
    /// Заканчивает измерение операции
    @discardableResult
    func endMeasurement(_ operation: String) -> TimeInterval {
        guard isEnabled, let start = startTimes[operation] else { return 0 }
        
        let duration = Date().timeIntervalSince(start)
        
        // Обновляем метрики в зависимости от типа операции
        switch operation {
        case "eventProcessing":
            metrics.eventProcessingTime = duration
            metrics.totalEventsProcessed += 1
            
        case "languageDetection":
            metrics.languageDetectionTime = duration
            metrics.languageDetections += 1
            
        case "layoutSwitch":
            metrics.layoutSwitchTime = duration
            metrics.layoutSwitches += 1
            
        case "typoCorrection":
            metrics.typoCorrectionTime = duration
            metrics.typoCorrections += 1
            
        case "autoComplete":
            metrics.autoCompleteTime = duration
            metrics.autoCompletions += 1
            
        default:
            break
        }
        
        startTimes.removeValue(forKey: operation)
        return duration
    }
    
    /// Регистрирует попадание в кэш
    func recordCacheHit() {
        guard isEnabled else { return }
        metrics.cacheHits += 1
    }
    
    /// Регистрирует промах кэша
    func recordCacheMiss() {
        guard isEnabled else { return }
        metrics.cacheMisses += 1
    }
    
    /// Регистрирует ошибку
    func recordError(_ error: String) {
        guard isEnabled else { return }
        metrics.errors[error, default: 0] += 1
    }
    
    /// Получает текущие метрики
    func getMetrics() -> PerformanceMetrics {
        var currentMetrics = metrics
        currentMetrics.uptime = Date().timeIntervalSince(startTime)
        currentMetrics.memoryUsage = getMemoryUsage()
        return currentMetrics
    }
    
    /// Сбрасывает метрики
    func resetMetrics() {
        metrics.reset()
        startTime = Date()
        startTimes.removeAll()
    }
    
    /// Экспортирует метрики в файл
    func exportMetrics(to filePath: String) -> Bool {
        let metricsDict = getMetrics().toDictionary()
        
        do {
            let data = try JSONSerialization.data(withJSONObject: metricsDict, options: .prettyPrinted)
            try data.write(to: URL(fileURLWithPath: filePath))
            return true
        } catch {
            logDebug("Failed to export metrics: \(error)")
            return false
        }
    }
    
    /// Устанавливает интервал сбора метрик
    func setSamplingInterval(_ interval: TimeInterval) {
        samplingInterval = max(1, interval) // Минимум 1 секунда
    }
    
    // MARK: - Private Methods
    
    private func startSamplingTimer() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                sleep(UInt32(self?.samplingInterval ?? 60))
                self?.collectSample()
            }
        }
    }
    
    private func collectSample() {
        guard isEnabled else { return }
        
        // Обновляем время работы
        metrics.uptime = Date().timeIntervalSince(startTime)
        
        // Обновляем использование памяти
        metrics.memoryUsage = getMemoryUsage()
        
        // Уведомляем об обновлении метрик
        DispatchQueue.main.async {
            self.onMetricsUpdated?(self.getMetrics())
        }
        
        lastSampleTime = Date()
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.resident_size
        } else {
            return 0
        }
    }
}

/// Упрощенный API для мониторинга производительности
extension PerformanceMonitor {
    
    /// Измеряет выполнение блока кода
    func measure<T>(_ operation: String, block: () throws -> T) rethrows -> T {
        startMeasurement(operation)
        defer {
            endMeasurement(operation)
        }
        return try block()
    }
    
    /// Измеряет выполнение асинхронного блока кода
    func measureAsync<T>(
        _ operation: String,
        block: @escaping () async throws -> T,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        startMeasurement(operation)
        
        Task {
            do {
                let result = try await block()
                endMeasurement(operation)
                completion(.success(result))
            } catch {
                endMeasurement(operation)
                recordError("\(operation): \(error)")
                completion(.failure(error))
            }
        }
    }
    
    /// Логирует метрики производительности
    func logMetrics() {
        guard isEnabled else { return }
        
        let metrics = getMetrics()
        logDebug("""
        Performance Metrics:
        - Uptime: \(String(format: "%.1f", metrics.uptime))s
        - Events processed: \(metrics.totalEventsProcessed)
        - Language detections: \(metrics.languageDetections)
        - Layout switches: \(metrics.layoutSwitches)
        - Cache hit rate: \(String(format: "%.1f", metrics.cacheHitRate * 100))%
        - Memory usage: \(formatBytes(metrics.memoryUsage))
        """)
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
}