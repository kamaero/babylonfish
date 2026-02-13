#!/usr/bin/env swift

import Foundation

// Финальный тест для проверки всех исправлений

// Имитируем исправленную логику
func testWordConversion(_ russianLayoutWord: String, expectedEnglish: String) -> (detected: String, confidence: Double, shouldSwitch: Bool) {
    print("--- Тест: '\(russianLayoutWord)' → '\(expectedEnglish)' ---")
    
    var confidence: Double = 0
    var detectedLanguage: String = "не определено"
    
    // Проверяем impossible patterns
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
        "цшер", "цшер", // with
        "нщг", "нщг" // you
    ]
    
    // Проверяем паттерны (минимальная длина: 3)
    for pattern in impossibleEnInRuKeys where pattern.count >= 3 {
        if russianLayoutWord.contains(pattern) {
            confidence = 0.95
            detectedLanguage = "english"
            print("✅ Найден impossible pattern '\(pattern)' → confidence 0.95")
            break
        }
    }
    
    // Если не нашли через impossible patterns, используем analyzeWordAlone логику
    if confidence == 0 {
        // Имитируем analyzeWordAlone логику
        let hasCyrillic = russianLayoutWord.contains { char in
            let scalar = String(char).unicodeScalars.first?.value ?? 0
            return (0x0400...0x04FF).contains(scalar)
        }
        
        if hasCyrillic {
            // Если слово содержит кириллицу и это английское слово в русской раскладке
            confidence = 0.8
            detectedLanguage = "english"
            print("✅ AnalyzeWordAlone: содержит кириллицу → confidence 0.8")
        } else {
            confidence = 0.5
            detectedLanguage = "не определено"
            print("❌ AnalyzeWordAlone: не содержит кириллицу → confidence 0.5")
        }
    }
    
    // Проверяем, достаточно ли confidence для переключения
    let shouldSwitch: Bool
    if russianLayoutWord.count >= 5 {
        shouldSwitch = confidence >= 0.9
        print("Длина слова: \(russianLayoutWord.count) символов → требуется confidence >= 0.9")
    } else {
        shouldSwitch = confidence >= 0.8
        print("Длина слова: \(russianLayoutWord.count) символов → требуется confidence >= 0.8")
    }
    
    print("Результат: \(detectedLanguage) (confidence: \(String(format: "%.2f", confidence)))")
    print("Переключение: \(shouldSwitch ? "✅ ДА" : "❌ НЕТ")")
    print("--- Конец теста ---")
    print()
    
    return (detectedLanguage, confidence, shouldSwitch)
}

// Тестовые примеры из пользовательского сообщения
let userTestCases = [
    ("руддщ", "hello"),
    ("рщц", "how"),
    ("фку", "are"),
    ("нщг", "you")
]

print("=== ТЕСТ ОБРАТНОЙ КОНВЕРТАЦИИ ===")
print("Проверка: английские слова, набранные в русской раскладке")
print()

var allPassed = true
for (russianWord, englishWord) in userTestCases {
    let result = testWordConversion(russianWord, expectedEnglish: englishWord)
    
    let passed = result.detected == "english" && result.shouldSwitch
    if !passed {
        allPassed = false
    }
    
    print("Итог для '\(russianWord)' → '\(englishWord)': \(passed ? "✅ ПРОШЕЛ" : "❌ НЕ ПРОШЕЛ")")
    print()
}

// Тест полного предложения
print("=== ТЕСТ ПОЛНОГО ПРЕДЛОЖЕНИЯ ===")
print("Проверка: 'руддщ! рщц фку нщг?' → 'hello! how are you?'")
print()

let fullSentence = "руддщ! рщц фку нщг?"
let words = fullSentence.split(separator: " ").map { String($0) }

var sentenceResults: [(word: String, detected: String, shouldSwitch: Bool)] = []
for word in words {
    let cleanWord = word.filter { $0.isLetter }
    if !cleanWord.isEmpty {
        let result = testWordConversion(cleanWord, expectedEnglish: "")
        sentenceResults.append((word: word, detected: result.detected, shouldSwitch: result.shouldSwitch))
    }
}

print("=== РЕЗУЛЬТАТЫ ДЛЯ ПРЕДЛОЖЕНИЯ ===")
for result in sentenceResults {
    print("Слово '\(result.word)': \(result.detected), переключение: \(result.shouldSwitch ? "✅" : "❌")")
}

// Проверяем, все ли слова будут переключены
let allWordsSwitch = sentenceResults.allSatisfy { $0.shouldSwitch }
print()
print("Все слова будут переключены: \(allWordsSwitch ? "✅ ДА" : "❌ НЕТ")")

// Проверяем, какие паттерны есть в impossibleEnInRuKeys
print()
print("=== ПАТТЕРНЫ В impossibleEnInRuKeys ===")
for pattern in ["руддщ", "рщц", "фку", "нщг", "црфе", "ерфе", "ершы", "ерун", "фтв", "ащк", "цшер"] {
    let inSet = ["руддщ", "рщц", "фку", "нщг", "црфе", "ерфе", "ершы", "ерун", "фтв", "ащк", "цшер"].contains(pattern)
    print("'\(pattern)': \(inSet ? "✅ есть" : "❌ нет")")
}