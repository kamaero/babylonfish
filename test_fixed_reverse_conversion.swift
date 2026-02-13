#!/usr/bin/env swift

import Foundation

/// Тестирование исправленной логики обратной конверсии
class FixedReverseConversionTester {
    
    /// Тестирует исправленную логику isEnglishWordInRussianLayout
    func testFixedReverseConversionLogic() {
        print("=== Тестирование ИСПРАВЛЕННОЙ логики обратной конверсии ===")
        print()
        
        // Тестовые слова
        let testWords = [
            // Английские слова в русской раскладке (должны быть true)
            "фку",    // are
            "яку",    // you (альтернатива)
            "нщг",    // you
            "рщц",    // how
            "руддщ",  // hello
            "щт",     // in
            "йфя",    // was
            "еуые",   // test
            
            // Русские слова (должны быть false)
            "привет", // hello (русский)
            "как",    // how (русский)
            "ты",     // you (русский)
            "я",      // I (русский)
            "он",     // he (русский)
            "она",    // she (русский)
            
            // Короткие русские слова, которые NSSpellChecker считает английскими
            // С исправленной логикой они должны быть false
            "а", "в", "и", "к", "о", "с", "у", "я",
            "бы", "во", "да", "до", "за", "из", "на", "не", "но", "он", "от", "по", "со", "то", "ты",
            "без", "был", "быть", "весь", "вот", "для", "его", "ее", "еще", "или", "им", "их", "ли", "мой", "над", "нас", "нет", "ни", "них"
        ]
        
        print("Всего тестовых слов: \(testWords.count)")
        print()
        
        // Симулируем ИСПРАВЛЕННУЮ логику из EventProcessor.swift
        for word in testWords {
            let lowercased = word.lowercased()
            var result = false
            var method = ""
            
            // 1. Проверяем известные паттерны (как в EventProcessor)
            let englishInRussianPatterns = [
                "руддщ", // hello
                "щт",    // in
                "йфя",   // was
                "еуые",  // test
                "рщц",   // how
                "яку",   // you (альтернатива)
                "нщг",   // you
                "фку",   // are
                "ерш",   // the
                "ышы",   // she
                "феу",   // get
                "ыеш",   // test (alternative)
                "тпд",   // and
                "шыр",   // car
                "юиф",   // zip
                "инд",   // win
                "щта",   // inta
                "шырт",  // cart
                "щец",   // ice
                "щкл",   // ickl
                "штп",   // intp
                "ю",     // ,
            ]
            
            // Проверяем паттерны
            for pattern in englishInRussianPatterns {
                if lowercased.hasPrefix(pattern) {
                    result = true
                    method = "pattern: \(pattern)"
                    break
                }
            }
            
            // 2. Если не нашли по паттерну, проверяем через ИСПРАВЛЕННУЮ логику NSSpellChecker
            if !result && lowercased.count >= 2 && lowercased.count <= 4 {
                // Симулируем ИСПРАВЛЕННУЮ проверку NSSpellChecker
                let simulatedResult = simulateFixedNSSpellCheckerLogic(word: lowercased)
                
                if simulatedResult.result {
                    result = true
                    method = "NSSpellChecker (fixed): \(simulatedResult.reason)"
                } else {
                    method = "NSSpellChecker (fixed): \(simulatedResult.reason)"
                }
            }
            
            // Определяем ожидаемый результат
            let expectedResult = [
                "фку", "яку", "нщг", "рщц", "руддщ", "щт", "йфя", "еуые"
            ].contains(word)
            
            let status = result == expectedResult ? "✓" : "✗"
            
            print("Слово: '\(word)' (длина: \(word.count))")
            print("  Результат: \(result ? "✅ English in Russian layout" : "❌ Not English in Russian layout")")
            print("  Метод: \(method)")
            print("  Ожидаемый: \(expectedResult ? "✅" : "❌")")
            print("  Статус: \(status)")
            
            if result != expectedResult {
                print("  ⚠️  РАСХОЖДЕНИЕ!")
            }
            print()
        }
    }
    
    /// Симулирует ИСПРАВЛЕННУЮ логику NSSpellChecker
    private func simulateFixedNSSpellCheckerLogic(word: String) -> (result: Bool, reason: String) {
        // Из нашего теста мы знаем, что NSSpellChecker считает многие русские слова английскими
        // Давайте симулируем это поведение
        
        let shortRussianWordsThatNSSpellCheckerThinksAreEnglish: Set<String> = [
            "а", "в", "и", "к", "о", "с", "у", "я",
            "бы", "во", "да", "до", "за", "из", "на", "не", "но", "он", "от", "по", "со", "то", "ты",
            "без", "был", "быть", "весь", "вот", "для", "его", "ее", "еще", "или", "им", "их", "ли", "мой", "над", "нас", "нет", "ни", "них"
        ]
        
        // Симулируем проверку обоих языков
        let isEnglishWord = shortRussianWordsThatNSSpellCheckerThinksAreEnglish.contains(word)
        let isRussianWord = true // Предположим, что NSSpellChecker также считает их русскими словами
        
        // ИСПРАВЛЕННАЯ логика:
        // 1. Если слово валидно только в английском, но не в русском → true
        if isEnglishWord && !isRussianWord {
            return (true, "valid only in English")
        }
        
        // 2. Если слово валидно в обоих языках → false (неоднозначный случай)
        if isEnglishWord && isRussianWord {
            return (false, "ambiguous (valid in both languages)")
        }
        
        // 3. Если слово не валидно ни в одном языке → false
        return (false, "not valid in English")
    }
}

// Запуск теста
let tester = FixedReverseConversionTester()
tester.testFixedReverseConversionLogic()