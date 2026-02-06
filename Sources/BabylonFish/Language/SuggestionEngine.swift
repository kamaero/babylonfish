import Foundation

/// Узел префиксного дерева (Trie)
private class TrieNode {
    var children: [Character: TrieNode] = [:]
    var isEndOfWord: Bool = false
    var word: String?
}

/// Движок предложений на основе префиксного дерева
class SuggestionEngine {
    private let englishTrie = TrieNode()
    private let russianTrie = TrieNode()
    private let learningManager: LearningManager
    
    init(learningManager: LearningManager) {
        self.learningManager = learningManager
        buildTries()
    }
    
    /// Строит префиксные деревья из словарей
    private func buildTries() {
        // Английские слова
        for word in LanguageConstants.commonEnglishWords {
            insert(word: word, into: englishTrie)
        }
        
        // Русские слова
        for word in LanguageConstants.commonRuShortWords {
            insert(word: word, into: russianTrie)
        }
        
        // TODO: Добавить пользовательские слова из learningManager
    }
    
    /// Вставляет слово в префиксное дерево
    private func insert(word: String, into root: TrieNode) {
        var node = root
        for char in word.lowercased() {
            if node.children[char] == nil {
                node.children[char] = TrieNode()
            }
            node = node.children[char]!
        }
        node.isEndOfWord = true
        node.word = word
    }
    
    /// Получает предложение для последовательности кодов клавиш
    func getSuggestion(for keyCodes: [Int]) -> String? {
        guard keyCodes.count >= 2 else { return nil }
        
        var enString = ""
        var ruString = ""
        
        for code in keyCodes {
            if let chars = KeyMapper.shared.getChars(for: code) {
                enString += chars.en
                ruString += chars.ru
            }
        }
        
        let enLower = enString.lowercased()
        let ruLower = ruString.lowercased()
        
        // 1. Проверяем автодополнение английских слов
        if let enCompletion = autocomplete(word: enLower, in: englishTrie) {
            return enCompletion
        }
        
        // 2. Проверяем автодополнение русских слов
        if let ruCompletion = autocomplete(word: ruLower, in: russianTrie) {
            return ruCompletion
        }
        
        // 3. Проверяем пользовательские слова (английские)
        // TODO: Добавить пользовательские слова в отдельное дерево или проверять здесь
        
        // 4. Проверяем кросс-раскладочные исправления
        // Если enString - это русское слово, набранное в английской раскладке
        if let crossLayoutSuggestion = getCrossLayoutSuggestion(enString: enString, ruString: ruString) {
            return crossLayoutSuggestion
        }
        
        return nil
    }
    
    /// Автодополнение слова в префиксном дереве
    private func autocomplete(word: String, in root: TrieNode) -> String? {
        var node = root
        
        // Идем по префиксу
        for char in word {
            guard let nextNode = node.children[char] else {
                return nil // Префикс не найден
            }
            node = nextNode
        }
        
        // Нашли префикс, ищем полное слово
        return findCompleteWord(from: node, prefix: word)
    }
    
    /// Находит полное слово, начиная с узла
    private func findCompleteWord(from node: TrieNode, prefix: String) -> String? {
        // Если текущий узел - конец слова и слово длиннее префикса
        if node.isEndOfWord, let word = node.word, word.count > prefix.count {
            return word
        }
        
        // Ищем любое дочернее слово
        for (_, childNode) in node.children {
            if let word = findCompleteWord(from: childNode, prefix: prefix) {
                return word
            }
        }
        
        return nil
    }
    
    /// Предлагает исправление для кросс-раскладочных ошибок
    private func getCrossLayoutSuggestion(enString: String, ruString: String) -> String? {
        // Проверяем, является ли enString русским словом, набранным в английской раскладке
        // Например: "ghbdtn" -> "привет"
        
        let enLower = enString.lowercased()
        let ruLower = ruString.lowercased()
        
        // Сначала проверяем русское дерево для ruLower (это уже преобразованные символы)
        if let ruCompletion = autocomplete(word: ruLower, in: russianTrie) {
            return ruCompletion
        }
        
        // Проверяем английское дерево для enLower (если это английское слово, набранное в русской раскладке)
        if let enCompletion = autocomplete(word: enLower, in: englishTrie) {
            return enCompletion
        }
        
        return nil
    }
    
    /// Добавляет пользовательское слово в движок
    func addUserWord(_ word: String, language: Language) {
        let trie = (language == .english) ? englishTrie : russianTrie
        insert(word: word, into: trie)
    }
    
    /// Удаляет пользовательское слово из движка
    func removeUserWord(_ word: String, language: Language) {
        // TODO: Реализовать удаление из Trie (более сложная операция)
        // Пока просто помечаем как удаленное в learningManager
        logDebug("Word removal from Trie not implemented yet: \(word)")
    }
}