#!/usr/bin/env swift

import Foundation
import Cocoa

/// Тестирование коротких слов через NSSpellChecker
class ShortWordsTester {
    private let spellChecker = NSSpellChecker.shared
    
    /// Тестирует короткие слова
    func testShortWords() {
        print("=== Тестирование коротких слов через NSSpellChecker ===")
        print()
        
        // Тестовые слова
        let testWords = [
            // Короткие английские слова (1-3 символа)
            "a", "an", "be", "by", "do", "go", "he", "hi", "if", "in", "is", "it", "me", "my", "no", "of", "on", "or", "so", "to", "up", "us", "we",
            "are", "but", "can", "did", "for", "get", "had", "has", "her", "him", "his", "how", "its", "let", "man", "not", "now", "one", "out", "say", "see", "she", "the", "too", "use", "was", "way", "who", "why", "yes", "you",
            
            // Короткие русские слова (1-3 символа)
            "а", "в", "и", "к", "о", "с", "у", "я",
            "бы", "во", "да", "до", "за", "из", "на", "не", "но", "он", "от", "по", "со", "то", "ты", "уже",
            "без", "был", "быть", "весь", "вот", "для", "его", "ее", "еще", "или", "им", "их", "ли", "мой", "над", "нас", "нет", "ни", "них", "но", "она", "они", "оно", "под", "при", "раз", "раз", "свой", "так", "тем", "тот", "тут", "уже", "чем", "что", "это",
            
            // Специальные случаи для тестирования
            "фку", "яку", "руддщ", "ghbdtn", "heccrbq", "ntcn", "yfxfkmybr"
        ]
        
        print("Всего тестовых слов: \(testWords.count)")
        print()
        
        var englishResults: [String: Bool] = [:]
        var russianResults: [String: Bool] = [:]
        
        // Тестируем каждое слово
        for word in testWords {
            let isEnglish = checkEnglishWord(word)
            let isRussian = checkRussianWord(word)
            
            englishResults[word] = isEnglish
            russianResults[word] = isRussian
            
            print("Слово: '\(word)' (длина: \(word.count))")
            print("  Английский: \(isEnglish ? "✓" : "✗")")
            print("  Русский: \(isRussian ? "✓" : "✗")")
            
            // Анализируем результаты
            if isEnglish && !isRussian {
                print("  → Только английский")
            } else if !isEnglish && isRussian {
                print("  → Только русский")
            } else if isEnglish && isRussian {
                print("  → Оба языка (ambiguous)")
            } else {
                print("  → Ни один язык")
            }
            print()
        }
        
        // Статистика
        print("=== Статистика ===")
        let totalWords = testWords.count
        let englishOnly = englishResults.filter { $0.value && !russianResults[$0.key]! }.count
        let russianOnly = russianResults.filter { $0.value && !englishResults[$0.key]! }.count
        let bothLanguages = englishResults.filter { $0.value && russianResults[$0.key]! }.count
        let neitherLanguage = englishResults.filter { !$0.value && !russianResults[$0.key]! }.count
        
        print("Всего слов: \(totalWords)")
        print("Только английские: \(englishOnly) (\(String(format: "%.1f", Double(englishOnly) / Double(totalWords) * 100))%)")
        print("Только русские: \(russianOnly) (\(String(format: "%.1f", Double(russianOnly) / Double(totalWords) * 100))%)")
        print("Оба языка: \(bothLanguages) (\(String(format: "%.1f", Double(bothLanguages) / Double(totalWords) * 100))%)")
        print("Ни один язык: \(neitherLanguage) (\(String(format: "%.1f", Double(neitherLanguage) / Double(totalWords) * 100))%)")
        
        // Анализ коротких слов (1-3 символа)
        print()
        print("=== Анализ коротких слов (1-3 символа) ===")
        let shortWords = testWords.filter { $0.count <= 3 }
        let shortEnglishOnly = shortWords.filter { englishResults[$0]! && !russianResults[$0]! }.count
        let shortRussianOnly = shortWords.filter { !englishResults[$0]! && russianResults[$0]! }.count
        let shortBoth = shortWords.filter { englishResults[$0]! && russianResults[$0]! }.count
        let shortNeither = shortWords.filter { !englishResults[$0]! && !russianResults[$0]! }.count
        
        print("Коротких слов: \(shortWords.count)")
        print("Только английские: \(shortEnglishOnly)")
        print("Только русские: \(shortRussianOnly)")
        print("Оба языка: \(shortBoth)")
        print("Ни один язык: \(shortNeither)")
        
        // Специальные случаи
        print()
        print("=== Специальные случаи ===")
        let specialCases = ["фку", "яку", "руддщ", "ghbdtn", "heccrbq", "ntcn", "yfxfkmybr"]
        for word in specialCases {
            let isEnglish = englishResults[word] ?? false
            let isRussian = russianResults[word] ?? false
            
            print("'\(word)' (длина: \(word.count)):")
            print("  Английский: \(isEnglish ? "✓" : "✗")")
            print("  Русский: \(isRussian ? "✓" : "✗")")
            
            // Определяем, что это за слово
            if word == "фку" || word == "яку" {
                print("  → Русская раскладка: '\(word)'")
                print("  → Английская раскладка: '\(convertRussianToEnglish(word))'")
            } else if word == "руддщ" || word == "ghbdtn" || word == "heccrbq" || word == "ntcn" || word == "yfxfkmybr" {
                print("  → Английская раскладка: '\(word)'")
                print("  → Русская раскладка: '\(convertEnglishToRussian(word))'")
            }
            print()
        }
    }
    
    /// Проверяет английское слово
    private func checkEnglishWord(_ word: String) -> Bool {
        let range = spellChecker.checkSpelling(
            of: word,
            startingAt: 0,
            language: "en",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location == NSNotFound
    }
    
    /// Проверяет русское слово
    private func checkRussianWord(_ word: String) -> Bool {
        let range = spellChecker.checkSpelling(
            of: word,
            startingAt: 0,
            language: "ru",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location == NSNotFound
    }
    
    /// Конвертирует русскую раскладку в английскую
    private func convertRussianToEnglish(_ russianWord: String) -> String {
        let russianToEnglish: [Character: Character] = [
            "ф": "a", "и": "b", "с": "c", "в": "d", "у": "e", "а": "f", "п": "g", "р": "h", "ш": "i", "о": "j",
            "л": "k", "д": "l", "ь": "m", "т": "n", "щ": "o", "з": "p", "й": "q", "к": "r", "ы": "s", "е": "t",
            "г": "u", "м": "v", "ц": "w", "ч": "x", "н": "y", "я": "z", "х": "[", "ъ": "]", "ж": ";", "э": "'",
            "б": ",", "ю": ".", "ё": "`"
        ]
        
        var result = ""
        for char in russianWord.lowercased() {
            if let englishChar = russianToEnglish[char] {
                result.append(englishChar)
            } else {
                result.append(char)
            }
        }
        return result
    }
    
    /// Конвертирует английскую раскладку в русскую
    private func convertEnglishToRussian(_ englishWord: String) -> String {
        let englishToRussian: [Character: Character] = [
            "a": "ф", "b": "и", "c": "с", "d": "в", "e": "у", "f": "а", "g": "п", "h": "р", "i": "ш", "j": "о",
            "k": "л", "l": "д", "m": "ь", "n": "т", "o": "щ", "p": "з", "q": "й", "r": "к", "s": "ы", "t": "е",
            "u": "г", "v": "м", "w": "ц", "x": "ч", "y": "н", "z": "я", "[": "х", "]": "ъ", ";": "ж", "'": "э",
            ",": "б", ".": "ю", "`": "ё"
        ]
        
        var result = ""
        for char in englishWord.lowercased() {
            if let russianChar = englishToRussian[char] {
                result.append(russianChar)
            } else {
                result.append(char)
            }
        }
        return result
    }
}

// Запуск теста
let tester = ShortWordsTester()
tester.testShortWords()