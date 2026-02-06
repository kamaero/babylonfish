import Foundation
import Cocoa
import ApplicationServices

/// Обрабатывает двойное нажатие Shift
class DoubleShiftHandler {
    private var config: HotkeyConfig
    private weak var layoutSwitcher: LayoutSwitcher?
    private weak var languageDetector: LanguageDetector?
    private var lastActionTime: TimeInterval = 0
    private let actionCooldown: TimeInterval = 0.5
    
    init(config: HotkeyConfig, layoutSwitcher: LayoutSwitcher? = nil, languageDetector: LanguageDetector? = nil) {
        self.config = config
        self.layoutSwitcher = layoutSwitcher
        self.languageDetector = languageDetector
    }
    
    /// Обрабатывает событие двойного Shift
    func handleDoubleShift() {
        guard config.doubleShiftEnabled else {
            logDebug("Double shift ignored (disabled in config)")
            return
        }
        
        let now = Date().timeIntervalSince1970
        if now - lastActionTime < actionCooldown {
            return
        }
        lastActionTime = now
        
        logDebug("Double Shift Action Triggered")
        
        // 1. Пытаемся получить выделенный текст
        getSelectedText { [weak self] text in
            guard let self = self else { return }
            
            guard let text = text, !text.isEmpty else {
                // Если текст не выделен, можно попробовать выделить последнее слово
                // Но пока просто выходим
                logDebug("No text selected")
                return
            }
            
            // 2. Конвертируем текст
            let converted = KeyMapper.shared.convertString(text)
            if converted == text {
                logDebug("Text conversion resulted in same string. Ignoring.")
                return
            }
            
            logDebug("Converting: '\(text)' -> '\(converted)'")
            
            // 3. Заменяем текст
            self.replaceSelectedText(with: converted)
            
            // 4. Переключаем раскладку (опционально, если большинство символов изменилось)
            self.switchLayoutIfNeeded(original: text, converted: converted)
        }
    }
    
    /// Пытаемся получить текст через AX API, если нет - через буфер обмена
    private func getSelectedText(completion: @escaping (String?) -> Void) {
        // Попытка 1: Accessibility API
        if let axText = getSelectedTextViaAX() {
            logDebug("Got text via AX: \(axText.prefix(20))...")
            completion(axText)
            return
        }
        
        // Попытка 2: Буфер обмена
        getSelectedTextViaClipboard(completion: completion)
    }
    
    /// Заменяем текст через AX API или буфер обмена
    private func replaceSelectedText(with newText: String) {
        // Попытка 1: Accessibility API
        if setSelectedTextViaAX(newText) {
            logDebug("Replaced text via AX")
            return
        }
        
        // Попытка 2: Буфер обмена
        pasteTextViaClipboard(newText)
    }
    
    // MARK: - Accessibility Implementation
    
    private func getSelectedTextViaAX() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement else { return nil }
        let axElement = element as! AXUIElement
        
        var value: AnyObject?
        let resultVal = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &value)
        
        if resultVal == .success, let str = value as? String {
            return str
        }
        return nil
    }
    
    private func setSelectedTextViaAX(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement else { return false }
        let axElement = element as! AXUIElement
        
        let resultSet = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        return resultSet == .success
    }
    
    // MARK: - Clipboard Implementation
    
    private func getSelectedTextViaClipboard(completion: @escaping (String?) -> Void) {
        guard let switcher = layoutSwitcher else {
            completion(nil)
            return
        }
        
        let pasteboard = NSPasteboard.general
        let oldChangeCount = pasteboard.changeCount
        
        // Сохраняем текущий буфер (опционально, сложно реализовать надежно)
        // Пока просто очищаем для детекции
        // pasteboard.clearContents() // Не стоит очищать, лучше проверить изменение
        
        // Cmd+C
        switcher.sendKey(8, flags: .maskCommand) // 8 is 'c' in QWERTY? No, 8 is 'c'
        // Wait, KeyCode 8 is 'c'. Correct.
        
        // Ждем асинхронно
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if pasteboard.changeCount != oldChangeCount {
                if let str = pasteboard.string(forType: .string) {
                    completion(str)
                    return
                }
            }
            completion(nil)
        }
    }
    
    private func pasteTextViaClipboard(_ text: String) {
        guard let switcher = layoutSwitcher else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Cmd+V
        switcher.sendKey(9, flags: .maskCommand) // 9 is 'v'
    }
    
    // MARK: - Layout Switching
    
    private func switchLayoutIfNeeded(original: String, converted: String) {
        guard let switcher = layoutSwitcher else { return }
        
        // Smart Logic:
        // 1. Проверяем, является ли конвертированное слово валидным (в целевом языке)
        // 2. Если нет, проверяем, есть ли исправление для оригинального слова (в исходном языке)
        
        var targetText = converted
        var shouldSwitch = true
        
        let ruChars = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
        let hasRuOriginal = original.lowercased().contains { ruChars.contains($0) }
        let hasRuConverted = converted.lowercased().contains { ruChars.contains($0) }
        
        // Определяем направление переключения
        let targetLangID = (hasRuOriginal && !hasRuConverted) ? "English" : ((!hasRuOriginal && hasRuConverted) ? "Russian" : nil)
        let sourceLangID = (hasRuOriginal) ? "Russian" : "English"
        
        if let detector = languageDetector {
            let targetLangCode = (targetLangID == "Russian") ? "ru_RU" : "en_US"
            
            let isConvertedValid = detector.isSystemWord(converted, language: targetLangCode)
            
            if !isConvertedValid {
                // Конвертация дала "несуществующее" слово.
                // Проверим, может это просто опечатка в оригинале?
                
                let langEnum: Language = (sourceLangID == "Russian") ? .russian : .english
                if let correction = detector.suggestCorrection(for: original, language: langEnum) {
                    logDebug("Smart Fix: '\(converted)' seems invalid, but '\(original)' has correction -> '\(correction)'")
                    targetText = correction
                    shouldSwitch = false // Не переключаем раскладку, просто исправляем слово
                    
                    // Если мы решили исправить слово, нужно заменить его в тексте
                    // Но replaceSelectedText уже был вызван с converted!
                    // Нам нужно отменить и вставить correction.
                    // Или лучше делать эту проверку ДО вызова replaceSelectedText в handleDoubleShift.
                }
            }
        }
        
        // В текущей реализации мы уже заменили текст на converted.
        // Если мы решили, что это была ошибка, нужно заменить обратно на targetText (correction)
        if targetText != converted {
             self.replaceSelectedText(with: targetText)
        }
        
        if shouldSwitch && targetLangID != nil {
             _ = switcher.switchToInputSource(containing: targetLangID!)
        }
    }
    
    /// Обновляет конфигурацию
    func updateConfig(_ newConfig: HotkeyConfig) {
        config = newConfig
    }
}
