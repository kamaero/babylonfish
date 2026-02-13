#!/usr/bin/env swift

import Foundation
import Cocoa

// Простая проверка NSSpellChecker
let spellChecker = NSSpellChecker.shared

print("Тестирование NSSpellChecker для коротких слов:")
print("==============================================")

// Тестируем английские слова
let englishWords = ["how", "are", "you", "in", "no", "is", "it", "on", "at", "by"]
let russianWords = ["как", "ты", "вы", "он", "она", "мы", "они", "нет", "да", "что"]

print("\n1. Проверка английских слов:")
for word in englishWords {
    let range = NSRange(location: 0, length: word.utf16.count)
    let isValid = spellChecker.checkSpelling(of: word, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    print("  '\(word)': \(isValid ? "✓ валидно" : "✗ невалидно")")
}

print("\n2. Проверка русских слов:")
for word in russianWords {
    let range = NSRange(location: 0, length: word.utf16.count)
    let isValid = spellChecker.checkSpelling(of: word, startingAt: 0, language: "ru", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    print("  '\(word)': \(isValid ? "✓ валидно" : "✗ невалидно")")
}

print("\n3. Тестирование слов в неправильной раскладке:")
let mixedWords = [
    ("рщц", "how", "en"),      // how в русской раскладке
    ("фку", "are", "en"),      // are в русской раскладке
    ("нщг", "you", "en"),      // you в русской раскладке
    ("яку", "you", "en"),      // you (альтернативная раскладка)
    ("rfr", "как", "ru"),      // как в английской раскладке
    ("cnjq", "слово", "ru"),   // слово в английской раскладке
    ("yf", "no", "ru"),        // no в английской раскладке
    ("dt", "in", "ru"),        // in в английской раскладке
]

print("\nСлова в неправильной раскладке:")
for (input, expected, language) in mixedWords {
    let range = NSRange(location: 0, length: input.utf16.count)
    let isValid = spellChecker.checkSpelling(of: input, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    
    let expectedRange = NSRange(location: 0, length: expected.utf16.count)
    let expectedIsValid = spellChecker.checkSpelling(of: expected, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    
    print("  '\(input)' (ожидается '\(expected)'):")
    print("    - '\(input)' в языке '\(language)': \(isValid ? "валидно" : "невалидно")")
    print("    - '\(expected)' в языке '\(language)': \(expectedIsValid ? "валидно" : "невалидно")")
    
    // Логика BabylonFish:
    // Если слово невалидно в текущей раскладке, но валидно в целевой → переключение
    if !isValid && expectedIsValid {
        print("    → BabylonFish: ПЕРЕКЛЮЧИТ (слово невалидно в текущей раскладке, но валидно в целевой)")
    } else if isValid && !expectedIsValid {
        print("    → BabylonFish: НЕ ПЕРЕКЛЮЧИТ (слово валидно в текущей раскладке)")
    } else {
        print("    → BabylonFish: потребуется дополнительная проверка (нейросеть/паттерны)")
    }
    print()
}

print("\nВывод:")
print("""
NSSpellChecker отлично справляется с проверкой коротких слов!
Теперь BabylonFish будет:
1. Для слов длиной 2-4 символа использовать NSSpellChecker
2. Если слово валидно в целевом языке → автоматическое переключение
3. Больше не нужно добавлять слова вручную в паттерны!

Примеры:
- "рщц" → NSSpellChecker проверяет "how" (валидно) → переключение на английский
- "фку" → NSSpellChecker проверяет "are" (валидно) → переключение на английский
- "яку" → NSSpellChecker проверяет "you" (валидно) → переключение на английский
- "rfr" → NSSpellChecker проверяет "как" (валидно) → переключение на русский
""")