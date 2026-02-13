#!/usr/bin/env swift

import Foundation
import Cocoa

// Простой тест для проверки NSSpellChecker
print("=== Простой тест NSSpellChecker ===")

let spellChecker = NSSpellChecker.shared

// Тестовые слова
let testWords = [
    "havv",      // Опечатка для "have"
    "have",      // Правильное слово
    "writting",  // Опечатка для "writing"
    "writing",   // Правильное слово
    "првиет",    // Опечатка для "привет"
    "привет",    // Правильное слово
    "карова",    // Опечатка для "корова"
    "корова",    // Правильное слово
]

print("\n1. Проверка орфографии:")
for word in testWords {
    // Проверяем английский
    let enRange = spellChecker.checkSpelling(of: word, startingAt: 0, language: "en_US", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
    let isValidEN = enRange.location == NSNotFound
    
    // Проверяем русский
    let ruRange = spellChecker.checkSpelling(of: word, startingAt: 0, language: "ru_RU", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
    let isValidRU = ruRange.location == NSNotFound
    
    print("  '\(word)': EN=\(isValidEN), RU=\(isValidRU)")
}

print("\n2. Получение предложений:")
let wordsWithTypos = ["havv", "writting", "првиет", "карова"]

for word in wordsWithTypos {
    print("\n  Слово: '\(word)'")
    
    // Английские предложения
    let enGuesses = spellChecker.guesses(forWordRange: NSRange(location: 0, length: word.count), in: word, language: "en_US", inSpellDocumentWithTag: 0)
    if let enGuesses = enGuesses, !enGuesses.isEmpty {
        print("    EN guesses: \(enGuesses)")
    }
    
    // Русские предложения
    let ruGuesses = spellChecker.guesses(forWordRange: NSRange(location: 0, length: word.count), in: word, language: "ru_RU", inSpellDocumentWithTag: 0)
    if let ruGuesses = ruGuesses, !ruGuesses.isEmpty {
        print("    RU guesses: \(ruGuesses)")
    }
}

print("\n3. Тестирование расстояния Левенштейна:")
func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
    let empty = [Int](repeating: 0, count: s2.count)
    var last = [Int](0...s2.count)
    
    for (i, char1) in s1.enumerated() {
        var cur = [i + 1] + empty
        for (j, char2) in s2.enumerated() {
            cur[j + 1] = char1 == char2 ? last[j] : min(last[j], last[j + 1], cur[j]) + 1
        }
        last = cur
    }
    return last.last!
}

let typoPairs = [
    ("havv", "have"),
    ("writting", "writing"),
    ("recieve", "receive"),
    ("seperate", "separate"),
    ("првиет", "привет"),
    ("карова", "корова"),
]

for (typo, correct) in typoPairs {
    let distance = levenshteinDistance(typo, correct)
    print("  '\(typo)' → '\(correct)': расстояние = \(distance)")
}

print("\n=== Тест завершен ===")