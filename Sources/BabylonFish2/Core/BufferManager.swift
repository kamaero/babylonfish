import Foundation
import Cocoa

/// Управляет буфером нажатых клавиш
class BufferManager {
    struct KeyInfo: CustomStringConvertible {
        let code: Int
        let flags: CGEventFlags
        var description: String {
            return "{code:\(code), flags:\(flags.rawValue)}"
        }
    }
    
    private var keyBuffer: [KeyInfo] = []
    private var maxBufferLength = 15
    
    var count: Int { keyBuffer.count }
    var isEmpty: Bool { keyBuffer.isEmpty }
    var snapshot: [KeyInfo] { keyBuffer }
    
    /// Добавляет клавишу в буфер
    func addKey(code: Int, flags: CGEventFlags) {
        keyBuffer.append(KeyInfo(code: code, flags: flags))
        if keyBuffer.count > maxBufferLength {
            keyBuffer.removeFirst()
        }
    }
    
    /// Удаляет последнюю клавишу
    func removeLast() {
        if !keyBuffer.isEmpty {
            keyBuffer.removeLast()
        }
    }
    
    /// Очищает буфер
    func clear() {
        keyBuffer.removeAll()
    }
    
    /// Устанавливает максимальный размер буфера
    func setMaxBufferLength(_ length: Int) {
        maxBufferLength = max(1, length) // Минимум 1
        logDebug("BufferManager: maxBufferLength set to \(maxBufferLength)")
        
        // Удаляем лишние элементы если нужно
        while keyBuffer.count > maxBufferLength {
            keyBuffer.removeFirst()
        }
    }
    
    /// Возвращает отфильтрованные коды клавиш (только буквы)
    func filteredLetterCodes() -> [Int] {
        keyBuffer.compactMap { info -> Int? in
            guard let chars = KeyMapper.shared.getChars(for: info.code) else { return nil }
            if isLetter(chars.en) || isLetter(chars.ru) {
                return info.code
            }
            return nil
        }
    }
    
    /// Проверяет, является ли символ буквой
    private func isLetter(_ s: String) -> Bool {
        guard let scalar = s.unicodeScalars.first else { return false }
        return CharacterSet.letters.contains(scalar)
    }
}