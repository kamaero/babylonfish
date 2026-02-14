import Cocoa
import Carbon
import ApplicationServices

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
    private var isProcessing = false
    private var recursionDepth = 0
    private let maxRecursionDepth = 3
    
    // Double Shift State
    private var lastShiftTime: TimeInterval = 0
    private let doubleShiftThreshold: TimeInterval = 0.3
    private var lastShiftKeyCode: Int = 0
    
    // Статистика
    private var totalEventsProcessed: Int = 0
    private var languageDetections: Int = 0
    private var layoutSwitches: Int = 0
    private var correctionsMade: Int = 0
    private var startTime: Date?
    
    // Обработка слов при нажатии Space/Return
    private var pendingSpaceWord: String?
    private var pendingSpaceRequiresProcessing: Bool = false
    
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
        
        // Защита от рекурсии
        if !isProcessing {
            // Внешний вызов
            isProcessing = true
            recursionDepth = 0
        } else {
            // Рекурсивный вызов
            recursionDepth += 1
            if recursionDepth > maxRecursionDepth {
                logDebug("⚠️ Recursion depth exceeded (\(recursionDepth)), skipping processing")
                recursionDepth -= 1  // Откатываем увеличение перед возвратом
                return .default
            }
            logDebug("⚠️ Recursive processing detected (depth: \(recursionDepth))")
        }
        
        defer {
            if recursionDepth > 0 {
                // Вложенный вызов завершается
                recursionDepth -= 1
            } else {
                // Внешний вызов завершается
                isProcessing = false
            }
        }
        
        totalEventsProcessed += 1
        lastProcessedEvent = event
        
        logDebug("Processing event: keyCode=\(event.keyCode), unicode='\(event.unicodeString)', flags=\(event.flags.rawValue)")
        
        // 1. Обновляем контекст
        updateContext(with: event)
        
        // Handle Backspace explicitly
        if event.keyCode == 51 { // Backspace
            bufferManager.removeLast()
            logDebug("Backspace pressed, buffer updated")
            return EventProcessingResult(
                shouldBlockOriginalEvent: false,
                eventsToSend: [],
                detectedLanguage: nil,
                shouldSwitchLayout: false
            )
        }
        
        // Handle Space and Return as word boundaries
        if event.keyCode == 49 || event.keyCode == 36 { // Space or Return
            logDebug("Word boundary detected (Space/Return), checking current word")
            
            // Если есть текущее слово, проверяем нужно ли его обработать
            if let currentWord = bufferManager.getCurrentWord(), !currentWord.isEmpty {
                logDebug("Current word before Space/Return: '\(currentWord)'")
                
                // Проверяем, является ли это английским словом в русской раскладке
                if isEnglishWordInRussianLayout(currentWord) {
                    logDebug("English word in Russian layout detected: '\(currentWord)'")
                    // Отмечаем, что нужно обработать это слово
                    // Но не обрабатываем сейчас, чтобы избежать рекурсии
                    pendingSpaceWord = currentWord
                    pendingSpaceRequiresProcessing = true
                } else {
                    // Для обычных слов проверяем уверенность
                    let languageResult = neuralLanguageClassifier.classifyLanguage(
                        currentWord,
                        context: ClassificationContext(
                            applicationType: currentContext.applicationType,
                            previousLanguage: currentContext.lastDetectedLanguage
                        )
                    )
                    
                    if let detectedLanguage = languageResult.language, languageResult.confidence >= 0.8 {
                        logDebug("High confidence (\(languageResult.confidence)) for language \(detectedLanguage)")
                        pendingSpaceWord = currentWord
                        pendingSpaceRequiresProcessing = true
                    } else {
                        logDebug("Word doesn't require processing")
                        pendingSpaceWord = nil
                        pendingSpaceRequiresProcessing = false
                    }
                }
            } else {
                logDebug("No current word")
                pendingSpaceWord = nil
                pendingSpaceRequiresProcessing = false
            }
            
            // Очищаем буфер для нового ввода
            bufferManager.clearForNewInput()
            logDebug("Buffer cleared for Space/Return")
            
            // Если слово требует обработки, планируем ее на следующий тик
            if pendingSpaceRequiresProcessing, let word = pendingSpaceWord {
                logDebug("Scheduling word processing for: '\(word)'")
                // Планируем обработку слова асинхронно
                DispatchQueue.main.async { [weak self] in
                    self?.processPendingWord(word)
                }
            }
            
            // Возвращаем результат без блокировки оригинального события
            return EventProcessingResult(
                shouldBlockOriginalEvent: false,
                eventsToSend: [],
                detectedLanguage: nil,
                shouldSwitchLayout: false
            )
        }
        
        // Очищаем буфер при начале нового ввода (специальные клавиши)
        if shouldClearBufferForNewInput(event: event) {
            let bufferState = bufferManager.getState()
            bufferManager.clearForNewInput()
            logDebug("Buffer cleared for new input due to special key: \(event.keyCode). Previous state: \(bufferState)")
        }
        
        // Handle Arrows explicitly (clear buffer to avoid confusion)
        if event.keyCode >= 123 && event.keyCode <= 126 {
             bufferManager.clear()
             logDebug("Arrow key pressed, buffer cleared")
             return EventProcessingResult(
                shouldBlockOriginalEvent: false,
                eventsToSend: [],
                detectedLanguage: nil,
                shouldSwitchLayout: false
             )
        }
        
        // 2. Проверяем, нужно ли игнорировать событие
        if shouldIgnoreEvent(event) {
            logDebug("Ignoring event: \(event)")
            return EventProcessingResult(
                shouldBlockOriginalEvent: false,
                eventsToSend: [],
                detectedLanguage: nil,
                shouldSwitchLayout: false
            )
        }
        
        // 3. Добавляем символ в буфер
        bufferManager.addCharacter(event.unicodeString)
        logDebug("Added to buffer: '\(event.unicodeString)', current word: '\(bufferManager.getCurrentWord() ?? "")'")
        
        // 4. Проверяем границы слов
        if bufferManager.shouldProcessWord() {
            logDebug("Word ready for processing")
            return processWord()
        }
        
        // 4.1. Проверяем длину текущего слова для обработки без явных границ
        if let currentWord = bufferManager.getCurrentWord(), currentWord.count >= config.minWordLengthForSwitch {
            logDebug("Word length \(currentWord.count) ≥ \(config.minWordLengthForSwitch), checking if processing needed")
            
            // Проверяем, является ли это английским словом в русской раскладке
            if isEnglishWordInRussianLayout(currentWord) {
                logDebug("English word in Russian layout detected: '\(currentWord)', forcing word processing")
                // Принудительно завершаем слово и обрабатываем
                bufferManager.forceCompleteCurrentWord()
                return processWord()
            }
            
            // Для обычных слов проверяем уверенность
            let languageResult = neuralLanguageClassifier.classifyLanguage(
                currentWord,
                context: ClassificationContext(
                    applicationType: currentContext.applicationType,
                    previousLanguage: currentContext.lastDetectedLanguage
                )
            )
            
            if let detectedLanguage = languageResult.language, languageResult.confidence >= 0.8 {
                logDebug("High confidence (\(languageResult.confidence)) for language \(detectedLanguage), forcing word processing")
                bufferManager.forceCompleteCurrentWord()
                return processWord()
            }
        }
        
        // 5. Проверяем специальные комбинации клавиш
        if let specialResult = handleSpecialKeyCombinations(event) {
            logDebug("Special key combination handled")
            return specialResult
        }
        
        logDebug("Event processed, no action needed")
        return EventProcessingResult(
            shouldBlockOriginalEvent: false,
            eventsToSend: [],
            detectedLanguage: nil,
            shouldSwitchLayout: false
        )
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
        currentContext.isSecureField = isSecureFocusedField()
        
        // Определяем активное приложение
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            currentContext.activeApplication = frontmostApp
            currentContext.bundleIdentifier = frontmostApp.bundleIdentifier
            currentContext.processName = frontmostApp.localizedName
        }
        
        // Определяем тип приложения
        currentContext.applicationType = determineApplicationType()
        
        // Проверяем, не переключил ли пользователь раскладку вручную
        checkForManualLayoutSwitch(event)
    }
    
    private func checkForManualLayoutSwitch(_ event: KeyboardEvent) {
        // Проверяем комбинации клавиш для ручного переключения раскладки
        let flags = event.flags
        
        // Command+Space или Ctrl+Space - стандартные комбинации для переключения раскладки
        if (flags.contains(.maskCommand) || flags.contains(.maskControl)) && event.keyCode == 49 { // Space
            logDebug("Detected manual layout switch shortcut (Cmd/Ctrl+Space)")
            currentContext.lastLayoutSwitchByApp = false
            currentContext.expectedLayoutLanguage = nil
            currentContext.postSwitchWordCount = 0
            currentContext.postSwitchBuffer.removeAll()
        }
        
        // Проверяем текущую раскладку и сравниваем с ожидаемой
        if let currentLayout = layoutSwitcher.getCurrentLayout(),
           let currentLanguage = layoutSwitcher.getLanguage(for: currentLayout),
           let expectedLanguage = currentContext.expectedLayoutLanguage,
           currentLanguage != expectedLanguage {
            
            // Если BabylonFish переключил раскладку, но текущая раскладка отличается от ожидаемой
            // значит пользователь вручную переключил обратно
            if currentContext.lastLayoutSwitchByApp {
                logDebug("User manually switched layout from \(expectedLanguage) to \(currentLanguage)")
                currentContext.lastLayoutSwitchByApp = false
                currentContext.expectedLayoutLanguage = currentLanguage
                currentContext.postSwitchWordCount = 0
                currentContext.postSwitchBuffer.removeAll()
            }
        }
    }
    
    private func shouldIgnoreEvent(_ event: KeyboardEvent) -> Bool {
        // 1. Игнорируем события без символа
        if event.unicodeString.isEmpty {
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
            // Если нажата стрелка вправо - пользователь редактирует, сбрасываем буфер
            if event.keyCode == 124 { // Right Arrow
                logDebug("Right arrow pressed - user is editing, clearing buffer")
                bufferManager.clearWord()
            }
            return true
        }
        
        return false
    }
    
    private func processWord() -> EventProcessingResult {
        guard let word = bufferManager.getCurrentWord() else {
            logDebug("processWord: No current word in buffer")
            return EventProcessingResult(
                shouldBlockOriginalEvent: false,
                eventsToSend: [],
                detectedLanguage: nil,
                shouldSwitchLayout: false
            )
        }
        
        // Проверяем максимальную длину слова
        if word.count > config.maxWordLength {
            logDebug("processWord: Word too long (\(word.count) > \(config.maxWordLength)), skipping processing")
            bufferManager.clearWord()
            return EventProcessingResult(
                shouldBlockOriginalEvent: false,
                eventsToSend: [],
                detectedLanguage: nil,
                shouldSwitchLayout: false
            )
        }
        
        let bufferState = bufferManager.getState()
        logDebug("Processing word: '\(word)' (buffer state: \(bufferState))")
        
        // 1. Анализируем контекст
        let detectionContext = DetectionContext(
            applicationType: currentContext.applicationType,
            isSecureField: currentContext.isSecureField,
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
            return EventProcessingResult(
                shouldBlockOriginalEvent: false,
                eventsToSend: [],
                detectedLanguage: nil,
                shouldSwitchLayout: false
            )
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
        var decisionMethod = "unknown"
        
        // Улучшенная логика принятия решений с учетом границ предложений
        if contextAnalysis.isConfident, let ctxLang = contextAnalysis.suggestedLanguage {
            // Проверяем, согласуется ли контекстный язык с нейросетевым предсказанием
            if let clsLang = languageResult.language, languageResult.confidence >= 0.8 {
                // Нейросеть очень уверена - проверяем согласованность
                if clsLang == ctxLang {
                    // Согласованы - используем контекст
                    selectedLanguage = ctxLang
                    selectedConfidence = max(contextAnalysis.confidence, languageResult.confidence)
                    decisionMethod = "context+classifier_agreement"
                } else {
                    // Не согласованы - приоритет нейросети при высокой уверенности
                    if languageResult.confidence >= 0.9 {
                        selectedLanguage = clsLang
                        selectedConfidence = languageResult.confidence
                        decisionMethod = "classifier_high_confidence_override"
                        logDebug("Classifier override: high confidence (\(languageResult.confidence)) overrides context")
                    } else {
                        // Умеренная уверенность - используем контекст
                        selectedLanguage = ctxLang
                        selectedConfidence = contextAnalysis.confidence
                        decisionMethod = "context_moderate_classifier"
                    }
                }
            } else {
                // Нейросеть не уверена или нет предсказания - используем контекст
                selectedLanguage = ctxLang
                selectedConfidence = contextAnalysis.confidence
                decisionMethod = "context_only"
            }
        } else if let clsLang = languageResult.language {
            // Нет уверенного контекста - используем нейросеть
            selectedLanguage = clsLang
            selectedConfidence = languageResult.confidence
            decisionMethod = "classifier_only"
        }
        
        logDebug("Language decision: \(decisionMethod) (\(selectedLanguage?.rawValue ?? "none"), \(String(format: "%.2f", selectedConfidence)))")
        
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
        
        // 5. Трекаем слова после переключения BabylonFish
        if currentContext.lastLayoutSwitchByApp, let detectedLang = selectedLanguage {
            currentContext.postSwitchWordCount += 1
            currentContext.postSwitchBuffer.append(word)
            
            // Если пользователь печатает на ожидаемом языке после переключения
            if let expectedLang = currentContext.expectedLayoutLanguage {
                if detectedLang == expectedLang {
                    logDebug("Post-switch word \(currentContext.postSwitchWordCount): '\(word)' in expected language \(detectedLang)")
                } else {
                    logDebug("Post-switch word \(currentContext.postSwitchWordCount): '\(word)' in unexpected language \(detectedLang) (expected \(expectedLang))")
                    
                    // Если пользователь печатает на другом языке несколько слов подряд,
                    // возможно, он вручную переключил раскладку
                    if currentContext.postSwitchWordCount >= 2 {
                        logDebug("Multiple words in unexpected language - user may have manually switched layout")
                        currentContext.lastLayoutSwitchByApp = false // Reset BabylonFish switch tracking
                    }
                }
            } else {
                logDebug("Post-switch word \(currentContext.postSwitchWordCount): '\(word)' in language \(detectedLang) (no expected language set)")
            }
        }
        
        // 6. Очищаем буфер
        bufferManager.clearWord()
        
        // Возвращаем результат с обнаруженным языком, но без переключения
        return EventProcessingResult(
            shouldBlockOriginalEvent: false,
            eventsToSend: [],
            detectedLanguage: selectedLanguage,
            shouldSwitchLayout: false
        )
    }
    
    /// Обрабатывает слово, которое было отложено при нажатии Space/Return
    private func processPendingWord(_ word: String) {
        logDebug("processPendingWord called for: '\(word)'")
        
        // Проверяем, является ли это английским словом в русской раскладке
        if isEnglishWordInRussianLayout(word) {
            logDebug("Processing English word in Russian layout: '\(word)'")
            
            // Конвертируем слово из русской раскладки в английскую
            let englishWord = convertFromRussianLayout(word)
            logDebug("Converted '\(word)' → '\(englishWord)'")
            
            // Получаем английскую раскладку и переключаемся на нее
            if let englishLayout = layoutSwitcher.getLayoutForLanguage(.english),
               layoutSwitcher.switchToLayout(englishLayout) {
                logDebug("Switched to English layout for word: '\(englishWord)'")
                layoutSwitches += 1
                
                // Отправляем события для замены слова
                // Note: В реальной реализации здесь будет отправка событий клавиатуры
                // для удаления русского слова и ввода английского
            }
        } else {
            // Для обычных слов с высокой уверенностью
            logDebug("Processing high-confidence word: '\(word)'")
            
            let languageResult = neuralLanguageClassifier.classifyLanguage(
                word,
                context: ClassificationContext(
                    applicationType: currentContext.applicationType,
                    previousLanguage: currentContext.lastDetectedLanguage
                )
            )
            
            if let detectedLanguage = languageResult.language, languageResult.confidence >= 0.8 {
                logDebug("Detected language: \(detectedLanguage) with confidence \(languageResult.confidence)")
                
                // Проверяем, нужно ли переключать раскладку
                if shouldSwitchLayout(for: word, detectedLanguage: detectedLanguage) {
                    logDebug("Should switch layout for word: '\(word)'")
                    
                    if let targetLayout = layoutSwitcher.getLayoutForLanguage(detectedLanguage),
                       layoutSwitcher.switchToLayout(targetLayout) {
                        logDebug("Switched to \(detectedLanguage) layout")
                        layoutSwitches += 1
                    }
                }
            }
        }
        
        // Сбрасываем состояние
        pendingSpaceWord = nil
        pendingSpaceRequiresProcessing = false
    }
    
    private func shouldSwitchLayout(for word: String, detectedLanguage: Language) -> Bool {
        logDebug("shouldSwitchLayout called for word='\(word)', detectedLanguage=\(detectedLanguage), word.count=\(word.count), minWordLengthForSwitch=\(config.minWordLengthForSwitch)")
        
        // Специальная проверка для обратной конвертации (английские слова в русской раскладке)
        // Для таких слов разрешаем более короткую длину
        logDebug("Checking reverse conversion: detectedLanguage=\(detectedLanguage), word='\(word)'")
        if detectedLanguage == .english {
            logDebug("detectedLanguage is .english, checking isEnglishWordInRussianLayout...")
            let isEnglishInRussian = isEnglishWordInRussianLayout(word)
            logDebug("isEnglishWordInRussianLayout('\(word)') = \(isEnglishInRussian)")
            if isEnglishInRussian {
                logDebug("English word in Russian layout detected: '\(word)'")
                // Для обратной конвертации разрешаем слова от 2 букв
                if word.count >= 2 {
                    logDebug("✅ Short English word in Russian layout (≥2 chars) → allowing switch")
                    return true
                } else {
                    logDebug("Word too short even for reverse conversion: \(word.count) < 2")
                    return false
                }
            }
        }
        
        // Специальная проверка для русских слов в английской раскладке
        // Когда пользователь печатает русские слова в английской раскладке
        if detectedLanguage == .russian {
            logDebug("detectedLanguage is .russian, checking if it's Russian word in English layout...")
            let isRussianInEnglish = isRussianWordInEnglishLayout(word)
            logDebug("isRussianWordInEnglishLayout('\(word)') = \(isRussianInEnglish)")
            if isRussianInEnglish {
                logDebug("Russian word in English layout detected: '\(word)'")
                // Для таких слов разрешаем переключение от 3 букв
                if word.count >= 3 {
                    logDebug("✅ Russian word in English layout (≥3 chars) → allowing switch")
                    return true
                } else {
                    logDebug("Word too short for Russian in English layout: \(word.count) < 3")
                    return false
                }
            }
        }
        
        // 1. Проверяем минимальную длину слова для обычных случаев
        guard word.count >= config.minWordLengthForSwitch else {
            logDebug("Word too short: \(word.count) < \(config.minWordLengthForSwitch)")
            return false
        }
        
        // 2. Проверяем исключения
        if config.wordExceptions.contains(word.lowercased()) {
            logDebug("Word is in exceptions list: '\(word.lowercased())'")
            return false
        }
        
        // 3. Получаем текущую раскладку
        guard let currentLayout = layoutSwitcher.getCurrentLayout() else {
            logDebug("Cannot get current layout")
            return false
        }
        
        logDebug("Current layout: \(currentLayout)")
        
        // 4. Определяем язык текущей раскладки
        guard let currentLayoutLanguage = layoutSwitcher.getLanguage(for: currentLayout) else {
            logDebug("Cannot get language for layout: \(currentLayout)")
            return false
        }
        
        logDebug("Current layout language: \(currentLayoutLanguage), detected language: \(detectedLanguage)")
        
        // 5. Сравниваем языки
        if currentLayoutLanguage == detectedLanguage {
            logDebug("Current layout language matches detected language: \(currentLayoutLanguage)")
            return false
        }
        
        logDebug("Languages differ: current=\(currentLayoutLanguage), detected=\(detectedLanguage)")
        
        // 6. Проверяем, не переключили ли мы уже раскладку для этого слова
        if currentContext.lastLayoutSwitchTime != nil {
            let timeSinceLastSwitch = Date().timeIntervalSince(currentContext.lastLayoutSwitchTime!)
            
            // Если BabylonFish переключил раскладку недавно, пользователь должен быть на новой раскладке
            if currentContext.lastLayoutSwitchByApp && timeSinceLastSwitch < 5.0 {
                logDebug("BabylonFish switched layout \(String(format: "%.1f", timeSinceLastSwitch))s ago, user should be on \(currentContext.expectedLayoutLanguage?.rawValue ?? "unknown") layout")
                
                // Если пользователь продолжает печатать на старой раскладке, это нормально
                // Не пытаемся снова переключить
                if let expectedLang = currentContext.expectedLayoutLanguage, detectedLanguage == expectedLang {
                    logDebug("User typing \(detectedLanguage) on expected \(expectedLang) layout - assuming correct behavior")
                    return false
                }
            }
            
            // Общий таймаут между переключениями
            if timeSinceLastSwitch < 2.0 {
                logDebug("Recently switched layout (\(String(format: "%.1f", timeSinceLastSwitch))s ago), not switching again")
                return false
            }
        }
        
        // 7. Проверяем уверенность для раннего срабатывания
        let confidence = getDetectionConfidence(for: word, language: detectedLanguage)
        
        // Если уверенность 100% и слово начинается с подозрительной комбинации
        if confidence >= 1.0 && isSuspiciousStart(word: word, language: detectedLanguage) {
            logDebug("Early detection: 100% confidence for suspicious start '\(word)'")
            return true
        }
        
        // Если слово закончено (есть разделитель) и уверенность достаточная
        if isWordComplete(word) && confidence >= 0.8 {
            logDebug("Complete word detection: confidence \(confidence) for '\(word)'")
            return true
        }
        
        // Если слово длинное (>5 символов) и уверенность высокая
        if word.count >= 5 && confidence >= 0.9 {
            logDebug("Long word detection: confidence \(confidence) for '\(word)'")
            logDebug("✅ shouldSwitchLayout returning TRUE (long word with high confidence)")
            return true
        }
        
        // Проверяем, не является ли слово валидным в текущей раскладке
        // Если нейросеть уверена, что слово английское, а мы пытаемся переключить на русский,
        // возможно, слово действительно английское и не требует конвертации
        let neuralResult = neuralLanguageClassifier.classifyLanguage(
            word,
            context: ClassificationContext(
                applicationType: currentContext.applicationType,
                previousLanguage: currentContext.lastDetectedLanguage
            )
        )
        
        if neuralResult.confidence >= 0.8 && neuralResult.language == currentLayoutLanguage {
            logDebug("Neural network confident word is \(neuralResult.language?.rawValue ?? "unknown") (confidence: \(neuralResult.confidence)) and matches current layout → not switching")
            return false
        }
        
        logDebug("❌ shouldSwitchLayout returning FALSE (no conditions met)")
        logDebug("  - isWordComplete=\(isWordComplete(word)), confidence=\(confidence)")
        logDebug("  - word.count=\(word.count) >= 5, confidence >= 0.9")
        logDebug("  - neural result: \(neuralResult.language?.rawValue ?? "unknown") with confidence \(neuralResult.confidence)")
        return false
    }
    
    private func getDetectionConfidence(for word: String, language: Language) -> Double {
        logDebug("getDetectionConfidence called for word='\(word)', language=\(language)")
        
        // Проверяем биграммы/триграммы для раннего определения
        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanWord.count >= 2 {
            let bigram = String(cleanWord.prefix(2)).lowercased()
            if language == .russian && isRussianBigram(bigram) {
                logDebug("Found Russian bigram '\(bigram)' → confidence 1.0")
                return 1.0
            }
            if language == .english && isEnglishBigram(bigram) {
                logDebug("Found English bigram '\(bigram)' → confidence 1.0")
                return 1.0
            }
        }
        
        if cleanWord.count >= 3 {
            let trigram = String(cleanWord.prefix(3)).lowercased()
            if language == .russian && isRussianTrigram(trigram) {
                logDebug("Found Russian trigram '\(trigram)' → confidence 1.0")
                return 1.0
            }
            if language == .english && isEnglishTrigram(trigram) {
                logDebug("Found English trigram '\(trigram)' → confidence 1.0")
                return 1.0
            }
        }
        
        // Специальная проверка для обратной конвертации
        // Если слово выглядит как английское слово, напечатанное в русской раскладке
        if language == .english && isEnglishWordInRussianLayout(cleanWord) {
            logDebug("Detected English word in Russian layout: '\(cleanWord)' → confidence 0.95")
            return 0.95
        }
        
        // Если слово выглядит как русское слово, напечатанное в английской раскладке
        if language == .russian && isRussianWordInEnglishLayout(cleanWord) {
            logDebug("Detected Russian word in English layout: '\(cleanWord)' → confidence 0.95")
            return 0.95
        }
        
        // Используем нейросеть для оценки уверенности
        let result = neuralLanguageClassifier.classifyLanguage(
            cleanWord,
            context: ClassificationContext(
                applicationType: currentContext.applicationType,
                previousLanguage: currentContext.lastDetectedLanguage
            )
        )
        
        logDebug("Neural classifier result: language=\(String(describing: result.language)), confidence=\(result.confidence)")
        
        if result.language == language {
            logDebug("Classifier matches requested language → confidence \(result.confidence)")
            return result.confidence
        }
        
        // Если нейросеть уверена в другом языке с высокой уверенностью,
        // это может означать, что слово действительно на другом языке
        // и не требует конвертации
        if result.confidence >= 0.8 {
            logDebug("Classifier confident in different language (\(result.language?.rawValue ?? "unknown") with confidence \(result.confidence)) → confidence 0.0 for requested language \(language)")
            return 0.0
        }
        
        logDebug("Classifier doesn't match requested language and confidence is low → confidence 0.0")
        return 0.0
    }
    
    private func isEnglishWordInRussianLayout(_ word: String) -> Bool {
        let lowercased = word.lowercased()
        
        logDebug("isEnglishWordInRussianLayout checking: '\(word)' -> '\(lowercased)', length=\(lowercased.count)")
        
        // Английское слово в русской раскладке должно состоять из русских букв
        // Проверяем, что слово содержит только русские буквы
        let russianLetters = CharacterSet(charactersIn: "абвгдеёжзийклмнопрстуфхцчшщъыьэюя")
        let wordCharacterSet = CharacterSet(charactersIn: lowercased)
        
        if !russianLetters.isSuperset(of: wordCharacterSet) {
            logDebug("❌ isEnglishWordInRussianLayout: Word '\(lowercased)' contains non-Russian letters, cannot be English word in Russian layout")
            return false
        }
        
        // 1. Проверяем известные паттерны (для быстрой проверки)
        let englishInRussianPatterns = [
            "руддщ", // hello
            "щт",    // in
            "йфя",   // was
            "еуые",  // test
            "рщц",   // how
            "яку",   // you (альтернативная раскладка)
            "нщг",   // you
            "фку",   // are
            "ерш",   // the
            "ышы",   // she
            "феу",   // get
            "ыеш",   // test (alternative)
            "тпд",   // and
            "шыр",   // car
            "юиф",   // zip
            "инд",   // win
            "щта",   // inta
            "шырт",  // cart
            "щец",   // ice
            "щкл",   // ickl
            "штп",   // intp
            "ю",     // ,
        ]
        
        logDebug("Checking against \(englishInRussianPatterns.count) patterns")
        
        for (index, pattern) in englishInRussianPatterns.enumerated() {
            logDebug("  Pattern \(index): '\(pattern)' (length: \(pattern.count))")
            if lowercased.hasPrefix(pattern) {
                logDebug("✅ isEnglishWordInRussianLayout: '\(lowercased)' matches pattern '\(pattern)' at index \(index)")
                if pattern == "руддщ" {
                    logDebug("🎯 SPECIAL: Found 'руддщ' pattern for word '\(word)'")
                }
                return true
            }
        }
        
        // 2. Для коротких слов (2-4 символа) используем улучшенную проверку с NSSpellChecker
        if lowercased.count >= 2 && lowercased.count <= 4 {
            logDebug("Short word (\(lowercased.count) chars), checking with enhanced NSSpellChecker logic...")
            
            // Проверяем оба языка через NSSpellChecker
            let isEnglishWord = SystemDictionaryService.shared.checkSpelling(lowercased, languageCode: "en")
            let isRussianWord = SystemDictionaryService.shared.checkSpelling(lowercased, languageCode: "ru")
            
            logDebug("NSSpellChecker results:")
            logDebug("  '\(lowercased)' is valid English word: \(isEnglishWord)")
            logDebug("  '\(lowercased)' is valid Russian word: \(isRussianWord)")
            
            // Улучшенная логика: проверяем оба языка и сравниваем
            // Если слово валидно только в английском, но не в русском → это английское слово в русской раскладке
            if isEnglishWord && !isRussianWord {
                logDebug("✅ isEnglishWordInRussianLayout: Short word '\(lowercased)' is ONLY valid in English via NSSpellChecker")
                return true
            }
            
            // Если слово валидно в обоих языках → неоднозначный случай, нужна дополнительная проверка
            if isEnglishWord && isRussianWord {
                logDebug("⚠️  Ambiguous case: '\(lowercased)' is valid in both English and Russian")
                // Проверяем, есть ли слово в списке известных английских слов в русской раскладке
                // (например, "фку" = "are", "яку" = "you")
                // Если нет, то скорее всего это русское слово
                return false
            }
            
            // Если слово не валидно ни в одном языке → не английское слово в русской раскладке
            logDebug("❌ isEnglishWordInRussianLayout: Short word '\(lowercased)' is not valid in English or ambiguous")
        }
        
        // 3. Используем нейросеть для дополнительной проверки
        let neuralResult = neuralLanguageClassifier.classifyLanguage(
            lowercased,
            context: ClassificationContext(
                applicationType: currentContext.applicationType,
                previousLanguage: currentContext.lastDetectedLanguage
            )
        )
        
        if neuralResult.language == .english && neuralResult.confidence >= 0.7 {
            logDebug("✅ isEnglishWordInRussianLayout: Neural network confident word is English (confidence: \(neuralResult.confidence))")
            return true
        }
        
        logDebug("❌ isEnglishWordInRussianLayout: '\(lowercased)' doesn't match any pattern or validation")
        logDebug("  Word characters: \(Array(lowercased).map { String($0) })")
        logDebug("  Neural result: \(neuralResult.language?.rawValue ?? "unknown") with confidence \(neuralResult.confidence)")
        return false
    }
    
    /// Конвертирует слово из русской раскладки в английскую
    private func convertFromRussianLayout(_ word: String) -> String {
        logDebug("convertFromRussianLayout called for: '\(word)'")
        
        // Таблица соответствия русских символов в русской раскладке английским символам
        let russianToEnglishMap: [Character: Character] = [
            "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y", "г": "u", "ш": "i", "щ": "o", "з": "p",
            "х": "[", "ъ": "]", "ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h", "о": "j", "л": "k",
            "д": "l", "ж": ";", "э": "'", "я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m",
            "б": ",", "ю": ".", "ё": "`",
            "Й": "Q", "Ц": "W", "У": "E", "К": "R", "Е": "T", "Н": "Y", "Г": "U", "Ш": "I", "Щ": "O", "З": "P",
            "Х": "{", "Ъ": "}", "Ф": "A", "Ы": "S", "В": "D", "А": "F", "П": "G", "Р": "H", "О": "J", "Л": "K",
            "Д": "L", "Ж": ":", "Э": "\"", "Я": "Z", "Ч": "X", "С": "C", "М": "V", "И": "B", "Т": "N", "Ь": "M",
            "Б": "<", "Ю": ">", "Ё": "~"
        ]
        
        var result = ""
        for char in word {
            if let englishChar = russianToEnglishMap[char] {
                result.append(englishChar)
            } else {
                // Если символ не найден в таблице, оставляем как есть
                result.append(char)
            }
        }
        
        logDebug("convertFromRussianLayout: '\(word)' → '\(result)'")
        return result
    }
    
    /// Конвертирует слово из английской раскладки в русскую
    private func convertFromEnglishLayout(_ word: String) -> String {
        logDebug("convertFromEnglishLayout called for: '\(word)'")
        
        // Таблица соответствия английских символов в английской раскладке русским символам
        let englishToRussianMap: [Character: Character] = [
            "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
            "[": "х", "]": "ъ", "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л",
            "l": "д", ";": "ж", "'": "э", "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
            ",": "б", ".": "ю", "`": "ё",
            "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е", "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
            "{": "Х", "}": "Ъ", "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П", "H": "Р", "J": "О", "K": "Л",
            "L": "Д", ":": "Ж", "\"": "Э", "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь",
            "<": "Б", ">": "Ю", "~": "Ё"
        ]
        
        var result = ""
        for char in word {
            if let russianChar = englishToRussianMap[char] {
                result.append(russianChar)
            } else {
                // Если символ не найден в таблице, оставляем как есть
                result.append(char)
            }
        }
        
        logDebug("convertFromEnglishLayout: '\(word)' → '\(result)'")
        return result
    }
    
    private func isRussianWordInEnglishLayout(_ word: String) -> Bool {
        let lowercased = word.lowercased()
        
        logDebug("isRussianWordInEnglishLayout checking: '\(word)' -> '\(lowercased)', length=\(lowercased.count)")
        
        // Русское слово в английской раскладке должно состоять из английских букв
        // Проверяем, что слово содержит только английские буквы
        let englishLetters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        let wordCharacterSet = CharacterSet(charactersIn: lowercased)
        
        if !englishLetters.isSuperset(of: wordCharacterSet) {
            logDebug("❌ isRussianWordInEnglishLayout: Word '\(lowercased)' contains non-English letters, cannot be Russian word in English layout")
            return false
        }
        
        // 1. Проверяем известные паттерны (русские слова в английской раскладке)
        let russianInEnglishPatterns = [
            "ghbdtn",  // привет
            "yfcnz",   // слово
            "njkmrj",  // номер
            "rfr",     // что
            "vjq",     // да
            "yt",      // нет
            "lj",      // да (альтернатива)
            "xtkjdtr", // программа
            "cnfnm",   // место
            "gjckt",   // время
            "rjvgm",   // человек
            "dctv",    // дело
            "gjcnj",   // время (альтернатива)
            "rfrjq",   // что-то
            "vj;tn",   // делать
            "ytn",     // нет (длиннее)
            "ljkz",    // давай
            "xtkjd",   // програм
            "cnf",     // мес
            "gjc",     // вре
        ]
        
        logDebug("Checking against \(russianInEnglishPatterns.count) patterns")
        
        for (index, pattern) in russianInEnglishPatterns.enumerated() {
            logDebug("  Pattern \(index): '\(pattern)' (length: \(pattern.count))")
            if lowercased.hasPrefix(pattern) {
                logDebug("✅ isRussianWordInEnglishLayout: '\(lowercased)' matches pattern '\(pattern)' at index \(index)")
                if pattern == "ghbdtn" {
                    logDebug("🎯 SPECIAL: Found 'ghbdtn' pattern for word '\(word)' (привет в английской раскладке)")
                }
                return true
            }
        }
        
        // 2. Для коротких слов (3-6 символов) используем улучшенную проверку с NSSpellChecker
        if lowercased.count >= 3 && lowercased.count <= 6 {
            logDebug("Short word (\(lowercased.count) chars), checking with enhanced NSSpellChecker logic...")
            
            // Проверяем оба языка через NSSpellChecker
            let isEnglishWord = SystemDictionaryService.shared.checkSpelling(lowercased, languageCode: "en")
            let isRussianWord = SystemDictionaryService.shared.checkSpelling(lowercased, languageCode: "ru")
            
            logDebug("NSSpellChecker results:")
            logDebug("  '\(lowercased)' is valid English word: \(isEnglishWord)")
            logDebug("  '\(lowercased)' is valid Russian word: \(isRussianWord)")
            
            // Улучшенная логика: проверяем оба языка и сравниваем
            // Если слово валидно только в русском, но не в английском → это русское слово в английской раскладке
            if isRussianWord && !isEnglishWord {
                logDebug("✅ isRussianWordInEnglishLayout: Short word '\(lowercased)' is ONLY valid in Russian via NSSpellChecker")
                return true
            }
            
            // Если слово валидно в обоих языках → неоднозначный случай, нужна дополнительная проверка
            if isEnglishWord && isRussianWord {
                logDebug("⚠️  Ambiguous case: '\(lowercased)' is valid in both English and Russian")
                // Проверяем, есть ли слово в списке известных русских слов в английской раскладке
                // Если нет, то скорее всего это английское слово
                return false
            }
            
            // Если слово не валидно ни в одном языке → проверяем через нейросеть
            logDebug("❌ isRussianWordInEnglishLayout: Short word '\(lowercased)' is not valid in Russian or ambiguous")
        }
        
        // 3. Используем нейросеть для дополнительной проверки
        let neuralResult = neuralLanguageClassifier.classifyLanguage(
            lowercased,
            context: ClassificationContext(
                applicationType: currentContext.applicationType,
                previousLanguage: currentContext.lastDetectedLanguage
            )
        )
        
        if neuralResult.language == .russian && neuralResult.confidence >= 0.7 {
            logDebug("✅ isRussianWordInEnglishLayout: Neural network confident word is Russian (confidence: \(neuralResult.confidence))")
            return true
        }
        
        // 4. Проверяем, содержит ли слово только символы английской раскладки
        // Русские слова в английской раскладке содержат только символы a-z
        let englishLetters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        let wordCharacterSet = CharacterSet(charactersIn: lowercased)
        
        if englishLetters.isSuperset(of: wordCharacterSet) {
            logDebug("Word contains only English letters, could be Russian in English layout")
            // Дополнительная проверка: конвертируем из английской раскладки в русскую
            let convertedToRussian = convertFromEnglishLayout(lowercased)
            logDebug("Converted from English layout: '\(lowercased)' → '\(convertedToRussian)'")
            
            // Проверяем, является ли результат валидным русским словом
            let isConvertedRussianWord = SystemDictionaryService.shared.checkSpelling(convertedToRussian, languageCode: "ru")
            if isConvertedRussianWord {
                logDebug("✅ isRussianWordInEnglishLayout: Converted word '\(convertedToRussian)' is valid Russian word")
                return true
            }
        }
        
        logDebug("❌ isRussianWordInEnglishLayout: '\(lowercased)' doesn't match any pattern or validation")
        logDebug("  Word characters: \(Array(lowercased).map { String($0) })")
        logDebug("  Neural result: \(neuralResult.language?.rawValue ?? "unknown") with confidence \(neuralResult.confidence)")
        return false
    }
    
    private func isSuspiciousStart(word: String, language: Language) -> Bool {
        let cleanWord = word.lowercased()
        
        if language == .russian {
            // Комбинации, которые не встречаются в английском
            let suspiciousStarts = ["gh", "ghb", "ghbd", "rj", "rfr", "plh", "plhf", "ntcn", "yf"]
            return suspiciousStarts.contains { cleanWord.hasPrefix($0) }
        } else if language == .english {
            // Комбинации, которые не встречаются в русском
            let suspiciousStarts = ["руд", "рудд", "щт", "щты", "йфя", "йфяч"]
            return suspiciousStarts.contains { cleanWord.hasPrefix($0) }
        }
        
        return false
    }
    
    private func isWordComplete(_ word: String) -> Bool {
        // Слово закончено если есть пробел, пунктуация или нажат Enter
        let separators = CharacterSet(charactersIn: " .,!?;:\"\n\t")
        let result = word.unicodeScalars.contains { separators.contains($0) }
        logDebug("isWordComplete('\(word)') = \(result)")
        return result
    }
    
    private func isRussianBigram(_ bigram: String) -> Bool {
        // Биграммы, которые явно указывают на русский язык
        let russianBigrams = ["gh", "rj", "pl", "nt", "yf", "kb", "uj", "gb", "db", "el"]
        return russianBigrams.contains(bigram)
    }
    
    private func isEnglishBigram(_ bigram: String) -> Bool {
        // Биграммы, которые явно указывают на английский язык
        let englishBigrams = ["th", "he", "in", "er", "an", "re", "nd", "at", "on", "nt"]
        return englishBigrams.contains(bigram)
    }
    
    private func isRussianTrigram(_ trigram: String) -> Bool {
        // Триграммы, которые явно указывают на русский язык
        let russianTrigrams = ["ghb", "rfr", "plh", "ntc", "yfl", "kbr", "ujd", "gbt", "dbt", "elt"]
        return russianTrigrams.contains(trigram)
    }
    
    private func isEnglishTrigram(_ trigram: String) -> Bool {
        // Триграммы, которые явно указывают на английский язык
        let englishTrigrams = ["the", "and", "ing", "her", "hat", "his", "ere", "for", "ent", "ion"]
        return englishTrigrams.contains(trigram)
    }
    
    /// Разделяет слово и знаки препинания (начало и конец)
    private func separateWordAndPunctuation(_ text: String) -> (word: String, leadingPunctuation: String, trailingPunctuation: String) {
        let punctuationChars = CharacterSet.punctuationCharacters
            .union(CharacterSet.symbols)
            .union(CharacterSet(charactersIn: "«»\"'`"))
        
        var word = text
        var leadingPunctuation = ""
        var trailingPunctuation = ""
        
        logDebug("Separating '\(text)' - checking punctuation chars")
        
        // 1. Ищем знаки препинания в начале
        while let firstChar = word.first {
            let charStr = String(firstChar)
            if charStr.rangeOfCharacter(from: punctuationChars) != nil {
                leadingPunctuation.append(charStr)
                word.removeFirst()
                logDebug("Found leading punctuation: '\(charStr)', remaining word: '\(word)'")
            } else {
                break
            }
        }
        
        // 2. Ищем знаки препинания в конце
        while let lastChar = word.last {
            let charStr = String(lastChar)
            if charStr.rangeOfCharacter(from: punctuationChars) != nil {
                trailingPunctuation = charStr + trailingPunctuation
                word.removeLast()
                logDebug("Found trailing punctuation: '\(charStr)', remaining word: '\(word)'")
            } else {
                break
            }
        }
        
        logDebug("Separated result: word='\(word)', leading='\(leadingPunctuation)', trailing='\(trailingPunctuation)'")
        return (word, leadingPunctuation, trailingPunctuation)
    }
    
    /// Создает события клавиш для текста (без конвертации раскладки)
    private func createKeyEventsForText(_ text: String) -> [KeyboardEvent] {
        logDebug("Creating key events for text: '\(text)'")
        
        // Для знаков препинания используем текущий язык из контекста
        let currentLanguage = currentContext.lastDetectedLanguage ?? .english
        
        // Используем LayoutSwitcher для создания событий
        // Знаки препинания обычно одинаковы на обеих раскладках
        let events = layoutSwitcher.getKeyEventsForWord(text, inLanguage: currentLanguage)
        
        logDebug("Created \(events.count) key events for text '\(text)' using language \(currentLanguage)")
        return events
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
            
            // 3. Обновляем контекст: BabylonFish переключил раскладку
            currentContext.lastLayoutSwitchTime = Date()
            currentContext.lastLayoutSwitchByApp = true
            currentContext.expectedLayoutLanguage = targetLanguage
            currentContext.postSwitchWordCount = 0
            currentContext.postSwitchBuffer.removeAll()
            logDebug("Context updated: BabylonFish switched to \(targetLanguage)")
            
            // 4. Разделяем слово и знаки препинания
            let (cleanWord, leadingPunctuation, trailingPunctuation) = separateWordAndPunctuation(word)
            logDebug("Separated: word='\(cleanWord)', leading='\(leadingPunctuation)', trailing='\(trailingPunctuation)'")
            
            // 5. Удаляем неправильное слово (backspace события)
            // Используем длину cleanWord, так как знаки препинания обычно одинаковы в обеих раскладках
            let backspaceEvents = createBackspaceEvents(count: cleanWord.count)
            logDebug("Created \(backspaceEvents.count) backspace events for clean word length \(cleanWord.count) (original word length: \(word.count))")
            
            // 6. Печатаем исправленное слово
            // Явно конвертируем слово в целевой язык
            let correctedWord = convertWordToTargetLanguage(cleanWord, targetLanguage: targetLanguage)
            let correctionEvents = layoutSwitcher.getKeyEventsForWord(correctedWord, inLanguage: targetLanguage)
            logDebug("Created \(correctionEvents.count) correction events for word '\(correctedWord)'")
            
            // 7. Добавляем события в правильном порядке
            var allEvents: [KeyboardEvent] = []
            
            // Сначала удаляем неправильное слово
            allEvents.append(contentsOf: backspaceEvents)
            
            // Затем leading punctuation (если есть) - знаки препинания перед словом
            if !leadingPunctuation.isEmpty {
                logDebug("Adding leading punctuation: '\(leadingPunctuation)'")
                let leadingEvents = createKeyEventsForText(leadingPunctuation)
                allEvents.append(contentsOf: leadingEvents)
            }
            
            // Затем исправленное слово
            allEvents.append(contentsOf: correctionEvents)
            
            // Затем trailing punctuation (если есть) - знаки препинания после слова
            if !trailingPunctuation.isEmpty {
                logDebug("Adding trailing punctuation: '\(trailingPunctuation)'")
                let trailingEvents = createKeyEventsForText(trailingPunctuation)
                allEvents.append(contentsOf: trailingEvents)
            }
            
            // 8. Обучаем модель
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
            
            // 9. Очищаем буфер
            bufferManager.clearWord()
            
            logDebug("Layout switched successfully to \(targetLanguage), total events: \(allEvents.count)")
            return EventProcessingResult(
                shouldBlockOriginalEvent: true,
                eventsToSend: allEvents,
                detectedLanguage: targetLanguage,
                shouldSwitchLayout: true
            )
        }
        
        return .default
    }
    
    private func handleTypoCorrection(word: String, correctionResult: CorrectionResult) -> EventProcessingResult {
        logDebug("Correcting typo: '\(word)' → '\(correctionResult.correctedText)'")
        logDebug("Typo analysis: \(correctionResult.description) applied=\(correctionResult.applied) conf=\(String(format: "%.2f", correctionResult.confidence))")
        
        correctionsMade += 1
        
        // 1. Разделяем слово и знаки препинания
        let (cleanWord, leadingPunctuation, trailingPunctuation) = separateWordAndPunctuation(word)
        let (correctedCleanWord, correctedLeadingPunctuation, correctedTrailingPunctuation) = separateWordAndPunctuation(correctionResult.correctedText)
        
        logDebug("Original: word='\(cleanWord)', leading='\(leadingPunctuation)', trailing='\(trailingPunctuation)'")
        logDebug("Corrected: word='\(correctedCleanWord)', leading='\(correctedLeadingPunctuation)', trailing='\(correctedTrailingPunctuation)'")
        
        // 2. Удаляем неправильное слово
        let backspaceEvents = createBackspaceEvents(count: word.count)
        logDebug("Created \(backspaceEvents.count) backspace events")
        
        // 3. Печатаем исправленное слово
        let language = currentContext.lastDetectedLanguage ?? .english
        let correctionEvents = layoutSwitcher.getKeyEventsForWord(correctedCleanWord, inLanguage: language)
        logDebug("Created \(correctionEvents.count) correction events")
        
        // 4. Добавляем знаки препинания в правильном порядке
        // Используем исправленные знаки препинания, если есть, иначе оригинальные
        let finalLeadingPunctuation = !correctedLeadingPunctuation.isEmpty ? correctedLeadingPunctuation : leadingPunctuation
        let finalTrailingPunctuation = !correctedTrailingPunctuation.isEmpty ? correctedTrailingPunctuation : trailingPunctuation
        
        var allEvents: [KeyboardEvent] = []
        
        // Сначала leading punctuation
        if !finalLeadingPunctuation.isEmpty {
            logDebug("Adding leading punctuation: '\(finalLeadingPunctuation)'")
            let leadingEvents = createKeyEventsForText(finalLeadingPunctuation)
            allEvents.append(contentsOf: leadingEvents)
        }
        
        // Затем исправленное слово
        allEvents.append(contentsOf: backspaceEvents)
        allEvents.append(contentsOf: correctionEvents)
        
        // Затем trailing punctuation
        if !finalTrailingPunctuation.isEmpty {
            logDebug("Adding trailing punctuation: '\(finalTrailingPunctuation)'")
            let trailingEvents = createKeyEventsForText(finalTrailingPunctuation)
            allEvents.append(contentsOf: trailingEvents)
        }
        
        // 5. Обучаем модель
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
        
        // 6. Очищаем буфер
        bufferManager.clearWord()
        
        logDebug("Typo corrected: \(word) → \(correctionResult.correctedText), total events: \(allEvents.count)")
        return EventProcessingResult(
            shouldBlockOriginalEvent: true,
            eventsToSend: allEvents,
            detectedLanguage: nil,
            shouldSwitchLayout: false
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
        guard event.keyCode == 56 || event.keyCode == 60 else { // Left/Right Shift
            return false
        }
        
        // Проверяем флаги: нас интересует только нажатие (Shift добавлен в флаги)
        let isPressed = event.flags.contains(.maskShift)
        guard isPressed else { return false }
        
        let now = Date().timeIntervalSince1970
        let timeDiff = now - lastShiftTime
        
        // Обновляем время последнего нажатия
        lastShiftTime = now
        lastShiftKeyCode = event.keyCode
        
        // Проверяем интервал для Double Shift
        if timeDiff < doubleShiftThreshold {
            return true
        }
        
        return false
    }
    
    private func handleDoubleShift() -> EventProcessingResult {
        logDebug("Double Shift detected - manual correction requested")
        
        // 1. Пытаемся получить текст для коррекции
        var textToCorrect = getSelectedText()
        var isSelection = true
        
        if textToCorrect == nil {
            // Если нет выделения, берем текущее слово из буфера
            if let currentWord = bufferManager.getCurrentWord(), !currentWord.isEmpty {
                textToCorrect = currentWord
                isSelection = false
                logDebug("Using current word from buffer: '\(currentWord)'")
            }
        }
        
        guard let text = textToCorrect else {
            logDebug("No text to correct (selection empty and buffer empty)")
            return .default
        }
        
        // 2. Определяем целевой язык (инвертируем текущий)
        // Если текст определен как английский -> меняем на русский, и наоборот
        let detected = neuralLanguageClassifier.classifyLanguage(text).language ?? .english
        let targetLanguage: Language = (detected == .english) ? .russian : .english
        
        logDebug("Double Shift: '\(text)' (\(detected)) -> \(targetLanguage)")
        
        // 3. Формируем события для замены
        if isSelection {
            // Для выделенного текста: просто печатаем поверх (заменяет выделение)
            let events = layoutSwitcher.getKeyEventsForWord(text, inLanguage: targetLanguage)
            return EventProcessingResult(
                shouldBlockOriginalEvent: false, // Не блокируем Shift, чтобы не ломать системное поведение
                eventsToSend: events,
                detectedLanguage: targetLanguage,
                shouldSwitchLayout: true
            )
        } else {
            // Для слова из буфера: стираем и печатаем заново
            // Разделяем слово и знаки препинания
            let (cleanText, leadingPunctuation, trailingPunctuation) = separateWordAndPunctuation(text)
            logDebug("Double Shift: text='\(cleanText)', leading='\(leadingPunctuation)', trailing='\(trailingPunctuation)'")
            
            let backspaceEvents = createBackspaceEvents(count: text.count)
            let typeEvents = layoutSwitcher.getKeyEventsForWord(cleanText, inLanguage: targetLanguage)
            
            // Добавляем знаки препинания в правильном порядке
            var allEvents: [KeyboardEvent] = []
            
            // Сначала leading punctuation
            if !leadingPunctuation.isEmpty {
                logDebug("Adding leading punctuation for Double Shift: '\(leadingPunctuation)'")
                let leadingEvents = createKeyEventsForText(leadingPunctuation)
                allEvents.append(contentsOf: leadingEvents)
            }
            
            // Затем исправленное слово
            allEvents.append(contentsOf: backspaceEvents)
            allEvents.append(contentsOf: typeEvents)
            
            // Затем trailing punctuation
            if !trailingPunctuation.isEmpty {
                logDebug("Adding trailing punctuation for Double Shift: '\(trailingPunctuation)'")
                let trailingEvents = createKeyEventsForText(trailingPunctuation)
                allEvents.append(contentsOf: trailingEvents)
            }
            
            bufferManager.clearWord()
            
            logDebug("Double Shift correction: '\(text)' → converted, total events: \(allEvents.count)")
            return EventProcessingResult(
                shouldBlockOriginalEvent: false,
                eventsToSend: allEvents,
                detectedLanguage: targetLanguage,
                shouldSwitchLayout: true
            )
        }
    }
    
    private func getSelectedText() -> String? {
        // Получаем выделенный текст из активного приложения
        // Упрощенная реализация
        return nil
    }
    
    private func shouldClearBufferForNewInput(event: KeyboardEvent) -> Bool {
        // Клавиши, которые указывают на начало нового ввода
        let newInputKeyCodes: Set<Int> = [
            36, // Return/Enter
            76, // Enter (numeric keypad)
            49, // Space (добавлено как граница слова)
            48, // Tab
            53, // Escape
            123, // Left Arrow
            124, // Right Arrow
            125, // Down Arrow
            126, // Up Arrow
            115, // Home
            119, // End
            117, // Delete (forward delete)
            114, // Help
            122, // F1
            120, // F2
            99,  // F3
            118, // F4
            96,  // F5
            97,  // F6
            98,  // F7
            100, // F8
            101, // F9
            109, // F10
            103, // F11
            111, // F12
        ]
        
        // Проверяем, является ли это клавишей нового ввода
        if newInputKeyCodes.contains(event.keyCode) {
            return true
        }
        
        // Проверяем комбинации с модификаторами (Cmd, Ctrl, Alt)
        if event.flags.contains(.maskCommand) || event.flags.contains(.maskControl) || event.flags.contains(.maskAlternate) {
            logDebug("Modifier key detected (Cmd/Ctrl/Alt), clearing buffer")
            return true
        }
        
        return false
    }

    private func isSecureFocusedField() -> Bool {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )

        guard focusedResult == .success, let focusedElement = focused else {
            return false
        }

        var role: AnyObject?
        let roleResult = AXUIElementCopyAttributeValue(
            focusedElement as! AXUIElement,
            kAXRoleAttribute as CFString,
            &role
        )

        if roleResult == .success, let roleString = role as? String {
            if roleString == "AXSecureTextField" {
                return true
            }
        }

        var subrole: AnyObject?
        let subroleResult = AXUIElementCopyAttributeValue(
            focusedElement as! AXUIElement,
            kAXSubroleAttribute as CFString,
            &subrole
        )

        if subroleResult == .success, let subroleString = subrole as? String {
            if subroleString == "AXSecureTextField" {
                return true
            }
        }

        return false
    }
    
    private func createBackspaceEvents(count: Int) -> [KeyboardEvent] {
        var events: [KeyboardEvent] = []
        
        for _ in 0..<count {
            let downEvent = KeyboardEvent(
                keyCode: 51, // Backspace key code
                unicodeString: "",
                flags: [],
                timestamp: 0,
                eventType: .keyDown
            )
            let upEvent = KeyboardEvent(
                keyCode: 51,
                unicodeString: "",
                flags: [],
                timestamp: 0,
                eventType: .keyUp
            )
            events.append(downEvent)
            events.append(upEvent)
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
    
    /// Конвертирует слово в целевой язык
    private func convertWordToTargetLanguage(_ word: String, targetLanguage: Language) -> String {
        logDebug("convertWordToTargetLanguage: word='\(word)', target=\(targetLanguage)")
        
        // Определяем, в какой раскладке находится исходное слово
        let isEnglishWord = isEnglishWordInRussianLayout(word)
        let isRussianWord = isRussianWordInEnglishLayout(word)
        
        logDebug("Word analysis: isEnglishWord=\(isEnglishWord), isRussianWord=\(isRussianWord)")
        
        // Проверяем, нужно ли конвертировать слово
        // 1. Если слово уже в правильной раскладке для целевого языка, возвращаем как есть
        //    - Для английского языка: слово должно быть английским словом в английской раскладке
        //    - Для русского языка: слово должно быть русским словом в русской раскладке
        // 2. isEnglishWordInRussianLayout означает "английское слово в русской раскладке"
        //    - Если целевой язык английский, нужно конвертировать в английскую раскладку
        // 3. isRussianWordInEnglishLayout означает "русское слово в английской раскладке"
        //    - Если целевой язык русский, нужно конвертировать в русскую раскладку
        
        // Проверяем, состоит ли слово из букв целевого языка
        let isWordInTargetLanguageLayout: Bool
        switch targetLanguage {
        case .english:
            // Для английского языка: слово должно состоять из английских букв
            let englishLetters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
            let wordCharacterSet = CharacterSet(charactersIn: word)
            isWordInTargetLanguageLayout = englishLetters.isSuperset(of: wordCharacterSet)
        case .russian:
            // Для русского языка: слово должно состоять из русских букв
            let russianLetters = CharacterSet(charactersIn: "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ")
            let wordCharacterSet = CharacterSet(charactersIn: word)
            isWordInTargetLanguageLayout = russianLetters.isSuperset(of: wordCharacterSet)
        }
        
        logDebug("Word in target language layout: \(isWordInTargetLanguageLayout)")
        
        // Если слово уже в правильной раскладке для целевого языка, возвращаем как есть
        if isWordInTargetLanguageLayout {
            logDebug("Word is already in target language layout, returning as-is")
            return word
        }
        
        // Конвертируем с помощью KeyMapper
        let converted = KeyMapper.shared.convertString(word)
        logDebug("KeyMapper conversion: '\(word)' → '\(converted)'")
        
        // Проверяем результат конвертации
        if converted == word {
            logDebug("No conversion needed or conversion failed")
            return word
        }
        
        return converted
    }
}

// MARK: - Вспомогательные структуры

/// Конфигурация обработки событий
struct ProcessingConfig {
    let enableTypoCorrection: Bool
    let enableAutoComplete: Bool
    let enableDoubleShift: Bool
    let minWordLengthForSwitch: Int
    let maxWordLength: Int
    let wordExceptions: Set<String>
    let confidenceThreshold: Double
    
    static let `default` = ProcessingConfig(
        enableTypoCorrection: false, // Отключаем для тестирования
        enableAutoComplete: false,   // Отключаем для тестирования
        enableDoubleShift: false,    // Отключаем для тестирования
        minWordLengthForSwitch: 3,   // Уменьшаем для лучшего переключения раскладки
        maxWordLength: 50,           // Максимальная длина слова для обработки
        wordExceptions: ["a", "i", "to", "in", "on", "at", "the", "and", "but", "or"],
        confidenceThreshold: 0.8     // Повышаем порог уверенности
    )
    
    var description: String {
        return """
        ProcessingConfig(
          enableTypoCorrection: \(enableTypoCorrection),
          enableAutoComplete: \(enableAutoComplete),
          enableDoubleShift: \(enableDoubleShift),
          minWordLengthForSwitch: \(minWordLengthForSwitch),
          maxWordLength: \(maxWordLength),
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
    var isSecureField: Bool = false
    var lastLayoutSwitchTime: Date?
    var lastLayoutSwitchByApp: Bool = false // true if BabylonFish switched, false if user switched
    var postSwitchBuffer: [String] = [] // Words typed after BabylonFish switched layout
    var postSwitchWordCount: Int = 0 // Number of words typed after switch
    var expectedLayoutLanguage: Language? // What language we expect user to type in after switch
    
    var description: String {
        let timeSinceSwitch = lastLayoutSwitchTime.map { "\(Date().timeIntervalSince($0))s ago" } ?? "never"
        let switchBy = lastLayoutSwitchByApp ? "BabylonFish" : "user"
        let expectedLang = expectedLayoutLanguage?.rawValue ?? "none"
        return """
        ProcessingContext(
          app: \(processName ?? "unknown"),
          bundleId: \(bundleIdentifier ?? "unknown"),
          type: \(applicationType),
          lastLanguage: \(String(describing: lastDetectedLanguage)),
          lastEvent: \(lastEventTime.timeIntervalSinceNow * -1)s ago,
          lastSwitch: \(timeSinceSwitch) by \(switchBy),
          postSwitchWords: \(postSwitchWordCount),
          expectedLayout: \(expectedLang)
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
