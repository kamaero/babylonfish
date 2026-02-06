import Foundation
import Cocoa
import Carbon

/// Управляет переключением раскладок и отправкой клавиш
class LayoutSwitcher {
    
    /// Переключает на раскладку, содержащую указанный идентификатор
    func switchToInputSource(containing partialID: String) -> Bool {
        let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        
        for source in sources {
            let category = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory)
            if let catPtr = category {
                let catStr = Unmanaged<CFString>.fromOpaque(catPtr).takeUnretainedValue() as String
                if catStr == "TISCategoryKeyboardInputSource" {
                    
                    if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                        let sourceID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
                        
                        var localizedName = ""
                        if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                            localizedName = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
                        }

                        let isEnglishCandidate =
                            sourceID.contains("US") ||
                            sourceID.contains("ABC") ||
                            sourceID.contains("British") ||
                            localizedName.localizedCaseInsensitiveContains("ABC") ||
                            localizedName.localizedCaseInsensitiveContains("U.S.") ||
                            localizedName.localizedCaseInsensitiveContains("US")

                        if sourceID.contains(partialID) || (partialID == "English" && isEnglishCandidate) {
                             logDebug("Found matching source: \(sourceID). Selecting...")
                             let err = TISSelectInputSource(source)
                             if err == noErr {
                                 return true
                             } else {
                                 logDebug("Error selecting source: \(err)")
                             }
                        }
                    }
                }
            }
        }
        return false
    }
    
    /// Отправляет нажатие клавиши
    func sendKey(_ keyCode: Int, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let eventDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let eventUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) else { return }
        
        eventDown.flags = flags
        eventUp.flags = flags
        
        eventDown.setIntegerValueField(.eventSourceUserData, value: 0xBAB7)
        eventUp.setIntegerValueField(.eventSourceUserData, value: 0xBAB7)
        
        let loc = CGEventTapLocation.cghidEventTap
        eventDown.post(tap: loc)
        eventUp.post(tap: loc)
    }
    
    /// Удаляет указанное количество символов (backspace)
    func deleteCharacters(_ count: Int) {
        logDebug("Deleting \(count) characters...")
        for _ in 0..<count {
            sendKey(51) // Backspace
            usleep(500)
        }
    }
    
    /// Перепечатывает буфер клавиш
    func retypeBuffer(_ buffer: [BufferManager.KeyInfo]) {
        logDebug("Re-typing \(buffer.count) keys...")
        for info in buffer {
            sendKey(info.code, flags: info.flags)
            usleep(500)
        }
    }
    
    /// Получает идентификатор текущей раскладки
    func getCurrentInputSourceId() -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        }
        return nil
    }
}