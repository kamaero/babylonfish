import Foundation
import Cocoa

/// Язык раскладки
enum Language: String, Codable {
    case english = "english"
    case russian = "russian"
}

/// Комбинация клавиш
struct KeyCombo: Codable {
    var keyCode: Int
    var modifiers: UInt64 // CGEventFlags не Codable, используем rawValue
    
    init(keyCode: Int, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
    }
    
    var cgEventFlags: CGEventFlags {
        return CGEventFlags(rawValue: modifiers)
    }
}