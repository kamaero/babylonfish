import Foundation

// Тест раннего определения языка по биграммам/триграммам

let russianBigrams = ["gh", "rj", "pl", "nt", "yf", "kb", "uj", "gb", "db", "el"]
let russianTrigrams = ["ghb", "rfr", "plh", "ntc", "yfl", "kbr", "ujd", "gbt", "dbt", "elt"]

let englishBigrams = ["th", "he", "in", "er", "an", "re", "nd", "at", "on", "nt"]
let englishTrigrams = ["the", "and", "ing", "her", "hat", "his", "ere", "for", "ent", "ion"]

func testWord(_ word: String) {
    let lowercased = word.lowercased()
    
    print("Testing word: '\(word)'")
    
    // Проверяем биграммы
    if lowercased.count >= 2 {
        let bigram = String(lowercased.prefix(2))
        if russianBigrams.contains(bigram) {
            print("  ✅ Russian bigram detected: '\(bigram)'")
        }
        if englishBigrams.contains(bigram) {
            print("  ✅ English bigram detected: '\(bigram)'")
        }
    }
    
    // Проверяем триграммы
    if lowercased.count >= 3 {
        let trigram = String(lowercased.prefix(3))
        if russianTrigrams.contains(trigram) {
            print("  ✅ Russian trigram detected: '\(trigram)'")
        }
        if englishTrigrams.contains(trigram) {
            print("  ✅ English trigram detected: '\(trigram)'")
        }
    }
    
    // Проверяем подозрительные начала
    let russianSuspicious = ["gh", "ghb", "ghbd", "rj", "rfr", "plh", "plhf", "ntcn", "yf"]
    let englishSuspicious = ["руд", "рудд", "щт", "щты", "йфя", "йфяч"]
    
    for start in russianSuspicious {
        if lowercased.hasPrefix(start) {
            print("  ⚠️  Suspicious Russian start: '\(start)'")
        }
    }
    
    for start in englishSuspicious {
        if lowercased.hasPrefix(start) {
            print("  ⚠️  Suspicious English start: '\(start)'")
        }
    }
    
    print()
}

// Тестовые слова
testWord("ghbdtn")  // привет
testWord("rfr")     // как
testWord("plhf")    // йцук
testWord("ntcn")    // нету
testWord("yfl")     // было

testWord("the")
testWord("and")
testWord("hello")
testWord("world")

// Смешанные случаи
testWord("ghost")   // начинается с "gh" но это английское слово
testWord("ghb")     // русская триграмма
testWord("theater") // английская триграмма