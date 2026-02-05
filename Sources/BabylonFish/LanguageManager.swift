import Foundation
import Cocoa // For NSSpellChecker

enum Language {
    case english
    case russian
}

class LanguageManager {
    static let shared = LanguageManager()
    
    private let enUserKey = "bf_user_words_en"
    private let ruUserKey = "bf_user_words_ru"
    private let ignoredWordsKey = "bf_ignored_words"
    private var userWordsEN: [String: Int] = [:]
    private var userWordsRU: [String: Int] = [:]
    private var ignoredWords: Set<String> = []
    
    // NSSpellChecker instance
    private let spellChecker = NSSpellChecker.shared
    
    private init() {
        if let en = UserDefaults.standard.dictionary(forKey: enUserKey) as? [String: Int] {
            userWordsEN = en
        }
        if let ru = UserDefaults.standard.dictionary(forKey: ruUserKey) as? [String: Int] {
            userWordsRU = ru
        }
        if let ignored = UserDefaults.standard.array(forKey: ignoredWordsKey) as? [String] {
            ignoredWords = Set(ignored)
        }
    }
    
    // Simplified N-gram scores (log probabilities or frequency counts could be used here)
    // For this demo, we use a set of common bigrams/trigrams
    
    let commonRuBigrams: Set<String> = [
        "пр", "ри", "ив", "ве", "ет", "по", "ка", "то", "на", "не", "ст", "но", "ал", "ни",
        "ра", "го", "ко", "ов", "во", "ли", "ре", "ос", "од", "ва", "де", "ес", "за", "ль",
        "ль", "ел", "ем", "ен", "ер", "ес", "ет", "еч", "ею", "ея",
        "ом", "он", "оп", "ор", "ос", "от", "оф", "ох", "оц", "оч", "ош", "ощ", "ою", "оя",
        "ам", "ан", "ап", "ар", "ас", "ат", "аф", "ах", "ац", "ач", "аш", "ащ", "аю", "ая",
        "др", "ру", "уг", "га" // drug, druga
    ]
    
    let commonEnBigrams: Set<String> = [
        "th", "he", "in", "er", "an", "re", "on", "at", "en", "nd", "ti", "es", "or", "te", "of", "ed",
        "is", "it", "al", "ar", "st", "to", "nt", "ng", "se", "ha", "as", "ou", "io", "le", "ve", "me",
        "ea", "hi", "wa", "ro", "co", "ne", "de", "ri", "no", "us", "li", "ra", "ce", "ta", "ma"
    ]
    
    let commonEnglishWords: Set<String> = [
        "hello","world","test","please","thanks","thank","google","facebook","twitter","keyboard",
        "forget","and","the","this","that","with","are","you","what","how","who","which","from","into",
        "switch","layout","babylon","fish","babylonfish","work","home","email","password","login",
        "good","bad","yes","no","maybe","today","tomorrow","yesterday","time","date","year","month",
        "day","hour","minute","second","now","later","before","after","never","always","sometimes",
        "friend","friends","family","love","hate","like","dislike","want","need","have","has","had",
        "do","does","did","done","go","goes","gone","went","come","comes","came","coming",
        "say","says","said","saying","tell","tells","told","telling","speak","speaks","spoke","speaking",
        "look","looks","looked","looking","see","sees","saw","seen","seeing","watch","watches","watched",
        "hear","hears","heard","hearing","listen","listens","listened","listening",
        "think","thinks","thought","thinking","know","knows","knew","known","knowing",
        "lol","lmao","omg","wtf","brb","idk","imho","imo","tbh","btw","fyi","asap",
        "cool","nice","great","awesome","amazing","beautiful","ugly","bad","terrible","horrible",
        "sorry","excuse","pardon","please","thanks","thank","you","welcome","bye","goodbye"
    ]
    
    let commonRuShortWords: Set<String> = [
        "я","и","а","но","да","не","же","ли","э","ё","ей","её","мы","ты","вы","он","на","за",
        "по","со","из","от","до","во","об","у","к","с","в","о","ж","б","бы",
        "ну","эх","ой","ай","ух","ах","фу","фи","бе","ме","му","га","гав","мяу",
        "еще","ещё","уже","все","всё","кто","что","где","как","там","тут","так",
        "вот","вон","это","эта","этот","эти","тот","та","те","то","те",
        "мой","моя","моё","мои","твой","твоя","твоё","твои","наш","ващ",
        "спс","пжл","плз","ок","да","нет","мб","хз","лол","омг","втф","имхо",
        "прив","пок","ку","хай","йо","че","чо","шо","ща","щас","щаз",
        "друг", "рыбка", "эту"
    ]
    
    let ruSingletonLetters: Set<String> = [
        "э","ё","й","щ","ъ","ы","ю","я"
    ]
    
    // Impossible sequences (User's requirement "Dictionary of impossible combinations")
    // If these occur in one language, it's almost certainly the other.
    let impossibleRuInEnKeys: Set<String> = [
        "ghbd", "ghb", "nth", "cjd", "cjdf", "yt", "byl", "ntrc", "djp", "gj", "gjh",
        "ghb", "ghbd", "ghbdt", "ghbdtn", // priv, privet
        "plhf", "plhfd", "plhfdc", // zdravstv
        "cjdf", "cjd", // slov
        "rfr", "rfrbt", // kak, kakie
        "xt", "xtuj", // che, chego
        "ds", "z", "ns", // vy, ya, ty
        "ntrc", "ntrcn", // teks, tekst
        "gjxt", "gjxtve", // poche, pochemu
        "gkj", "gkj[", // plo, ploh
        "[jh", "[jhj", // hor, horo
        "bpd", "bpdby", // izv, izvin
        "cgfc", "cgfcb" // spas, spasi
    ]
    
    // Reverse impossible: Looks like RU but is EN keys
    // e.g. "руддщ" -> "hello" (RU keys)
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
    
    func getSuggestion(for keyCodes: [Int]) -> String? {
        guard keyCodes.count >= 2 else { return nil }
        
        var enString = ""
        var ruString = ""
        
        for code in keyCodes {
            if let chars = KeyMapper.shared.getChars(for: code) {
                enString += chars.en
                ruString += chars.ru
            }
        }
        
        let enLower = enString.lowercased()
        let ruLower = ruString.lowercased()
        
        // 1. Check for "impossible" patterns (Strong Correction)
        // If we typed "ghb" (EN chars) but it's clearly "при" (RU chars)
        // Note: We don't know the current layout here, but we can return the "other" likely word
        
        // 2. Autocomplete User Words
        // Check EN User Words
        for (word, count) in userWordsEN where count >= 2 {
            if word.hasPrefix(enLower) && word.count > enLower.count {
                return word // Autocomplete EN
            }
        }
        // Check RU User Words
        for (word, count) in userWordsRU where count >= 2 {
            if word.hasPrefix(ruLower) && word.count > ruLower.count {
                return word // Autocomplete RU
            }
        }
        
        // 3. Autocomplete Common Words
        // EN
        for word in commonEnglishWords {
            if word.hasPrefix(enLower) && word.count > enLower.count {
                return word
            }
        }
        // RU (Short words are too short, need a bigger dictionary really, but let's try)
        for word in commonRuShortWords {
            if word.hasPrefix(ruLower) && word.count > ruLower.count {
                return word
            }
        }
        
        // 4. Correction (Cross-layout completion)
        // e.g. "ghb" -> "hello" (if "ghb" was meant to be "hel"?? No)
        // e.g. "ghb" -> "привет" (if "ghb" maps to "при")
        
        // Check if EN string is a prefix of a RU word (typed on EN layout but meant RU)
        // Wait, "ghb" -> "при". "при" -> "привет".
        // So we check if `ruLower` (mapped from keys) starts a RU word.
        for word in commonRuShortWords {
            if word.hasPrefix(ruLower) && word.count > ruLower.count {
                return word // Correction to RU
            }
        }
        
        // Check if RU string is a prefix of an EN word (typed on RU layout but meant EN)
        // e.g. "рудд" -> "hell". "hell" -> "hello"
        for word in commonEnglishWords {
            if word.hasPrefix(enLower) && word.count > enLower.count {
                return word // Correction to EN
            }
        }
        
        return nil
    }

    // Helper: Check if word exists in system dictionary
    private func isSystemWord(_ word: String, language: String) -> Bool {
        // "en_US" or "ru_RU"
        // setLanguage is not thread safe? checkSpelling is better
        // checkSpelling returns range of misspelled word. If NSNotFound, it's correct.
        
        // Use a temp checker or shared? Shared is fine for main thread.
        // We are on main thread usually (EventTap callback).
        
        let range = spellChecker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return range.location == NSNotFound
    }
    
    // Suggest correction for a word in a specific language
    func suggestCorrection(for word: String, language: Language) -> String? {
        let langCode = (language == .russian) ? "ru_RU" : "en_US"
        
        // 1. Check if word is already valid
        if isSystemWord(word, language: langCode) {
            return nil
        }
        
        // 2. Get candidates
        // correction(forWordRange:in:language:inSpellDocumentWithTag:) returns the single best guess
        let range = NSRange(location: 0, length: word.utf16.count)
        let correction = spellChecker.correction(forWordRange: range, in: word, language: langCode, inSpellDocumentWithTag: 0)
        
        // Only return if it's different (it should be, since we checked isSystemWord, but safety first)
        if let correction = correction, correction != word {
            logDebug("Correction found for '\(word)' (\(langCode)): \(correction)")
            return correction
        }
        
        return nil
    }

    func detectLanguage(for keyCodes: [Int]) -> Language? {
        guard keyCodes.count >= 1 else { return nil }
        
        var enString = ""
        var ruString = ""
        
        for code in keyCodes {
            if let chars = KeyMapper.shared.getChars(for: code) {
                enString += chars.en
                ruString += chars.ru
            }
        }
        
        logDebug("Analyzing buffer: EN='\(enString)', RU='\(ruString)'")
        
        let enLower = enString.lowercased()
        let ruLower = ruString.lowercased()
        let count = keyCodes.count
        
        // 1. Check common dictionaries (Fast Path)
        if commonRuShortWords.contains(ruLower) {
            logDebug("Common Russian Short Word Match: \(ruLower)")
            return .russian
        }
        
        if commonEnglishWords.contains(enLower) {
            logDebug("Common English Word Match: \(enLower)")
            return .english
        }
        
        // 2. Check Exceptions (Ignored words)
        if ignoredWords.contains(enLower) || ignoredWords.contains(ruLower) {
            logDebug("Ignored word detected: \(enLower)/\(ruLower)")
            return nil
        }
        
        // 3. System Dictionary Check (The "ML/Big Dictionary" Layer)
        // Check RU
        let isRuValid = isSystemWord(ruLower, language: "ru_RU")
        let isEnValid = isSystemWord(enLower, language: "en_US")
        
        if isRuValid && !isEnValid {
            logDebug("System Dictionary: RU Valid ('\(ruLower)'), EN Invalid -> RU")
            return .russian
        }
        
        if isEnValid && !isRuValid {
            logDebug("System Dictionary: EN Valid ('\(enLower)'), RU Invalid -> EN")
            return .english
        }
        
        if isRuValid && isEnValid {
            logDebug("System Dictionary: Both Valid ('\(ruLower)' / '\(enLower)'). Falling back to bigrams/heuristics.")
        }
        
        if count == 1 {
            if ruSingletonLetters.contains(ruLower) || commonRuShortWords.contains(ruLower) {
                return .russian
            }
        }
        if count == 2 {
            if commonRuShortWords.contains(ruLower) {
                return .russian
            }
            if commonEnglishWords.contains(enLower) {
                return .english
            }
        }
        
        // 3. Check strict impossible/strong indicators
        // Check for strong matches in the *beginning* or *end* of the string
        // Actually, just substring check is fine for short buffers
        
        for pattern in impossibleRuInEnKeys where pattern.count >= 3 {
            if enString.contains(pattern) {
                logDebug("Detected Impossible Pattern (RU intent): \(pattern) in \(enString)")
                return .russian
            }
        }
        
        for pattern in impossibleEnInRuKeys where pattern.count >= 4 {
            if ruString.contains(pattern) {
                logDebug("Detected Impossible Pattern (EN intent): \(pattern) in \(ruString)")
                return .english
            }
        }
        
        // 4. Check user-learned words
        if let enCount = userWordsEN[enLower], enCount >= 2 {
            logDebug("User Learned Word (EN): \(enLower) count=\(enCount)")
            return .english
        }
        if let ruCount = userWordsRU[ruLower], ruCount >= 2 {
            logDebug("User Learned Word (RU): \(ruLower) count=\(ruCount)")
            return .russian
        }
        
        // 4. Simple heuristic: Count valid bigrams
        let enScore = countBigrams(enString, dictionary: commonEnBigrams)
        let ruScore = countBigrams(ruString, dictionary: commonRuBigrams)
        
        logDebug("Scores: EN=\(enScore), RU=\(ruScore)")
        
        // Threshold logic
        // If one score is significantly higher, switch.
        // We lower the threshold to 1 (meaning > is enough if difference is clear)
        // Or even 0 if the other is 0.
        
        if ruScore > 0 && enScore == 0 {
             logDebug("Score Analysis (Clear Winner): RU:\(ruScore) vs EN:0 -> RU")
             return .russian
        }
        
        if enScore > 0 && ruScore == 0 {
             logDebug("Score Analysis (Clear Winner): EN:\(enScore) vs RU:0 -> EN")
             return .english
        }
        
        if ruScore > enScore + 1 {
            logDebug("Score Analysis: RU:\(ruScore) vs EN:\(enScore) for keys: \(keyCodes) -> RU")
            return .russian
        } else if enScore > ruScore + 1 {
            logDebug("Score Analysis: RU:\(ruScore) vs EN:\(enScore) for keys: \(keyCodes) -> EN")
            return .english
        }
        
        return nil
    }
    
    func learnDecision(target: Language, enWord: String, ruWord: String) {
        let enLower = enWord.lowercased()
        let ruLower = ruWord.lowercased()
        switch target {
        case .english:
            let val = (userWordsEN[enLower] ?? 0) + 1
            userWordsEN[enLower] = val
            UserDefaults.standard.set(userWordsEN, forKey: enUserKey)
            logDebug("Learned EN word: \(enLower) -> \(val)")
        case .russian:
            let val = (userWordsRU[ruLower] ?? 0) + 1
            userWordsRU[ruLower] = val
            UserDefaults.standard.set(userWordsRU, forKey: ruUserKey)
            logDebug("Learned RU word: \(ruLower) -> \(val)")
        }
    }
    
    func unlearnDecision(target: Language, enWord: String, ruWord: String) {
        let enLower = enWord.lowercased()
        let ruLower = ruWord.lowercased()
        
        var remainingCount = 0
        var foundInUser = false
        
        // "Inverse Learning": If user rejected one language, they likely wanted the other.
        // If we unlearn EN, we should learn RU.
        // If we unlearn RU, we should learn EN.
        
        switch target {
        case .english:
            // 1. Unlearn English
            if let count = userWordsEN[enLower], count > 0 {
                foundInUser = true
                remainingCount = count - 1
                if remainingCount == 0 {
                    userWordsEN.removeValue(forKey: enLower)
                } else {
                    userWordsEN[enLower] = remainingCount
                }
                UserDefaults.standard.set(userWordsEN, forKey: enUserKey)
                logDebug("Unlearned EN word: \(enLower) -> \(remainingCount)")
            }
            
            // If it's effectively removed from user learning (or never was there), check if we need to ignore it
            // FORCE ignore if unlearned count hits 0 (user explicitly rejected it)
            if !foundInUser || remainingCount == 0 {
                 logDebug("Adding EN word to exceptions (rejected by user): \(enLower)")
                 ignoredWords.insert(enLower)
                 UserDefaults.standard.set(Array(ignoredWords), forKey: ignoredWordsKey)
            }
            
            // 2. Implicitly Learn Russian (Active Learning)
            // If the user rejected EN "lheu" (keys for "друг"), they probably wanted RU "друг".
            // Only learn if it's not already in common words (to avoid bloating user dict)
            if !commonRuShortWords.contains(ruLower) {
                let val = (userWordsRU[ruLower] ?? 0) + 1
                userWordsRU[ruLower] = val
                UserDefaults.standard.set(userWordsRU, forKey: ruUserKey)
                logDebug("Implicitly Learned RU word (via rejection): \(ruLower) -> \(val)")
            }
            
        case .russian:
            // 1. Unlearn Russian
            if let count = userWordsRU[ruLower], count > 0 {
                foundInUser = true
                remainingCount = count - 1
                if remainingCount == 0 {
                    userWordsRU.removeValue(forKey: ruLower)
                } else {
                    userWordsRU[ruLower] = remainingCount
                }
                UserDefaults.standard.set(userWordsRU, forKey: ruUserKey)
                logDebug("Unlearned RU word: \(ruLower) -> \(remainingCount)")
            }
            
            // If it's effectively removed from user learning (or never was there), check if we need to ignore it
            // FORCE ignore if unlearned count hits 0 (user explicitly rejected it)
            if !foundInUser || remainingCount == 0 {
                 logDebug("Adding RU word to exceptions (rejected by user): \(ruLower)")
                 ignoredWords.insert(ruLower)
                 UserDefaults.standard.set(Array(ignoredWords), forKey: ignoredWordsKey)
            }
            
            // 2. Implicitly Learn English (Active Learning)
            if !commonEnglishWords.contains(enLower) {
                let val = (userWordsEN[enLower] ?? 0) + 1
                userWordsEN[enLower] = val
                UserDefaults.standard.set(userWordsEN, forKey: enUserKey)
                logDebug("Implicitly Learned EN word (via rejection): \(enLower) -> \(val)")
            }
        }
    }
    
    private func countBigrams(_ text: String, dictionary: Set<String>) -> Int {
        var count = 0
        let chars = Array(text)
        if chars.count < 2 { return 0 }
        
        // Weighted scoring: First bigram gets +2 bonus
        // User logic: "Mistakes happen at start" -> Start matches are more important?
        // Actually, if I start typing "gh" (pr) -> "ghiv" (priv), the start is strong RU indicator (if gh is impossible in EN start).
        // But here we check against "Common Bigrams".
        // If "gh" is common in EN? Yes (ghost).
        // If "pr" is common in RU? Yes (privet).
        
        // Let's just give extra weight to the first 2 bigrams to align with user intuition.
        
        for i in 0..<(chars.count - 1) {
            let bigram = String(chars[i...i+1])
            if dictionary.contains(bigram) {
                // Base score
                var score = 1
                
                // Bonus for start of word (first 2 bigrams)
                if i < 2 {
                    score += 2 // Total 3
                }
                
                count += score
            }
        }
        return count
    }
}
