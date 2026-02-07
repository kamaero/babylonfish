import Foundation
import Cocoa
import Carbon

/// Обрабатывает события клавиатуры
class EventProcessor {
    private let bufferManager: BufferManager
    private let layoutSwitcher: LayoutSwitcher
    private let languageDetector: LanguageDetector
    private let contextAnalyzer: ContextAnalyzer
    private let suggestionEngine: SuggestionEngine?
    
    // Состояние
    private var isProcessing = false
    private var lastBoundaryAt: TimeInterval = 0
    var boundaryDebounce: TimeInterval = 0.12
    
    // Double Shift Detection
    private var lastShiftTime: TimeInterval = 0
    var doubleShiftThreshold: TimeInterval = 0.3
    
    // Undo Learning
    private struct LastSwitchInfo {
        let timestamp: TimeInterval
        let targetLang: Language
        let enWord: String
        let ruWord: String
        let length: Int
        let insertedLength: Int // New: length of inserted text
        let switchedLayout: Bool // New: whether layout was switched
    }
    private var lastSwitch: LastSwitchInfo?
    private var consecutiveBackspaceCount = 0
    
    weak var suggestionWindow: SuggestionWindow?
    private var currentSuggestion: String?
    
    var autoSwitchEnabled: Bool = true
    var autoCorrectTyposEnabled: Bool = true
    var onDoubleShift: (() -> Void)?
    
    init(bufferManager: BufferManager, 
         layoutSwitcher: LayoutSwitcher,
         languageDetector: LanguageDetector,
         contextAnalyzer: ContextAnalyzer,
         suggestionEngine: SuggestionEngine? = nil) {
        self.bufferManager = bufferManager
        self.layoutSwitcher = layoutSwitcher
        self.languageDetector = languageDetector
        self.contextAnalyzer = contextAnalyzer
        self.suggestionEngine = suggestionEngine
    }
    
    /// Обрабатывает изменение модификаторов
    func handleFlagsChanged(_ event: CGEvent) {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Проверяем Left Shift (KeyCode 56)
        if keyCode == 56 {
            if flags.contains(.maskShift) {
                let now = Date().timeIntervalSince1970
                if now - lastShiftTime < doubleShiftThreshold {
                    // Double Shift Detected!
                    handleDoubleShift()
                }
                lastShiftTime = now
            }
        }
    }
    
    /// Обрабатывает нажатие клавиши
    func handleKeyDown(_ event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) == 1
        
        // Игнорируем если нажаты Command или Control
        if event.flags.contains(.maskCommand) || event.flags.contains(.maskControl) {
            bufferManager.clear()
            consecutiveBackspaceCount = 0
            return Unmanaged.passRetained(event)
        }

        // Обрабатываем специальные клавиши
        switch keyCode {
        case 51: // Backspace
            consecutiveBackspaceCount += 1
            checkUndoLearning()
            
            if !bufferManager.isEmpty {
                bufferManager.removeLast()
            }
            updateSuggestion()
            return Unmanaged.passRetained(event)
            
        case 123: // Left Arrow
            // Проверяем, нужно ли отменить последнее действие
            if let ls = lastSwitch, Date().timeIntervalSince1970 - ls.timestamp < 3.0 {
                // Если прошло меньше 3 секунд, пробуем отменить
                undoLastSwitch()
                // Поглощаем событие стрелки, так как мы уже всё исправили
                return nil
            }
            
            // Иначе стандартное поведение
            bufferManager.clear()
            clearSuggestion()
            return Unmanaged.passRetained(event)

        case 53, 48, 124...126: // Esc, Tab, Other Arrows
            bufferManager.clear()
            clearSuggestion()
            return Unmanaged.passRetained(event)
            
        default:
            break
        }
        
        if isAutoRepeat { return Unmanaged.passRetained(event) }
        
        // Проверяем secure field
        if contextAnalyzer.isSecureField() {
            bufferManager.clear()
            return Unmanaged.passRetained(event)
        }
        
        // Границы слов: Space (49) или Enter (36)
        if keyCode == 49 || keyCode == 36 {
            if keyCode == 36, let suggestion = currentSuggestion {
                applySuggestion(suggestion)
                return nil
            }
            clearSuggestion()

            // Word boundary
            let now = Date().timeIntervalSince1970
            if now - lastBoundaryAt < boundaryDebounce { return Unmanaged.passRetained(event) }
            lastBoundaryAt = now
            
            // Обрабатываем буфер перед очисткой
            var consumed = false
            if !bufferManager.isEmpty {
                logDebug("Word boundary (Space/Enter). Processing buffer...")
                consumed = processBuffer(triggerKeyCode: keyCode)
            }
            
            bufferManager.clear()
            
            if consumed {
                return nil
            } else {
                return Unmanaged.passRetained(event)
            }
        }
        
        // Обычные символы
        bufferManager.addKey(code: keyCode, flags: event.flags)
        
        // Debug информация
        if let chars = KeyMapper.shared.getChars(for: keyCode) {
            logDebug("Key: \(keyCode) -> en:'\(chars.en)' ru:'\(chars.ru)'")
        }
        
        updateSuggestion()
        
        return Unmanaged.passRetained(event)
    }
    
    /// Обрабатывает буфер для определения языка и переключения
    private func processBuffer(triggerKeyCode: Int? = nil) -> Bool {
        // Проверяем контекст
        if contextAnalyzer.shouldDisableSwitching() {
            logDebug("processBuffer: context requires disabling switching")
            return false
        }
        if !autoSwitchEnabled {
            logDebug("processBuffer: skipped (autoSwitchEnabled=false)")
            return false
        }
        if isProcessing {
            logDebug("processBuffer: skipped (isProcessing=true)")
            return false
        }
        
        let filteredCodes = bufferManager.filteredLetterCodes()
        
        logDebug("Buffer count: \(bufferManager.count), Filtered count: \(filteredCodes.count)")
        
        guard !filteredCodes.isEmpty else {
            logDebug("Not enough filtered characters for detection (0)")
            return false
        }
        
        // Детекция языка
        if let detectedLang = languageDetector.detectLanguage(for: filteredCodes) {
            logDebug("Language detected: \(detectedLang)")
            
            // Проверяем текущую раскладку
            guard let currentID = layoutSwitcher.getCurrentInputSourceId() else {
                logDebug("Could not get current input source ID.")
                return false
            }
            
            let isCurrentRussian = currentID.contains("Russian")
            let isCurrentEnglish = currentID.contains("US") || currentID.contains("English") || currentID.contains("ABC")
            
            if detectedLang == .russian && isCurrentRussian {
                logDebug("Detected Russian, but already on Russian layout. Ignoring.")
                return false
            }
            if detectedLang == .english && isCurrentEnglish {
                logDebug("Detected English, but already on English layout. Ignoring.")
                return false
            }
            
            logDebug("Switching layout to \(detectedLang)...")
            switchAndReplace(targetLang: detectedLang, triggerKeyCode: triggerKeyCode)
            return true
        }
        
        // Автокоррекция в текущем языке
        if autoCorrectTyposEnabled, let currentID = layoutSwitcher.getCurrentInputSourceId() {
            let isCurrentRussian = currentID.contains("Russian")
            let isCurrentEnglish = currentID.contains("US") || currentID.contains("English") || currentID.contains("ABC")
            
            var currentLang: Language?
            if isCurrentRussian { currentLang = .russian }
            else if isCurrentEnglish { currentLang = .english }
            
            if let lang = currentLang {
                // Строим текущее слово
                var currentWord = ""
                for info in bufferManager.snapshot {
                    if let chars = KeyMapper.shared.getChars(for: info.code) {
                        currentWord += (lang == .russian) ? chars.ru : chars.en
                    }
                }
                
                // Просим предложить исправление
                if let correction = languageDetector.suggestCorrection(for: currentWord, language: lang) {
                    logDebug("Auto-correction triggered: \(currentWord) -> \(correction)")
                    replaceWord(originalLength: bufferManager.count, newText: correction, triggerKeyCode: triggerKeyCode)
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Переключает раскладку и заменяет слово
    private func switchAndReplace(targetLang: Language, triggerKeyCode: Int?) {
        isProcessing = true
        defer { isProcessing = false }
        
        let bufferSnapshot = bufferManager.snapshot
        
        // Строим строки для обучения
        var enWord = ""
        var ruWord = ""
        for info in bufferSnapshot {
            if let chars = KeyMapper.shared.getChars(for: info.code) {
                enWord += chars.en
                ruWord += chars.ru
            }
        }
        
        languageDetector.learnDecision(target: targetLang, enWord: enWord, ruWord: ruWord)
        
        // Запоминаем для undo
        let undoLength = bufferSnapshot.count + (triggerKeyCode != nil ? 1 : 0)
        let insertedLength = (targetLang == .russian ? ruWord.count : enWord.count) + (triggerKeyCode != nil ? 1 : 0)
        
        lastSwitch = LastSwitchInfo(
            timestamp: Date().timeIntervalSince1970,
            targetLang: targetLang,
            enWord: enWord,
            ruWord: ruWord,
            length: undoLength,
            insertedLength: insertedLength,
            switchedLayout: true
        )
        consecutiveBackspaceCount = 0
        
        logDebug("Executing switchAndReplace -> \(targetLang)")
        
        // Очищаем внутренний буфер
        bufferManager.clear()
        
        // Переключаем раскладку
        let targetIDPart = (targetLang == .russian) ? "Russian" : "English"
        logDebug("Attempting to switch input source to one containing: \(targetIDPart)")
        
        _ = layoutSwitcher.switchToInputSource(containing: targetIDPart)
        
        // Удаляем символы
        layoutSwitcher.deleteCharacters(bufferSnapshot.count)
        
        // Перепечатываем
        layoutSwitcher.retypeBuffer(bufferSnapshot)
        
        // Восстанавливаем триггерную клавишу если была
        if let trigger = triggerKeyCode {
            logDebug("Restoring trigger key: \(trigger)")
            layoutSwitcher.sendKey(trigger)
        }
    }
    
    /// Заменяет слово на исправленное
    private func replaceWord(originalLength: Int, newText: String, triggerKeyCode: Int?) {
        isProcessing = true
        defer { isProcessing = false }
        
        // Очищаем внутренний буфер
        bufferManager.clear()
        
        logDebug("Executing replaceWord -> \(newText)")
        
        // Удаляем символы
        layoutSwitcher.deleteCharacters(originalLength)
        
        // Вставляем исправление
        pasteString(newText)
        
        // Восстанавливаем триггерную клавишу если была
        if let trigger = triggerKeyCode {
            logDebug("Restoring trigger key: \(trigger)")
            layoutSwitcher.sendKey(trigger)
        }
    }
    
    /// Вставляет строку через буфер обмена
    private func pasteString(_ str: String) {
        let pasteboard = NSPasteboard.general
        let old = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(str, forType: .string)
        
        // Command+V
        layoutSwitcher.sendKey(9, flags: .maskCommand)
        
        // Восстанавливаем буфер обмена после задержки
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let old = old {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
    }
    
    /// Отменяет последнее переключение/замену
    private func undoLastSwitch() {
        guard let ls = lastSwitch else { return }
        
        logDebug("Undo Requested via Left Arrow! Reverting...")
        
        isProcessing = true
        defer { isProcessing = false }
        
        // 1. Определяем, что сейчас на экране
        // Если мы переключились на targetLang, значит сейчас там слово в targetLang (исправленное или конвертированное)
        // Но если это была автокоррекция (targetLang не менялся, но текст менялся)
        
        // Сценарий 1: Было переключение раскладки (switchAndReplace)
        // ls.targetLang - это язык, НА КОТОРЫЙ мы переключились.
        // ls.ruWord / ls.enWord - исходные слова.
        
        // Например: набрали "ghb" (EN) -> поняли что это RU "при" -> переключили на RU -> напечатали "при"
        // ls.targetLang = .russian
        // ls.enWord = "ghb"
        // ls.ruWord = "при"
        // На экране: "при"
        // Нужно: удалить "при", переключить на EN, напечатать "ghb"
        
        // Сценарий 2: Была автокоррекция (replaceWord)
        // Мы не сохраняли replaceWord в lastSwitch (надо проверить).
        // В текущем коде replaceWord НЕ сохраняет в lastSwitch. Исправим это.
        
        // 2. Удаляем текущее слово
        // Длина слова на экране может отличаться от ls.length (исходной длины).
        // Нам нужно знать длину ТОГО, ЧТО МЫ ВСТАВИЛИ.
        // Добавим insertedLength в LastSwitchInfo.
        
        layoutSwitcher.deleteCharacters(ls.insertedLength)
        
        // 3. Восстанавливаем раскладку (если менялась)
        // Если targetLang == .russian, значит мы переключились на RU. Надо вернуть EN.
        // Если targetLang == .english, значит мы переключились на EN. Надо вернуть RU.
        
        // Но может быть мы не переключались (автокоррекция)?
        // Добавим флаг switchedLayout в LastSwitchInfo.
        
        if ls.switchedLayout {
            let restoreID = (ls.targetLang == .russian) ? "English" : "Russian"
            logDebug("Restoring layout to \(restoreID)")
            _ = layoutSwitcher.switchToInputSource(containing: restoreID)
        }
        
        // 4. Печатаем исходное слово
        // Какое слово было исходным?
        // Если targetLang == .russian (значит исходно было EN, мы решили что это RU), то исходное - enWord.
        // Если targetLang == .english (значит исходно было RU, мы решили что это EN), то исходное - ruWord.
        
        // В случае автокоррекции (например te -> the):
        // targetLang = текущий язык.
        // enWord/ruWord = исходное слово "te".
        // Мы хотим вернуть "te".
        
        var originalText = ""
        if ls.switchedLayout {
             if ls.targetLang == .russian {
                 originalText = ls.enWord
             } else {
                 originalText = ls.ruWord
             }
        } else {
             // Автокоррекция.
             // Нам нужно знать, на каком языке мы были.
             // В ls.targetLang мы сохраним язык, на котором была коррекция.
             if ls.targetLang == .russian {
                 originalText = ls.ruWord
             } else {
                 originalText = ls.enWord
             }
        }
        
        logDebug("Restoring original text: \(originalText)")
        pasteString(originalText) // Используем pasteString, так как retypeBuffer требует KeyInfo
        
        // 5. Unlearn
        logDebug("Unlearning decision...")
        languageDetector.unlearnDecision(target: ls.targetLang, enWord: ls.enWord, ruWord: ls.ruWord)
        
        // 6. Reset
        lastSwitch = nil
    }
    
    /// Проверяет undo learning (triggered by Backspace)
    private func checkUndoLearning() {
        guard let ls = lastSwitch else { return }
        
        // Таймаут (например, 15 секунд)
        if Date().timeIntervalSince1970 - ls.timestamp > 15 {
            lastSwitch = nil
            return
        }
        
        if consecutiveBackspaceCount >= ls.length {
            logDebug("Undo Learning Triggered! Unlearning \(ls.enWord)/\(ls.ruWord)")
            languageDetector.unlearnDecision(target: ls.targetLang, enWord: ls.enWord, ruWord: ls.ruWord)
            
            lastSwitch = nil
        }
    }
    
    /// Обновляет подсказку
    private func updateSuggestion() {
        guard let window = suggestionWindow else { return }
        
        let filteredCodes = bufferManager.filteredLetterCodes()
        
        if let suggestion = suggestionEngine?.getSuggestion(for: filteredCodes) {
            currentSuggestion = suggestion
            DispatchQueue.main.async {
                let loc = NSEvent.mouseLocation
                let point = CGPoint(x: loc.x, y: loc.y - 40)
                window.showCompletion(suggestion, at: point)
            }
        } else {
            clearSuggestion()
        }
    }
    
    /// Очищает подсказку
    private func clearSuggestion() {
        currentSuggestion = nil
        DispatchQueue.main.async {
            self.suggestionWindow?.hideSuggestion()
        }
    }
    
    /// Применяет подсказку
    private func applySuggestion(_ text: String) {
        logDebug("Applying suggestion: \(text)")
        
        // Определяем, нужно ли переключать раскладку
        let isRussian = text.contains { "абвгдеёжзийклмнопрстуфхцчшщъыьэюя".contains(String($0).lowercased()) }
        
        // Проверяем текущую раскладку
        if let currentID = layoutSwitcher.getCurrentInputSourceId() {
             let isCurrentRussian = currentID.contains("Russian")
             if isRussian && !isCurrentRussian {
                 _ = layoutSwitcher.switchToInputSource(containing: "Russian")
             } else if !isRussian && isCurrentRussian {
                 _ = layoutSwitcher.switchToInputSource(containing: "English")
             }
        }
        
        // Удаляем набранные символы
        let deleteCount = bufferManager.count
        logDebug("Deleting \(deleteCount) chars for suggestion...")
        for _ in 0..<deleteCount {
            layoutSwitcher.sendKey(51) // Backspace
            usleep(500)
        }
        
        // Вставляем новый текст
        pasteString(text)
        
        // Очищаем буфер
        bufferManager.clear()
        clearSuggestion()
    }
    
    /// Обрабатывает двойное нажатие Shift
    private func handleDoubleShift() {
        logDebug("Double Shift detected! calling handler...")
        onDoubleShift?()
    }
}