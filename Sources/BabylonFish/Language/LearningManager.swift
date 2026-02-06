import Foundation

/// Управляет обучением и исключениями
class LearningManager {
    private let enUserKey = "bf_user_words_en"
    private let ruUserKey = "bf_user_words_ru"
    private let ignoredWordsKey = "bf_ignored_words"
    private var userWordsEN: [String: Int] = [:]
    private var userWordsRU: [String: Int] = [:]
    private var ignoredWords: Set<String> = []
    
    init() {
        loadFromUserDefaults()
    }
    
    /// Загружает данные из UserDefaults
    private func loadFromUserDefaults() {
        if let en = UserDefaults.standard.dictionary(forKey: enUserKey) as? [String: Int] {
            userWordsEN = en
        }
        if let ru = UserDefaults.standard.dictionary(forKey: ruUserKey) as? [String: Int] {
            userWordsRU = ru
        }
        if let ignored = UserDefaults.standard.array(forKey: ignoredWordsKey) as? [String] {
            ignoredWords = Set(ignored)
        }
    }
    
    /// Сохраняет данные в UserDefaults
    private func saveToUserDefaults() {
        UserDefaults.standard.set(userWordsEN, forKey: enUserKey)
        UserDefaults.standard.set(userWordsRU, forKey: ruUserKey)
        UserDefaults.standard.set(Array(ignoredWords), forKey: ignoredWordsKey)
    }
    
    /// Получает количество повторов английского слова
    func getEnglishWordCount(_ word: String) -> Int {
        return userWordsEN[word.lowercased()] ?? 0
    }
    
    /// Получает количество повторов русского слова
    func getRussianWordCount(_ word: String) -> Int {
        return userWordsRU[word.lowercased()] ?? 0
    }
    
    /// Проверяет, игнорируется ли слово
    func isWordIgnored(_ word: String) -> Bool {
        return ignoredWords.contains(word.lowercased())
    }
    
    /// Добавляет слово в исключения
    func ignoreWord(_ word: String) {
        ignoredWords.insert(word.lowercased())
        saveToUserDefaults()
    }
    
    /// Удаляет слово из исключений
    func unignoreWord(_ word: String) {
        ignoredWords.remove(word.lowercased())
        saveToUserDefaults()
    }
    
    /// Устанавливает набор игнорируемых слов (заменяет текущий)
    func setIgnoredWords(_ words: Set<String>) {
        ignoredWords = words
        saveToUserDefaults()
        logDebug("LearningManager: set \(words.count) ignored words")
    }
    
    /// Запоминает решение пользователя
    func learnDecision(target: Language, enWord: String, ruWord: String) {
        let enLower = enWord.lowercased()
        let ruLower = ruWord.lowercased()
        
        switch target {
        case .english:
            let val = (userWordsEN[enLower] ?? 0) + 1
            userWordsEN[enLower] = val
            logDebug("Learned EN word: \(enLower) -> \(val)")
        case .russian:
            let val = (userWordsRU[ruLower] ?? 0) + 1
            userWordsRU[ruLower] = val
            logDebug("Learned RU word: \(ruLower) -> \(val)")
        }
        
        saveToUserDefaults()
    }
    
    /// Отменяет решение пользователя (undo learning)
    func unlearnDecision(target: Language, enWord: String, ruWord: String) {
        let enLower = enWord.lowercased()
        let ruLower = ruWord.lowercased()
        
        var remainingCount = 0
        var foundInUser = false
        
        switch target {
        case .english:
            // 1. Отменяем английское слово
            if let count = userWordsEN[enLower], count > 0 {
                foundInUser = true
                remainingCount = count - 1
                if remainingCount == 0 {
                    userWordsEN.removeValue(forKey: enLower)
                } else {
                    userWordsEN[enLower] = remainingCount
                }
                logDebug("Unlearned EN word: \(enLower) -> \(remainingCount)")
            }
            
            // 2. Если слово полностью удалено, добавляем в исключения
            if !foundInUser || remainingCount == 0 {
                logDebug("Adding EN word to exceptions (rejected by user): \(enLower)")
                ignoredWords.insert(enLower)
            }
            
            // 3. Неявно учим русское слово
            if !commonRuShortWords.contains(ruLower) {
                let val = (userWordsRU[ruLower] ?? 0) + 1
                userWordsRU[ruLower] = val
                logDebug("Implicitly Learned RU word (via rejection): \(ruLower) -> \(val)")
            }
            
        case .russian:
            // 1. Отменяем русское слово
            if let count = userWordsRU[ruLower], count > 0 {
                foundInUser = true
                remainingCount = count - 1
                if remainingCount == 0 {
                    userWordsRU.removeValue(forKey: ruLower)
                } else {
                    userWordsRU[ruLower] = remainingCount
                }
                logDebug("Unlearned RU word: \(ruLower) -> \(remainingCount)")
            }
            
            // 2. Если слово полностью удалено, добавляем в исключения
            if !foundInUser || remainingCount == 0 {
                logDebug("Adding RU word to exceptions (rejected by user): \(ruLower)")
                ignoredWords.insert(ruLower)
            }
            
            // 3. Неявно учим английское слово
            if !commonEnglishWords.contains(enLower) {
                let val = (userWordsEN[enLower] ?? 0) + 1
                userWordsEN[enLower] = val
                logDebug("Implicitly Learned EN word (via rejection): \(enLower) -> \(val)")
            }
        }
        
        saveToUserDefaults()
    }
}

// Используем константы из LanguageConstants
private let commonRuShortWords = LanguageConstants.commonRuShortWords
private let commonEnglishWords = LanguageConstants.commonEnglishWords