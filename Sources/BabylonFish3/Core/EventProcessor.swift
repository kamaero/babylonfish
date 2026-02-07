import Cocoa
import Carbon

/// Главный процессор событий клавиатуры
class EventProcessor {
    
    // Зависимости
    private let bufferManager: BufferManager
    private let contextAnalyzer: ContextAnalyzer
    private let layoutSwitcher: LayoutSwitcher
    private let neuralLanguageClassifier: NeuralLanguageClassifier
    private let typoCorrector: TypoCorrector
    private let autoCompleteEngine: AutoCompleteEngine
    private let learningManager: LearningManager
    
    // Конфигурация
    private var isEnabled = true
    private var config: ProcessingConfig
    
    // Состояние
    private var currentContext: ProcessingContext
    private var lastProcessedEvent: KeyboardEvent?
    private var pendingCorrections: [PendingCorrection] = []
    
    // Статистика
    private var totalEventsProcessed: Int = 0
    private var languageDetections: Int = 0
    private var layoutSwitches: Int = 0
    private var correctionsMade: Int = 0
    private var startTime: Date?
    
    /// Инициализирует процессор событий
    init(
        bufferManager: BufferManager,
        contextAnalyzer: ContextAnalyzer,
        layoutSwitcher: LayoutSwitcher,
        neuralLanguageClassifier: NeuralLanguageClassifier,
        typoCorrector: TypoCorrector,
        autoCompleteEngine: AutoCompleteEngine,
        learningManager: LearningManager,
        config: ProcessingConfig = .default
    ) {
        self.bufferManager = bufferManager
        self.contextAnalyzer = contextAnalyzer
        self.layoutSwitcher = layoutSwitcher
        self.neuralLanguageClassifier = neuralLanguageClassifier
        self.typoCorrector = typoCorrector
        self.autoCompleteEngine = autoCompleteEngine
        self.learningManager = learningManager
        self.config = config
        self.currentContext = ProcessingContext()
        
        logDebug("EventProcessor initialized")
    }
    
    // MARK: - Public API
    
    /// Обрабатывает событие клавиатуры
    func processEvent(_ event: KeyboardEvent) -> EventProcessingResult {
        guard isEnabled else {
            return .default
        }
        
        totalEventsProcessed += 1
        lastProcessedEvent = event
        
        // 1. Обновляем контекст
        updateContext(with: event)
        
        // 2. Проверяем, нужно ли игнорировать событие
        if shouldIgnoreEvent(event) {
            logDebug("Ignoring event: \(event)")
            return .default
        }
        
        // 3. Добавляем символ в буфер
        bufferManager.addCharacter(event.unicodeString)
        
        // 4. Проверяем границы слов
        if bufferManager.shouldProcessWord() {
            return processWord()
        }
        
        // 5. Проверяем специальные комбинации клавиш
        if let specialResult = handleSpecialKeyCombinations(event) {
            return specialResult
        }
        
        return .default
    }
    
    /// Настраивает процессор
    func configure(_ config: ProcessingConfig) {
        self.config = config
        logDebug("EventProcessor configured: \(config)")
    }
    
    /// Включает/выключает обработку
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        logDebug("EventProcessor enabled: \(enabled)")
    }
    
    /// Получает статистику
    func getStatistics() -> [String: Any] {
        let uptime = startTime.map { Date().timeIntervalSince($0) } ?? 0
        
        return [
            "isEnabled": isEnabled,
            "totalEventsProcessed": totalEventsProcessed,
            "languageDetections": languageDetections,
            "layoutSwitches": layoutSwitches,
            "correctionsMade": correctionsMade,
            "uptime": uptime,
            "bufferState": bufferManager.getState(),
            "currentContext": currentContext.description,
            "config": config.description
        ]
    }
    
    /// Сбрасывает состояние процессора
    func reset() {
        bufferManager.clear()
        pendingCorrections.removeAll()
        currentContext = ProcessingContext()
        
        logDebug("EventProcessor reset")
    }
    
    // MARK: - Private Methods
    
    private func updateContext(with event: KeyboardEvent) {
        // Обновляем контекст на основе события
        currentContext.lastEventTime = Date()
        currentContext.lastKeyCode = event.keyCode
        
        // Определяем активное приложение
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            currentContext.activeApplication = frontmostApp
            currentContext.bundleIdentifier = frontmostApp.bundleIdentifier
            currentContext.processName = frontmostApp.localizedName
        }
        
        // Определяем тип приложения
        currentContext.applicationType = determineApplicationType()
    }
    
    private func shouldIgnoreEvent(_ event: KeyboardEvent) -> Bool {
        // 1. Проверяем контекст
        let detectionContext = DetectionContext(
            applicationType: currentContext.applicationType,
            isSecureField: false,
            previousWords: [],
            userPreferences: nil
        )
        
        let shouldIgnore = contextAnalyzer.shouldIgnoreInput(
            text: event.unicodeString,
            externalContext: detectionContext
        )
        
        if shouldIgnore {
            logDebug("Context check: ignoring event")
            return true
        }
        
        // 2. Проверяем модификаторы
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            // Игнорируем события с Command/Ctrl
            return true
        }
        
        // 3. Проверяем специальные клавиши
        if isSpecialKey(event.keyCode) {
            return true
        }
        
        return false
    }
    
    private func processWord() -> EventProcessingResult {
        guard let word = bufferManager.getCurrentWord() else {
            return .default
        }
        
        logDebug("Processing word: '\(word)'")
        
        // 1. Анализируем контекст
        let detectionContext = DetectionContext(
            applicationType: currentContext.applicationType,
            isSecureField: false,
            previousWords: bufferManager.getPreviousWords(),
            userPreferences: nil
        )
        
        let contextAnalysis = contextAnalyzer.analyzeContext(
            for: word,
            externalContext: detectionContext
        )
        
        logDebug("Context analysis: \(contextAnalysis.description)")
        
        if contextAnalysis.shouldIgnore {
            bufferManager.clearWord()
            return .default
        }
        
        // 2. Детектируем язык
        let languageResult = neuralLanguageClassifier.classifyLanguage(
            word,
            context: ClassificationContext(
                applicationType: currentContext.applicationType,
                previousLanguage: currentContext.lastDetectedLanguage
            )
        )
        
        logDebug("Classifier analysis: \(languageResult.description)")
        
        var selectedLanguage: Language?
        var selectedConfidence: Double = 0
        
        if contextAnalysis.isConfident, let ctxLang = contextAnalysis.suggestedLanguage {
            selectedLanguage = ctxLang
            selectedConfidence = contextAnalysis.confidence
            logDebug("Language decision: using context (\(selectedLanguage!), \(String(format: "%.2f", selectedConfidence)))")
        } else if let clsLang = languageResult.language {
            selectedLanguage = clsLang
            selectedConfidence = languageResult.confidence
            logDebug("Language decision: using classifier (\(selectedLanguage!), \(String(format: "%.2f", selectedConfidence)))")
        }
        
        if let detectedLanguage = selectedLanguage {
            languageDetections += 1
            currentContext.lastDetectedLanguage = detectedLanguage
            
            logDebug("Language detected: \(detectedLanguage) with confidence \(selectedConfidence)")
            
            // 3. Проверяем, нужно ли переключить раскладку
            if shouldSwitchLayout(for: word, detectedLanguage: detectedLanguage) {
                return handleLayoutSwitch(word: word, targetLanguage: detectedLanguage)
            }
        }
        
        // 4. Проверяем опечатки
        if config.enableTypoCorrection {
            let correctionResult = typoCorrector.correctTypos(
                in: word,
                language: currentContext.lastDetectedLanguage,
                context: CorrectionContext(
                    preferredLanguage: currentContext.lastDetectedLanguage,
                    applicationType: currentContext.applicationType
                )
            )
            
        if !correctionResult.corrections.isEmpty {
            return handleTypoCorrection(word: word, correctionResult: correctionResult)
        }
        }
        
        // 5. Очищаем буфер
        bufferManager.clearWord()
        
        return .default
    }
    
    private func shouldSwitchLayout(for word: String, detectedLanguage: Language) -> Bool {
        // 1. Проверяем минимальную длину
        guard word.count >= config.minWordLengthForSwitch else {
            return false
        }
        
        // 2. Проверяем исключения
        if config.wordExceptions.contains(word.lowercased()) {
            return false
        }
        
        // 3. Получаем текущую раскладку
        guard let currentLayout = layoutSwitcher.getCurrentLayout() else {
            return false
        }
        
        // 4. Определяем язык текущей раскладки
        let currentLayoutLanguage = layoutSwitcher.getLanguageForLayout(currentLayout)
        
        // 5. Сравниваем языки
        return currentLayoutLanguage != detectedLanguage
    }
    
    private func handleLayoutSwitch(word: String, targetLanguage: Language) -> EventProcessingResult {
        logDebug("Switching layout for word '\(word)' to \(targetLanguage)")
        
        // 1. Получаем целевую раскладку
        guard let targetLayout = layoutSwitcher.getLayoutForLanguage(targetLanguage) else {
            logDebug("No layout found for language: \(targetLanguage)")
            return .default
        }
        
        // 2. Переключаем раскладку
        let switchSuccess = layoutSwitcher.switchToLayout(targetLayout)
        
        if switchSuccess {
            layoutSwitches += 1
            
            // 3. Перепечатываем слово
            let eventsToSend = layoutSwitcher.getKeyEventsForWord(word, inLanguage: targetLanguage)
            
            // 4. Обучаем модель
            let learningContext = LearningContext(
                applicationBundleId: currentContext.bundleIdentifier,
                applicationType: currentContext.applicationType,
                textContext: word
            )
            
            learningManager.learn(from: LearningEvent(
                type: .languageSelection,
                language: targetLanguage,
                originalText: word,
                applicationType: currentContext.applicationType,
                context: learningContext
            ))
            
            // 5. Очищаем буфер
            bufferManager.clearWord()
            
            logDebug("Layout switched successfully to \(targetLanguage)")
            return EventProcessingResult(
                shouldBlockOriginalEvent: true,
                eventsToSend: eventsToSend
            )
        }
        
        return .default
    }
    
    private func handleTypoCorrection(word: String, correctionResult: CorrectionResult) -> EventProcessingResult {
        logDebug("Correcting typo: '\(word)' → '\(correctionResult.correctedText)'")
        logDebug("Typo analysis: \(correctionResult.description) applied=\(correctionResult.applied) conf=\(String(format: "%.2f", correctionResult.confidence))")
        
        correctionsMade += 1
        
        // 1. Удаляем неправильное слово
        let backspaceEvents = createBackspaceEvents(count: word.count)
        
        // 2. Печатаем исправленное слово
        let correctionEvents = layoutSwitcher.getKeyEventsForWord(
            correctionResult.correctedText,
            inLanguage: currentContext.lastDetectedLanguage ?? .english
        )
        
        // 3. Обучаем модель
        let learningContext = LearningContext(
            applicationBundleId: currentContext.bundleIdentifier,
            applicationType: currentContext.applicationType,
            textContext: "\(word) → \(correctionResult.correctedText)"
        )
        
            learningManager.learn(from: LearningEvent(
                type: .correctionAcceptance,
                language: currentContext.lastDetectedLanguage,
                originalText: word,
                correctedText: correctionResult.correctedText,
                applicationBundleId: currentContext.bundleIdentifier,
                applicationType: currentContext.applicationType,
                context: learningContext
            ))
        
        // 4. Очищаем буфер
        bufferManager.clearWord()
        
        logDebug("Typo corrected: \(word) → \(correctionResult.correctedText)")
        return EventProcessingResult(
            shouldBlockOriginalEvent: true,
            eventsToSend: backspaceEvents + correctionEvents
        )
    }
    
    private func handleSpecialKeyCombinations(_ event: KeyboardEvent) -> EventProcessingResult? {
        // Обработка Double Shift для ручного исправления
        if config.enableDoubleShift && isDoubleShift(event) {
            return handleDoubleShift()
        }
        
        // Обработка других специальных комбинаций
        // ...
        
        return nil
    }
    
    private func isDoubleShift(_ event: KeyboardEvent) -> Bool {
        // Упрощенная проверка Double Shift
        // В реальной реализации нужно отслеживать время между нажатиями
        guard event.keyCode == 56 || event.keyCode == 60 else { // Left/Right Shift
            return false
        }
        
        // Проверяем флаги
        let flags = event.flags
        return flags.contains(.maskShift)
    }
    
    private func handleDoubleShift() -> EventProcessingResult {
        logDebug("Double Shift detected - manual correction requested")
        
        guard let selectedText = getSelectedText() else {
            logDebug("No text selected")
            return .default
        }
        
        // Анализируем выбранный текст
        let detectionContext = DetectionContext(
            applicationType: currentContext.applicationType,
            isSecureField: false,
            previousWords: bufferManager.getPreviousWords(),
            userPreferences: nil
        )
        
        let contextAnalysis = contextAnalyzer.analyzeContext(
            for: selectedText,
            externalContext: detectionContext
        )
        logDebug("Double Shift context: \(contextAnalysis.description)")
        
        let languageResult = neuralLanguageClassifier.classifyLanguage(selectedText)
        logDebug("Double Shift classifier: \(languageResult.description)")
        
        var selectedLanguage: Language?
        var selectedConfidence: Double = 0
        
        if contextAnalysis.isConfident, let ctxLang = contextAnalysis.suggestedLanguage {
            selectedLanguage = ctxLang
            selectedConfidence = contextAnalysis.confidence
            logDebug("Double Shift decision: using context (\(selectedLanguage!), \(String(format: "%.2f", selectedConfidence)))")
        } else if let clsLang = languageResult.language {
            selectedLanguage = clsLang
            selectedConfidence = languageResult.confidence
            logDebug("Double Shift decision: using classifier (\(selectedLanguage!), \(String(format: "%.2f", selectedConfidence)))")
        }
        
        if let detectedLanguage = selectedLanguage, selectedConfidence >= config.confidenceThreshold {
            // Предлагаем переключить раскладку для выбранного текста
            logDebug("Selected text '\(selectedText)' detected as \(detectedLanguage) (conf=\(String(format: "%.2f", selectedConfidence)))")
            
            // Обучаем модель на ручном выборе
            let learningContext = LearningContext(
                applicationBundleId: currentContext.bundleIdentifier,
                applicationType: currentContext.applicationType,
                textContext: selectedText,
                selectedText: selectedText
            )
            
            learningManager.learn(from: LearningEvent(
                type: .languageSelection,
                language: detectedLanguage,
                originalText: selectedText,
                applicationBundleId: currentContext.bundleIdentifier,
                applicationType: currentContext.applicationType,
                context: learningContext
            ))
        }
        
        return .default
    }
    
    private func getSelectedText() -> String? {
        // Получаем выделенный текст из активного приложения
        // Упрощенная реализация
        return nil
    }
    
    private func createBackspaceEvents(count: Int) -> [KeyboardEvent] {
        var events: [KeyboardEvent] = []
        
        for _ in 0..<count {
            let backspaceEvent = KeyboardEvent(
                keyCode: 51, // Backspace key code
                unicodeString: "",
                flags: [],
                timestamp: CGEventTimestamp(Date().timeIntervalSince1970 * 1_000_000),
                eventType: .keyDown
            )
            events.append(backspaceEvent)
        }
        
        return events
    }
    
    private func determineApplicationType() -> ApplicationType {
        guard let bundleId = currentContext.bundleIdentifier else {
            return .other
        }
        
        // Определяем тип приложения по bundle identifier
        if bundleId.contains("com.apple.Terminal") || bundleId.contains("com.googlecode.iterm2") {
            return .terminal
        } else if bundleId.contains("com.apple.dt.Xcode") || bundleId.contains("com.jetbrains") {
            return .ide
        } else if bundleId.contains("com.apple.Safari") || bundleId.contains("com.google.Chrome") {
            return .browser
        } else if bundleId.contains("com.apple.TextEdit") || bundleId.contains("com.microsoft.Word") {
            return .textEditor
        } else if bundleId.contains("com.valvesoftware.steam") || bundleId.contains("com.blizzard") {
            return .game
        }
        
        return .other
    }
    
    private func isSpecialKey(_ keyCode: Int) -> Bool {
        // Специальные клавиши, которые нужно игнорировать
        let specialKeys: Set<Int> = [
            53, // Escape
            48, // Tab
            // 49, // Space - используем как границу слова
            // 36, // Return - используем как границу слова
            51, // Delete
            117, // Forward Delete
            115, // Home
            119, // End
            116, // Page Up
            121, // Page Down
            123, // Left Arrow
            124, // Right Arrow
            125, // Down Arrow
            126  // Up Arrow
        ]
        
        return specialKeys.contains(keyCode)
    }
}

// MARK: - Вспомогательные структуры

/// Конфигурация обработки событий
struct ProcessingConfig {
    let enableTypoCorrection: Bool
    let enableAutoComplete: Bool
    let enableDoubleShift: Bool
    let minWordLengthForSwitch: Int
    let wordExceptions: Set<String>
    let confidenceThreshold: Double
    
    static let `default` = ProcessingConfig(
        enableTypoCorrection: true,
        enableAutoComplete: true,
        enableDoubleShift: true,
        minWordLengthForSwitch: 3,
        wordExceptions: ["a", "i", "to", "in", "on", "at"],
        confidenceThreshold: 0.7
    )
    
    var description: String {
        return """
        ProcessingConfig(
          enableTypoCorrection: \(enableTypoCorrection),
          enableAutoComplete: \(enableAutoComplete),
          enableDoubleShift: \(enableDoubleShift),
          minWordLengthForSwitch: \(minWordLengthForSwitch),
          wordExceptions: \(wordExceptions.count) words,
          confidenceThreshold: \(confidenceThreshold)
        )
        """
    }
}

/// Контекст обработки
struct ProcessingContext {
    var activeApplication: NSRunningApplication?
    var bundleIdentifier: String?
    var processName: String?
    var applicationType: ApplicationType = .other
    var lastDetectedLanguage: Language?
    var lastEventTime: Date = Date()
    var lastKeyCode: Int = 0
    
    var description: String {
        return """
        ProcessingContext(
          app: \(processName ?? "unknown"),
          bundleId: \(bundleIdentifier ?? "unknown"),
          type: \(applicationType),
          lastLanguage: \(String(describing: lastDetectedLanguage)),
          lastEvent: \(lastEventTime.timeIntervalSinceNow * -1)s ago
        )
        """
    }
}

/// Ожидающая коррекция
struct PendingCorrection {
    let originalWord: String
    let correctedWord: String
    let confidence: Double
    let timestamp: Date
}
