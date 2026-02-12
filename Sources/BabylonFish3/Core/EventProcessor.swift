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
            return EventProcessingResult(
                shouldBlockOriginalEvent: false,
                eventsToSend: [],
                detectedLanguage: nil,
                shouldSwitchLayout: false
            )
        }
        
        logDebug("Processing word: '\(word)'")
        
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
    
    private func shouldSwitchLayout(for word: String, detectedLanguage: Language) -> Bool {
        // 1. Проверяем минимальную длину слова
        guard word.count >= config.minWordLengthForSwitch else { return false }
        
        // 2. Проверяем исключения
        if config.wordExceptions.contains(word.lowercased()) {
            return false
        }
        
        // 3. Получаем текущую раскладку
        guard let currentLayout = layoutSwitcher.getCurrentLayout() else {
            return false
        }
        
        // 4. Определяем язык текущей раскладки
        guard let currentLayoutLanguage = layoutSwitcher.getLanguage(for: currentLayout) else {
            return false
        }
        
        // 5. Сравниваем языки
        if currentLayoutLanguage == detectedLanguage {
            return false
        }
        
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
            return true
        }
        
        return false
    }
    
    private func getDetectionConfidence(for word: String, language: Language) -> Double {
        // Проверяем биграммы/триграммы для раннего определения
        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanWord.count >= 2 {
            let bigram = String(cleanWord.prefix(2)).lowercased()
            if language == .russian && isRussianBigram(bigram) {
                return 1.0
            }
            if language == .english && isEnglishBigram(bigram) {
                return 1.0
            }
        }
        
        if cleanWord.count >= 3 {
            let trigram = String(cleanWord.prefix(3)).lowercased()
            if language == .russian && isRussianTrigram(trigram) {
                return 1.0
            }
            if language == .english && isEnglishTrigram(trigram) {
                return 1.0
            }
        }
        
        // Используем нейросеть для оценки уверенности
        let result = neuralLanguageClassifier.classifyLanguage(
            cleanWord,
            context: ClassificationContext(
                applicationType: currentContext.applicationType,
                previousLanguage: currentContext.lastDetectedLanguage
            )
        )
        
        if result.language == language {
            return result.confidence
        }
        
        return 0.0
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
        return word.unicodeScalars.contains { separators.contains($0) }
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
            let backspaceEvents = createBackspaceEvents(count: word.count)
            logDebug("Created \(backspaceEvents.count) backspace events for word length \(word.count)")
            
            // 6. Печатаем исправленное слово
            let correctedWord = cleanWord // Будет конвертировано в getKeyEventsForWord
            let correctionEvents = layoutSwitcher.getKeyEventsForWord(correctedWord, inLanguage: targetLanguage)
            logDebug("Created \(correctionEvents.count) correction events")
            
            // 7. Добавляем знаки препинания (если есть) в правильном порядке
            var allEvents: [KeyboardEvent] = []
            
            // Сначала leading punctuation (если есть)
            if !leadingPunctuation.isEmpty {
                logDebug("Adding leading punctuation: '\(leadingPunctuation)'")
                let leadingEvents = createKeyEventsForText(leadingPunctuation)
                allEvents.append(contentsOf: leadingEvents)
            }
            
            // Затем исправленное слово
            allEvents.append(contentsOf: backspaceEvents)
            allEvents.append(contentsOf: correctionEvents)
            
            // Затем trailing punctuation (если есть)
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
        enableTypoCorrection: false, // Отключаем для тестирования
        enableAutoComplete: false,   // Отключаем для тестирования
        enableDoubleShift: false,    // Отключаем для тестирования
        minWordLengthForSwitch: 4,   // Увеличиваем для уменьшения false positives
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
