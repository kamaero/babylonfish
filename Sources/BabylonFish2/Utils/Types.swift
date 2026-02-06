import Foundation
import Cocoa

/// Язык раскладки
enum Language {
    case english
    case russian
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