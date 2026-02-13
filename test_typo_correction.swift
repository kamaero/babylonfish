#!/usr/bin/env swift

import Foundation
import Cocoa

// Простой тест для проверки исправления опечаток
print("=== Тестирование исправления опечаток ===")

// Создаем экземпляр TypoCorrector
let systemDictionary = SystemDictionaryService.shared
let cacheManager = CacheManager.shared
let performanceMonitor = PerformanceMonitor.shared

let typoCorrector = TypoCorrector(
    systemDictionary: systemDictionary,
    cacheManager: cacheManager,
    performanceMonitor: performanceMonitor
)

// Включаем исправление опечаток
typoCorrector.configure(
    isEnabled: true,
    autoCorrectEnabled: true,
    suggestionEnabled: true,
    maxEditDistance: 2,
    minConfidence: 0.7,
    contextWeight: 0.3
)

// Тестовые слова с опечатками
let testCases = [
    // Английские слова с опечатками
    ("havv", "have"),
    ("writting", "writing"),
    ("recieve", "receive"),
    ("seperate", "separate"),
    ("definately", "definitely"),
    
    // Русские слова с опечатками
    ("првиет", "привет"),
    ("карова", "корова"),
    ("малако", "молоко"),
    ("собака", "собака"), // без опечатки
    ("кошка", "кошка"),   // без опечатки
    
    // Короткие слова
    ("teh", "the"),
    ("adn", "and"),
    ("yuor", "your"),
    ("wht", "what"),
    ("hw", "how"),
]

print("\n1. Тестирование исправления отдельных слов:")
for (input, expected) in testCases {
    let result = typoCorrector.correctTypos(in: input)
    print("  '\(input)' → '\(result.correctedText)' (ожидалось: '\(expected)')")
    print("    Применено: \(result.applied), Уверенность: \(String(format: "%.2f", result.confidence))")
    if !result.corrections.isEmpty {
        for correction in result.corrections {
            print("    Исправление: '\(correction.originalWord)' → '\(correction.correctedWord)' (уверенность: \(String(format: "%.2f", correction.confidence)))")
        }
    }
    print()
}

print("\n2. Тестирование предложений:")
let sentences = [
    "I hav a dog and teh cat",
    "Привет как дела првиет",
    "This is definately wrong writting",
    "Мама мыла раму и карова"
]

for sentence in sentences {
    let result = typoCorrector.correctTypos(in: sentence)
    print("  '\(sentence)'")
    print("  → '\(result.correctedText)'")
    print("    Применено: \(result.applied), Уверенность: \(String(format: "%.2f", result.confidence))")
    if !result.corrections.isEmpty {
        print("    Исправления: \(result.corrections.count)")
    }
    print()
}

print("\n3. Тестирование получения предложений:")
let wordsForSuggestions = ["havv", "writting", "првиет", "карова"]

for word in wordsForSuggestions {
    let suggestions = typoCorrector.getSuggestions(for: word)
    print("  '\(word)': \(suggestions)")
}

print("\n4. Тестирование NSSpellChecker напрямую:")
let spellChecker = NSSpellChecker.shared
let testWords = ["havv", "have", "привет", "првиет"]

for word in testWords {
    // Проверяем английский
    let enRange = spellChecker.checkSpelling(of: word, startingAt: 0, language: "en_US", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
    let isValidEN = enRange.location == NSNotFound
    
    // Проверяем русский
    let ruRange = spellChecker.checkSpelling(of: word, startingAt: 0, language: "ru_RU", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
    let isValidRU = ruRange.location == NSNotFound
    
    print("  '\(word)': EN=\(isValidEN), RU=\(isValidRU)")
    
    // Получаем предложения
    if !isValidEN {
        let suggestions = spellChecker.guesses(forWordRange: NSRange(location: 0, length: word.count), in: word, language: "en_US", inSpellDocumentWithTag: 0)
        print("    EN suggestions: \(suggestions ?? [])")
    }
    if !isValidRU {
        let suggestions = spellChecker.guesses(forWordRange: NSRange(location: 0, length: word.count), in: word, language: "ru_RU", inSpellDocumentWithTag: 0)
        print("    RU suggestions: \(suggestions ?? [])")
    }
}

print("\n=== Тестирование завершено ===")