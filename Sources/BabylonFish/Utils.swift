import Foundation
import Carbon

class KeyMapper {
    static let shared = KeyMapper()
    
    // Mapping from Virtual Keycode to (English, Russian) characters
    // This is a simplified map for standard QWERTY/JCUKEN
    let map: [Int: (en: String, ru: String)] = [
        0: ("a", "ф"), 1: ("s", "ы"), 2: ("d", "в"), 3: ("f", "а"), 4: ("h", "р"), 5: ("g", "п"),
        6: ("z", "я"), 7: ("x", "ч"), 8: ("c", "с"), 9: ("v", "м"), 11: ("b", "и"),
        12: ("q", "й"), 13: ("w", "ц"), 14: ("e", "у"), 15: ("r", "к"), 16: ("y", "н"), 17: ("t", "е"),
        31: ("o", "щ"), 32: ("u", "г"), 34: ("i", "ш"), 35: ("p", "з"), 37: ("l", "д"),
        38: ("j", "о"), 40: ("k", "л"), 41: (";", "ж"), 39: ("'", "э"),
        45: ("n", "т"), 46: ("m", "ь"), 43: (",", "б"), 47: (".", "ю"), 50: ("`", "ё"),
        33: ("[", "х"), 30: ("]", "ъ"), 42: ("\\", "\\"),
        18: ("1", "1"), 19: ("2", "2"), 20: ("3", "3"), 21: ("4", "4"), 23: ("5", "5"),
        22: ("6", "6"), 26: ("7", "7"), 28: ("8", "8"), 25: ("9", "9"), 29: ("0", "0"),
        27: ("-", "-"), 24: ("=", "=")
    ]
    
    func getChars(for keyCode: Int) -> (en: String, ru: String)? {
        return map[keyCode]
    }
}

func getCurrentInputSourceId() -> String? {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
    return nil
}

func switchToInputSource(withId id: String) {
    let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
    if let source = sources.first(where: {
        guard let ptr = TISGetInputSourceProperty($0, kTISPropertyInputSourceID) else { return false }
        let sourceId = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        return sourceId == id
    }) {
        TISSelectInputSource(source)
    }
}
