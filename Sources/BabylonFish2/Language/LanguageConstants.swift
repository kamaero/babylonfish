import Foundation

struct LanguageConstants {
    static let commonRuBigrams: Set<String> = [
        "пр", "ри", "ив", "ве", "ет", "по", "ка", "то", "на", "не", "ст", "но", "ал", "ни",
        "ра", "го", "ко", "ов", "во", "ли", "ре", "ос", "од", "ва", "де", "ес", "за", "ль",
        "ль", "ел", "ем", "ен", "ер", "ес", "ет", "еч", "ею", "ея",
        "ом", "он", "оп", "ор", "ос", "от", "оф", "ох", "оц", "оч", "ош", "ощ", "ою", "оя",
        "ам", "ан", "ап", "ар", "ас", "ат", "аф", "ах", "ац", "ач", "аш", "ащ", "аю", "ая",
        "др", "ру", "уг", "га"
    ]
    
    static let commonEnBigrams: Set<String> = [
        "th", "he", "in", "er", "an", "re", "on", "at", "en", "nd", "ti", "es", "or", "te", "of", "ed",
        "is", "it", "al", "ar", "st", "to", "nt", "ng", "se", "ha", "as", "ou", "io", "le", "ve", "me",
        "ea", "hi", "wa", "ro", "co", "ne", "de", "ri", "no", "us", "li", "ra", "ce", "ta", "ma"
    ]
    
    static let commonEnglishWords: Set<String> = [
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
    
    static let commonRuShortWords: Set<String> = [
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
    
    static let ruSingletonLetters: Set<String> = [
        "э","ё","й","щ","ъ","ы","ю","я"
    ]
    
    static let impossibleRuInEnKeys: Set<String> = [
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
    
    static let impossibleEnInRuKeys: Set<String> = [
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
    
    static let programmingKeywords: Set<String> = [
        "func", "var", "let", "if", "else", "guard", "return", "class", "struct", "enum",
        "import", "public", "private", "extension", "protocol", "init", "deinit", "subscript",
        "typealias", "associatedtype", "break", "case", "continue", "default", "defer", "do",
        "fallthrough", "for", "in", "repeat", "switch", "where", "while", "as", "catch", "false",
        "is", "nil", "rethrows", "super", "self", "Self", "throw", "throws", "true", "try",
        "int", "double", "string", "bool", "void", "float", "char", "const", "static", "final",
        "print", "println", "console", "log", "debug", "error", "warn", "info",
        "function", "const", "await", "async", "export", "default", "from", "null", "undefined",
        "val", "fun", "package", "interface", "implements", "extends", "protected", "abstract"
    ]
}