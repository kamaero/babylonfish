#!/usr/bin/env swift

import Foundation

// Тест для проверки логики NeuralLanguageClassifier

// Имитируем логику classifyWithHeuristics из NeuralLanguageClassifier
func classifyWithHeuristics(_ text: String) -> (language: String?, confidence: Double) {
    print("--- Heuristics analysis for '\(text)' ---")
    
    var scores: [String: Double] = [:]
    
    // 1. Проверяем "невозможные паттерны" для "неправильной раскладки"
    let impossibleEnInRuKeys: Set<String> = [
        "рудд", "руддщ", // hell, hello
        "цр", "црфе", // wh, what
        "рщ", "рщц", // ho, how
        "ер", "ерфе", // th, that
        "ершы", "ершы", // this
        "еру", "ерун", // the, they
        "фтв", "фтв", // and
        "ащк", "ащкпуе", // for, forget
        "фку", "фку", // are
        "цшер", "цшер" // with
    ]
    
    print("Checking impossible patterns...")
    for pattern in impossibleEnInRuKeys where pattern.count >= 4 {
        if text.contains(pattern) {
            scores["english", default: 0] += 0.95
            print("Found impossible English pattern '\(pattern)' in text → English +0.95")
            break
        }
    }
    
    // Находим лучший язык
    let bestLanguage = scores.max(by: { $0.value < $1.value })
    
    guard let language = bestLanguage?.key, let score = bestLanguage?.value else {
        print("No language detected, scores: \(scores)")
        return (nil, 0)
    }
    
    let confidence = min(max(score, 0.1), 0.9)
    print("Heuristics result: \(language) with confidence \(String(format: "%.3f", confidence))")
    print("All scores: \(scores)")
    print("--- End heuristics ---")
    
    return (language, confidence)
}

// Тестовые примеры
let testCases = [
    "руддщ",  // hello
    "рщц",    // how
    "фку",    // are
    "нщг",    // you
    "црфе",   // what
    "ерфе",   // that
    "ершы",   // this
    "еру",    // the
    "ерун",   // they
    "фтв",    // and
    "ащк",    // for
    "цшер"    // with
]

print("=== Тест NeuralLanguageClassifier логики ===")
print()

for testWord in testCases {
    let result = classifyWithHeuristics(testWord)
    
    if let detectedLanguage = result.language {
        print("Слово: '\(testWord)'")
        print("  Результат: \(detectedLanguage) (confidence: \(String(format: "%.2f", result.confidence)))")
        
        // Проверяем, достаточно ли confidence для переключения
        if testWord.count >= 5 && result.confidence >= 0.9 {
            print("  Переключение: ✅ (confidence \(String(format: "%.2f", result.confidence)) >= 0.9, длина \(testWord.count) символов)")
        } else if testWord.count < 5 && result.confidence >= 0.8 {
            print("  Переключение: ✅ (confidence \(String(format: "%.2f", result.confidence)) >= 0.8, длина \(testWord.count) символов)")
        } else {
            print("  Переключение: ❌ (confidence \(String(format: "%.2f", result.confidence)), требуется \(testWord.count >= 5 ? "0.9" : "0.8"))")
        }
    } else {
        print("Слово: '\(testWord)'")
        print("  Результат: не определено")
        print("  Переключение: ❌")
    }
    print()
}

// Проверяем полное предложение
print("=== Тест полного предложения ===")
print()

let fullSentence = "руддщ! рщц фку нщг?"
print("Предложение: '\(fullSentence)'")
print("(hello! how are you?)")
print()

// Разбиваем на слова
let words = fullSentence.split(separator: " ").map { String($0) }
for word in words {
    // Убираем пунктуацию для проверки
    let cleanWord = word.filter { $0.isLetter }
    if !cleanWord.isEmpty {
        let result = classifyWithHeuristics(cleanWord)
        print("Слово '\(word)' → '\(cleanWord)': \(result.language ?? "не определено") (confidence: \(String(format: "%.2f", result.confidence)))")
    }
}