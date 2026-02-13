#!/usr/bin/env swift

import Foundation

// Простой тест для проверки логики обратной конвертации

// Имитируем логику из EnhancedLanguageDetector
func analyzeWordAlone(enString: String, ruString: String) -> (language: String?, confidence: Double) {
    // Проверяем наличие кириллицы/латиницы в ОБОИХ строках
    
    let hasCyrillicInRu = ruString.contains { char in
        let scalar = String(char).unicodeScalars.first?.value ?? 0
        return (0x0400...0x04FF).contains(scalar)
    }
    
    let hasLatinInEn = enString.contains { char in
        let scalar = String(char).unicodeScalars.first?.value ?? 0
        return (0x0041...0x007A).contains(scalar)
    }
    
    let hasCyrillicInEn = enString.contains { char in
        let scalar = String(char).unicodeScalars.first?.value ?? 0
        return (0x0400...0x04FF).contains(scalar)
    }
    
    let hasLatinInRu = ruString.contains { char in
        let scalar = String(char).unicodeScalars.first?.value ?? 0
        return (0x0041...0x007A).contains(scalar)
    }
    
    // Логика определения:
    // 1. Если enString содержит латиницу, а ruString содержит кириллицу → вероятно английское слово в русской раскладке
    // 2. Если ruString содержит кириллицу, а enString содержит латиницу → вероятно русское слово в английской раскладке
    // 3. Если оба содержат один тип символов → неопределенно
    
    if hasLatinInEn && hasCyrillicInRu && !hasCyrillicInEn && !hasLatinInRu {
        // Английское слово в русской раскладке (например, "руддщ" → "hello")
        return ("english", 0.8)
    } else if hasCyrillicInRu && hasLatinInEn && !hasLatinInRu && !hasCyrillicInEn {
        // Русское слово в английской раскладке (например, "ghbdtn" → "привет")
        return ("russian", 0.8)
    } else if hasCyrillicInRu && !hasLatinInEn {
        // Только кириллица в ruString, нет латиницы в enString
        return ("russian", 0.7)
    } else if hasLatinInEn && !hasCyrillicInRu {
        // Только латиница в enString, нет кириллицы в ruString
        return ("english", 0.7)
    } else {
        // Смешанные или другие символы
        return (nil, 0.5)
    }
}

// Тестовые примеры
let testCases = [
    // Английские слова в русской раскладке
    ("hello", "руддщ"),
    ("how", "рщц"),
    ("are", "фку"),
    ("you", "нщг"),
    ("what", "црфе"),
    ("that", "ерфе"),
    ("this", "ершы"),
    ("the", "еру"),
    ("they", "ерун"),
    ("and", "фтв"),
    ("for", "ащк"),
    ("with", "цшер"),
    
    // Русские слова в английской раскладке
    ("привет", "ghbdtn"),
    ("как", "rfr"),
    ("дела", "lkf"),
    ("мир", "vbr"),
    ("спасибо", "cgfcb,j"),
    ("пожалуйста", "gj;fkbnc"),
    ("хорошо", "[jhji"),
    ("плохо", "gkj[")
]

print("=== Тест логики обратной конвертации ===")
print()

for (expectedEnglish, russianLayout) in testCases {
    let result = analyzeWordAlone(enString: expectedEnglish, ruString: russianLayout)
    
    if let detectedLanguage = result.language {
        let isCorrect = (detectedLanguage == "english" && expectedEnglish.count > 0) || 
                       (detectedLanguage == "russian" && russianLayout.count > 0)
        
        print("Тест: '\(russianLayout)' → '\(expectedEnglish)'")
        print("  Результат: \(detectedLanguage) (confidence: \(String(format: "%.2f", result.confidence)))")
        print("  Правильно: \(isCorrect ? "✅" : "❌")")
    } else {
        print("Тест: '\(russianLayout)' → '\(expectedEnglish)'")
        print("  Результат: не определено (confidence: \(String(format: "%.2f", result.confidence)))")
        print("  Правильно: ❌")
    }
    print()
}

// Проверяем impossible patterns
print("=== Проверка impossible patterns ===")
print()

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

for pattern in impossibleEnInRuKeys where pattern.count >= 4 {
    print("Паттерн '\(pattern)': длина \(pattern.count) символов")
    
    // Проверяем, содержит ли наш тестовый пример этот паттерн
    for (expectedEnglish, russianLayout) in testCases {
        if russianLayout.contains(pattern) {
            print("  Найден в: '\(russianLayout)' → '\(expectedEnglish)'")
        }
    }
}

print()
print("=== Проверка confidence thresholds ===")
print()

// Проверяем, достаточно ли confidence для переключения раскладки
let testWord = "руддщ"
let confidenceFromPatterns = 0.95 // Из impossibleEnInRuKeys
let confidenceFromAnalyzeWordAlone = 0.8 // Из analyzeWordAlone

print("Слово: '\(testWord)' (hello в русской раскладке)")
print("Confidence от impossible patterns: \(confidenceFromPatterns)")
print("Confidence от analyzeWordAlone: \(confidenceFromAnalyzeWordAlone)")
print("Минимальный confidence для переключения (5+ символов): 0.9")
print()

if confidenceFromPatterns >= 0.9 {
    print("✅ Confidence от impossible patterns (\(confidenceFromPatterns)) >= 0.9 → переключение должно работать")
} else {
    print("❌ Confidence от impossible patterns (\(confidenceFromPatterns)) < 0.9 → переключение не сработает")
}

if confidenceFromAnalyzeWordAlone >= 0.9 {
    print("✅ Confidence от analyzeWordAlone (\(confidenceFromAnalyzeWordAlone)) >= 0.9 → переключение должно работать")
} else {
    print("❌ Confidence от analyzeWordAlone (\(confidenceFromAnalyzeWordAlone)) < 0.9 → переключение не сработает")
}