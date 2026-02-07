import Foundation

/// Менеджер асинхронных операций для BabylonFish
class AsyncProcessor {
    /// Приоритет очереди для асинхронных операций
    enum QueuePriority: String, Codable {
        case high
        case normal
        case low
        
        var dispatchQoS: DispatchQoS {
            switch self {
            case .high:
                return .userInteractive
            case .normal:
                return .userInitiated
            case .low:
                return .utility
            }
        }
    }
    
    static let shared = AsyncProcessor()

/// Результат асинхронной операции
struct AsyncResult<T> {
    let value: T?
    let error: Error?
    let processingTime: TimeInterval
    
    var isSuccess: Bool { value != nil }
    var isFailure: Bool { error != nil }
}
    
    // Очереди с разными приоритетами
    private let highPriorityQueue: DispatchQueue
    private let normalPriorityQueue: DispatchQueue
    private let lowPriorityQueue: DispatchQueue
    
    // Ограничители для предотвращения перегрузки
    private let highPrioritySemaphore: DispatchSemaphore
    private let normalPrioritySemaphore: DispatchSemaphore
    private let lowPrioritySemaphore: DispatchSemaphore
    
    // Статистика
    private var operationCounts: [QueuePriority: Int] = [:]
    private var totalProcessingTime: TimeInterval = 0
    private var startTimes: [String: Date] = [:]
    
    // Конфигурация
    private var maxConcurrentHighPriority: Int = 2
    private var maxConcurrentNormalPriority: Int = 4
    private var maxConcurrentLowPriority: Int = 8
    
    private init() {
        // Создаем очереди с соответствующими QoS
        highPriorityQueue = DispatchQueue(
            label: "com.babylonfish.async.high",
            qos: .userInteractive,
            attributes: .concurrent
        )
        
        normalPriorityQueue = DispatchQueue(
            label: "com.babylonfish.async.normal",
            qos: .userInitiated,
            attributes: .concurrent
        )
        
        lowPriorityQueue = DispatchQueue(
            label: "com.babylonfish.async.low",
            qos: .utility,
            attributes: .concurrent
        )
        
        // Инициализируем семафоры для ограничения параллелизма
        highPrioritySemaphore = DispatchSemaphore(value: maxConcurrentHighPriority)
        normalPrioritySemaphore = DispatchSemaphore(value: maxConcurrentNormalPriority)
        lowPrioritySemaphore = DispatchSemaphore(value: maxConcurrentLowPriority)
    }
    
    /// Выполняет операцию с указанным приоритетом
    func execute<T>(
        priority: QueuePriority = .normal,
        operationId: String = UUID().uuidString,
        operation: @escaping () throws -> T,
        completion: @escaping (AsyncResult<T>) -> Void
    ) {
        let startTime = Date()
        startTimes[operationId] = startTime
        
        let task = {
            do {
                // Ожидаем семафор для ограничения параллелизма
                self.waitForSemaphore(priority: priority)
                
                // Выполняем операцию
                let result = try operation()
                let processingTime = Date().timeIntervalSince(startTime)
                
                // Освобождаем семафор
                self.signalSemaphore(priority: priority)
                
                // Обновляем статистику
                self.updateStatistics(priority: priority, processingTime: processingTime)
                
                // Возвращаем результат
                DispatchQueue.main.async {
                    completion(AsyncResult(
                        value: result,
                        error: nil,
                        processingTime: processingTime
                    ))
                }
            } catch {
                let processingTime = Date().timeIntervalSince(startTime)
                
                // Освобождаем семафор в случае ошибки
                self.signalSemaphore(priority: priority)
                
                DispatchQueue.main.async {
                    completion(AsyncResult(
                        value: nil,
                        error: error,
                        processingTime: processingTime
                    ))
                }
            }
        }
        
        // Выбираем очередь в зависимости от приоритета
        switch priority {
        case .high:
            highPriorityQueue.async(execute: task)
        case .normal:
            normalPriorityQueue.async(execute: task)
        case .low:
            lowPriorityQueue.async(execute: task)
        }
    }
    
    /// Выполняет операцию синхронно (для критических операций)
    func executeSync<T>(operation: () throws -> T) throws -> T {
        return try operation()
    }
    
    /// Ожидает завершения всех операций (для тестирования)
    func waitForAllOperations(timeout: TimeInterval = 5.0) -> Bool {
        let group = DispatchGroup()
        
        // Добавляем все очереди в группу
        highPriorityQueue.async(group: group) {}
        normalPriorityQueue.async(group: group) {}
        lowPriorityQueue.async(group: group) {}
        
        return group.wait(timeout: .now() + timeout) == .success
    }
    
    /// Получает статистику выполнения операций
    func getStatistics() -> [String: Any] {
        return [
            "operationCounts": operationCounts,
            "totalProcessingTime": totalProcessingTime,
            "activeOperations": startTimes.count,
            "maxConcurrentHighPriority": maxConcurrentHighPriority,
            "maxConcurrentNormalPriority": maxConcurrentNormalPriority,
            "maxConcurrentLowPriority": maxConcurrentLowPriority
        ]
    }
    
    /// Очищает статистику
    func clearStatistics() {
        operationCounts = [:]
        totalProcessingTime = 0
        startTimes.removeAll()
    }
    
    /// Настраивает ограничения параллелизма
    func configureConcurrencyLimits(
        high: Int = 2,
        normal: Int = 4,
        low: Int = 8
    ) {
        maxConcurrentHighPriority = max(1, high)
        maxConcurrentNormalPriority = max(1, normal)
        maxConcurrentLowPriority = max(1, low)
        
        // Обновляем семафоры (создаем новые с новыми значениями)
        // В реальном приложении нужно быть осторожнее с изменением семафоров
        // во время выполнения операций
    }
    
    // MARK: - Private Methods
    
    private func waitForSemaphore(priority: QueuePriority) {
        switch priority {
        case .high:
            highPrioritySemaphore.wait()
        case .normal:
            normalPrioritySemaphore.wait()
        case .low:
            lowPrioritySemaphore.wait()
        }
    }
    
    private func signalSemaphore(priority: QueuePriority) {
        switch priority {
        case .high:
            highPrioritySemaphore.signal()
        case .normal:
            normalPrioritySemaphore.signal()
        case .low:
            lowPrioritySemaphore.signal()
        }
    }
    
    private func updateStatistics(priority: QueuePriority, processingTime: TimeInterval) {
        operationCounts[priority, default: 0] += 1
        totalProcessingTime += processingTime
    }
}

/// Упрощенный API для асинхронных операций
extension AsyncProcessor {
    
    /// Асинхронная детекция языка
    func detectLanguageAsync(
        keyCodes: [Int],
        completion: @escaping (AsyncResult<Language>) -> Void
    ) {
        execute(priority: .normal, operationId: "language_detection") {
            // Здесь будет вызов LanguageDetector
            // Пока возвращаем заглушку
            throw NSError(domain: "NotImplemented", code: 0, userInfo: nil)
        } completion: { result in
            completion(result)
        }
    }
    
    /// Асинхронная проверка орфографии
    func checkSpellingAsync(
        word: String,
        language: String,
        completion: @escaping (AsyncResult<Bool>) -> Void
    ) {
        execute(priority: .low, operationId: "spell_check") {
            // Здесь будет вызов SystemDictionaryService
            // Пока возвращаем заглушку
            throw NSError(domain: "NotImplemented", code: 0, userInfo: nil)
        } completion: { result in
            completion(result)
        }
    }
    
    /// Асинхронное получение предложений
    func getSuggestionsAsync(
        partialWord: String,
        language: String,
        completion: @escaping (AsyncResult<[String]>) -> Void
    ) {
        execute(priority: .low, operationId: "suggestions") {
            // Здесь будет вызов AutoCompleteEngine
            // Пока возвращаем заглушку
            throw NSError(domain: "NotImplemented", code: 0, userInfo: nil)
        } completion: { result in
            completion(result)
        }
    }
}