import Foundation
import Cocoa

/// Детектирует язык на основе нажатых клавиш
class LanguageDetector {
    private let spellChecker = NSSpellChecker.shared
    private let learningManager: LearningManager
    
    init(learningManager: LearningManager) {
        self.learningManager = learningManager
    }
    
    /// Детектирует язык для последовательности кодов клавиш
    func detectLanguage(for keyCodes: [Int]) -> Language? {
        guard keyCodes.count >= 1 else { return nil }
        
        var enString = ""
        var ruString = ""
        
        for code in keyCodes {
            if let chars = KeyMapper.shared.getChars(for: code) {
                enString += chars.en
                ruString += chars.ru
            }
        }
        
        logDebug("Analyzing buffer: EN='\(enString)', RU='\(ruString)'")
        
        let enLower = enString.lowercased()
        let ruLower = ruString.lowercased()
        let count = keyCodes.count
        
        // 1. Проверяем общие слова (быстрый путь)
        if LanguageConstants.commonRuShortWords.contains(ruLower) {
            logDebug("Common Russian Short Word Match: \(ruLower)")
            return .russian
        }
        
        if LanguageConstants.commonEnglishWords.contains(enLower) {
            logDebug("Common English Word Match: \(enLower)")
            return .english
        }
        
        // 2. Проверяем исключения (игнорируемые слова)
        if learningManager.isWordIgnored(enLower) || learningManager.isWordIgnored(ruLower) {
            logDebug("Ignored word detected: \(enLower)/\(ruLower)")
            return nil
        }
        
        // 3. Проверяем системный словарь
        let isRuValid = isSystemWord(ruLower, language: "ru_RU")
        let isEnValid = isSystemWord(enLower, language: "en_US")
        
        if isRuValid && !isEnValid {
            logDebug("System Dictionary: RU Valid ('\(ruLower)'), EN Invalid -> RU")
            return .russian
        }
        
        if isEnValid && !isRuValid {
            logDebug("System Dictionary: EN Valid ('\(enLower)'), RU Invalid -> EN")
            return .english
        }
        
        if isRuValid && isEnValid {
            logDebug("System Dictionary: Both Valid ('\(ruLower)' / '\(enLower)'). Falling back to bigrams/heuristics.")
        }
        
        // 4. Проверяем односимвольные и короткие слова
        if count == 1 {
            if LanguageConstants.ruSingletonLetters.contains(ruLower) || LanguageConstants.commonRuShortWords.contains(ruLower) {
                return .russian
            }
        }
        if count == 2 {
            if LanguageConstants.commonRuShortWords.contains(ruLower) {
                return .russian
            }
            if LanguageConstants.commonEnglishWords.contains(enLower) {
                return .english
            }
        }
        
        // 5. Проверяем "невозможные" паттерны
        for pattern in LanguageConstants.impossibleRuInEnKeys where pattern.count >= 3 {
            if enString.contains(pattern) {
                logDebug("Detected Impossible Pattern (RU intent): \(pattern) in \(enString)")
                return .russian
            }
        }
        
        for pattern in LanguageConstants.impossibleEnInRuKeys where pattern.count >= 4 {
            if ruString.contains(pattern) {
                logDebug("Detected Impossible Pattern (EN intent): \(pattern) in \(ruString)")
                return .english
            }
        }
        
        // 6. Проверяем слова, выученные пользователем
        if learningManager.getEnglishWordCount(enLower) >= 2 {
            logDebug("User Learned Word (EN): \(enLower)")
            return .english
        }
        if learningManager.getRussianWordCount(ruLower) >= 2 {
            logDebug("User Learned Word (RU): \(ruLower)")
            return .russian
        }
        
        // 7. Эвристика: подсчет биграмм
        let enScore = countBigrams(enString, dictionary: LanguageConstants.commonEnBigrams)
        let ruScore = countBigrams(ruString, dictionary: LanguageConstants.commonRuBigrams)
        
        logDebug("Scores: EN=\(enScore), RU=\(ruScore)")
        
        if ruScore > 0 && enScore == 0 {
             logDebug("Score Analysis (Clear Winner): RU:\(ruScore) vs EN:0 -> RU")
             return .russian
        }
        
        if enScore > 0 && ruScore == 0 {
             logDebug("Score Analysis (Clear Winner): EN:\(enScore) vs RU:0 -> EN")
             return .english
        }
        
        if ruScore > enScore + 1 {
            logDebug("Score Analysis: RU:\(ruScore) vs EN:\(enScore) for keys: \(keyCodes) -> RU")
            return .russian
        } else if enScore > ruScore + 1 {
            logDebug("Score Analysis: RU:\(ruScore) vs EN:\(enScore) for keys: \(keyCodes) -> EN")
            return .english
        }
        
        return nil
    }
    
    /// Предлагает исправление для слова в указанном языке
    func suggestCorrection(for word: String, language: Language) -> String? {
        let langCode = (language == .russian) ? "ru_RU" : "en_US"
        
        // Проверяем, является ли слово уже правильным
        if isSystemWord(word, language: langCode) {
            return nil
        }
        
        // Получаем лучшее исправление
        let range = NSRange(location: 0, length: word.utf16.count)
        let correction = spellChecker.correction(forWordRange: range, in: word, language: langCode, inSpellDocumentWithTag: 0)
        
        if let correction = correction, correction != word {
            logDebug("Correction found for '\(word)' (\(langCode)): \(correction)")
            return correction
        }
        
        return nil
    }
    
    /// Запоминает решение пользователя
    func learnDecision(target: Language, enWord: String, ruWord: String) {
        learningManager.learnDecision(target: target, enWord: enWord, ruWord: ruWord)
    }
    
    /// Отменяет решение пользователя (undo learning)
    func unlearnDecision(target: Language, enWord: String, ruWord: String) {
        learningManager.unlearnDecision(target: target, enWord: enWord, ruWord: ruWord)
    }
    
    /// Проверяет, есть ли слово в системном словаре
    private func isSystemWord(_ word: String, language: String) -> Bool {
        let range = spellChecker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return range.location == NSNotFound
    }
    
    /// Подсчитывает биграммы
    private func countBigrams(_ text: String, dictionary: Set<String>) -> Int {
        var count = 0
        let chars = Array(text)
        if chars.count < 2 { return 0 }
        
        for i in 0..<(chars.count - 1) {
            let bigram = String(chars[i...i+1])
            if dictionary.contains(bigram) {
                var score = 1
                
                // Бонус для начала слова (первые 2 биграммы)
                if i < 2 {
                    score += 2 // Всего 3
                }
                
                count += score
            }
        }
        return count
    }
}