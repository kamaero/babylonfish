#!/usr/bin/env swift

import Foundation

/// Тестирование логики обратной конверсии
class ReverseConversionTester {
    
    /// Тестирует логику isEnglishWordInRussianLayout
    func testReverseConversionLogic() {
        print("=== Тестирование логики обратной конверсии ===")
        print()
        
        // Тестовые слова
        let testWords = [
            // Английские слова в русской раскладке
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
            "а", "в", "и", "к", "о", "с", "у", "я",
            "бы", "во", "да", "до", "за", "из", "на", "не", "но", "он", "от", "по", "со", "то", "ты",
            "без", "был", "быть", "весь", "вот", "для", "его", "ее", "еще", "или", "им", "их", "ли", "мой", "над", "нас", "нет", "ни", "них"
        ]
        
        print("Всего тестовых слов: \(testWords.count)")
        print()
        
        // Симулируем логику из EventProcessor.swift
        for word in testWords {
            let lowercased = word.lowercased()
            var result = false
            var method = ""
            
            // 1. Проверяем известные паттерны
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
            
            // 2. Если не нашли по паттерну, проверяем через NSSpellChecker (симулируем)
            if !result && lowercased.count >= 2 && lowercased.count <= 4 {
                // Симулируем проверку NSSpellChecker
                // Из нашего теста мы знаем, что NSSpellChecker считает многие русские слова английскими
                let simulatedNSSpellCheckerResult = simulateNSSpellChecker(word: lowercased)
                
                if simulatedNSSpellCheckerResult {
                    result = true
                    method = "NSSpellChecker (simulated)"
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
    
    /// Симулирует работу NSSpellChecker
    private func simulateNSSpellChecker(word: String) -> Bool {
        // Из нашего теста мы знаем, что NSSpellChecker считает многие русские слова английскими
        // Давайте симулируем это поведение
        
        let shortRussianWordsThatNSSpellCheckerThinksAreEnglish: Set<String> = [
            "а", "в", "и", "к", "о", "с", "у", "я",
            "бы", "во", "да", "до", "за", "из", "на", "не", "но", "он", "от", "по", "со", "то", "ты",
            "без", "был", "быть", "весь", "вот", "для", "его", "ее", "еще", "или", "им", "их", "ли", "мой", "над", "нас", "нет", "ни", "них"
        ]
        
        // Если это короткое русское слово, NSSpellChecker вероятно считает его английским
        if shortRussianWordsThatNSSpellCheckerThinksAreEnglish.contains(word) {
            return true
        }
        
        // Для других слов возвращаем false (упрощённая симуляция)
        return false
    }
}

// Запуск теста
let tester = ReverseConversionTester()
tester.testReverseConversionLogic()