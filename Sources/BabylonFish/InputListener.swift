import Foundation
import Cocoa
import Carbon
import os
import os.signpost

class InputListener {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Buffer for analysis
    private struct KeyInfo: CustomStringConvertible {
        let code: Int
        let flags: CGEventFlags
        var description: String {
            return "{code:\(code), flags:\(flags.rawValue)}"
        }
    }
    private var keyBuffer: [KeyInfo] = []
    private let maxBufferLength = 15
    
    // Double Shift Detection
    private var lastShiftTime: TimeInterval = 0
    private let doubleShiftThreshold: TimeInterval = 0.3
    
    // State
    private var isProcessing = false
    private var switchingDisabled = false
    private var startedAt: TimeInterval = 0
    private var keyDownEventsSeen = 0
    private var flagsChangedEventsSeen = 0
    private var reportedMissingKeyDown = false
    private var pendingAutoSwitchWorkItem: DispatchWorkItem?
    private let autoSwitchIdleDelay: TimeInterval = 0.35
    private var lastBoundaryAt: TimeInterval = 0
    private let boundaryDebounce: TimeInterval = 0.12
    
    // Undo Learning
    private struct LastSwitchInfo {
        let timestamp: TimeInterval
        let targetLang: Language
        let enWord: String
        let ruWord: String
        let length: Int
    }
    private var lastSwitch: LastSwitchInfo?
    private var consecutiveBackspaceCount = 0
    
    weak var suggestionWindow: SuggestionWindow?
    private var currentSuggestion: String?
    
    var autoSwitchEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "autoSwitchEnabled")
    }
    
    @discardableResult
    func start() -> Bool {
        logDebug("Starting InputListener...")
        
        // Force enable if currently disabled (to ensure it works for the user)
        if !autoSwitchEnabled {
            logDebug("WARNING: autoSwitchEnabled was false. Forcing it to TRUE.")
            UserDefaults.standard.set(true, forKey: "autoSwitchEnabled")
        }
        
        startedAt = Date().timeIntervalSince1970
        keyDownEventsSeen = 0
        flagsChangedEventsSeen = 0
        reportedMissingKeyDown = false
        // Mask for KeyDown and FlagsChanged
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        logDebug("Creating event tap with mask: \(eventMask)")
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    logDebug("ERROR: refcon is nil in callback!")
                    return Unmanaged.passRetained(event)
                }
                let listener = Unmanaged<InputListener>.fromOpaque(refcon).takeUnretainedValue()
                return listener.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logDebug("CRITICAL: Failed to create event tap. Check Accessibility permissions.")
            print("Failed to create event tap. Check Accessibility permissions.")
            return false
        }
        
        self.eventTap = eventTap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Enable the tap
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        // Verify it's actually enabled
        let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
        logDebug("Event tap created. Enabled status: \(isEnabled)")
        
        if !isEnabled {
            logDebug("WARNING: Tap was created but is not enabled! Trying to enable again...")
            CGEvent.tapEnable(tap: eventTap, enable: true)
            let isEnabledNow = CGEvent.tapIsEnabled(tap: eventTap)
            logDebug("After re-enable attempt: \(isEnabledNow)")
        }
        
        // Set up a timer to periodically check if tap is still enabled
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkTapStatus()
        }
        
        return true
    }
    
    private func checkTapStatus() {
        guard let tap = eventTap else { return }
        let isEnabled = CGEvent.tapIsEnabled(tap: tap)
        if !isEnabled {
            logDebug("WARNING: Event tap was disabled by system! Re-enabling...")
            CGEvent.tapEnable(tap: tap, enable: true)
            let isEnabledNow = CGEvent.tapIsEnabled(tap: tap)
            logDebug("Re-enable result: \(isEnabledNow)")
        }

        let uptime = Date().timeIntervalSince1970 - startedAt
        if uptime >= 10, !reportedMissingKeyDown, flagsChangedEventsSeen > 0, keyDownEventsSeen == 0 {
            reportedMissingKeyDown = true
            logDebug("WARNING: flagsChanged events are received, but keyDown events are not. Check macOS Privacy & Security -> Input Monitoring for BabylonFish, and ensure Secure Input is not enabled by another app.")
        }
    }
    
    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logDebug("WARNING: Event tap disabled by system (type=\(type.rawValue)). Re-enabling...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        }

        logDebug("Event received: type=\(type.rawValue)")
        
        if type == .flagsChanged {
            flagsChangedEventsSeen += 1
            handleFlagsChanged(event)
            return Unmanaged.passRetained(event)
        }
        
        if type == .keyDown {
            keyDownEventsSeen += 1
            // Ignore if we are the ones synthesizing events (to avoid loops)
            if event.getIntegerValueField(.eventSourceUserData) == 0xBAB7 {
                logDebug("Ignoring synthesized event")
                return Unmanaged.passRetained(event)
            }
            
            return handleKeyDown(event, proxy: proxy)
        }
        
        return Unmanaged.passRetained(event)
    }
    
    private func handleFlagsChanged(_ event: CGEvent) {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Check for Left Shift (KeyCode 56)
        if keyCode == 56 {
            // If shift is pressed (not released)
            if flags.contains(.maskShift) {
                let now = Date().timeIntervalSince1970
                if now - lastShiftTime < doubleShiftThreshold {
                    // Double Shift Detected!
                    handleDoubleShift()
                }
                lastShiftTime = now
            }
        }
    }
    
    private func handleKeyDown(_ event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) == 1
        
        // Always ignore modifiers (cmd/ctrl/opt/shift are handled in flagsChanged usually, but sometimes keyDown appears?)
        // Actually keyDown for modifiers usually doesn't happen, but let's be safe.
        // If Command or Control is pressed, we probably shouldn't track this word.
        if event.flags.contains(.maskCommand) || event.flags.contains(.maskControl) {
            keyBuffer.removeAll()
            consecutiveBackspaceCount = 0
            return Unmanaged.passRetained(event)
        }

        // 1. Handle Special Keys
        // Backspace (51)
        if keyCode == 51 {
            consecutiveBackspaceCount += 1
            checkUndoLearning()
            
            if !keyBuffer.isEmpty {
                keyBuffer.removeLast()
            }
            updateSuggestion()
            return Unmanaged.passRetained(event)
        }
        
        // Any other key resets the backspace count
        consecutiveBackspaceCount = 0
        
        // Reset keys: Esc (53), Tab (48), Arrows (123-126)
        if keyCode == 53 || keyCode == 48 || (keyCode >= 123 && keyCode <= 126) {
            keyBuffer.removeAll()
            switchingDisabled = false // Reset disabled state on navigation
            clearSuggestion()
            return Unmanaged.passRetained(event)
        }
        
        if isAutoRepeat { return Unmanaged.passRetained(event) }
        
        // 2. Check if password field
        if isSecureField() {
            keyBuffer.removeAll()
            return Unmanaged.passRetained(event)
        }
        
        // 3. Word boundary: Space (49) or Enter (36)
        if keyCode == 49 || keyCode == 36 {
             if keyCode == 36, let suggestion = currentSuggestion {
                 applySuggestion(suggestion)
                 return nil
             }
             clearSuggestion()

             // Word boundary
             let now = Date().timeIntervalSince1970
            if now - lastBoundaryAt < boundaryDebounce { return Unmanaged.passRetained(event) }
            lastBoundaryAt = now
            
            // Process buffer before clearing
            var consumed = false
            if !keyBuffer.isEmpty {
                logDebug("Word boundary (Space/Enter). Processing buffer: \(keyBuffer)")
                consumed = processBuffer(proxy: proxy, triggerKeyCode: keyCode)
            }
            
            keyBuffer.removeAll()
            switchingDisabled = false
            
            if consumed {
                return nil
            } else {
                return Unmanaged.passRetained(event)
            }
        }
        
        // 4. Regular characters
        // We add ALL other keys to buffer to maintain correct length for backspacing,
        // even if we don't use them for language detection (like numbers).
        keyBuffer.append(KeyInfo(code: keyCode, flags: event.flags))
        if keyBuffer.count > maxBufferLength {
            keyBuffer.removeFirst()
        }
        
        // Debug info for known chars
        if let chars = KeyMapper.shared.getChars(for: keyCode) {
            logDebug("Key: \(keyCode) -> en:'\(chars.en)' ru:'\(chars.ru)'")
        }
        
        updateSuggestion()
        
        return Unmanaged.passRetained(event)
    }

    private func updateSuggestion() {
        guard let window = suggestionWindow else { return }
        
        // Filter keys like in processBuffer
        let filteredCodes = keyBuffer.compactMap { info -> Int? in
             if let chars = KeyMapper.shared.getChars(for: info.code), (isLetter(chars.en) || isLetter(chars.ru)) {
                 return info.code
             }
             return nil
        }
        
        if let suggestion = LanguageManager.shared.getSuggestion(for: filteredCodes) {
            currentSuggestion = suggestion
            DispatchQueue.main.async {
                let loc = NSEvent.mouseLocation
                // Show below mouse cursor
                let point = CGPoint(x: loc.x, y: loc.y - 40)
                window.showSuggestion(suggestion, at: point)
            }
        } else {
            clearSuggestion()
        }
    }
    
    private func clearSuggestion() {
        currentSuggestion = nil
        DispatchQueue.main.async {
            self.suggestionWindow?.hide()
        }
    }
    
    private func applySuggestion(_ text: String) {
        logDebug("Applying suggestion: \(text)")
        
        // 1. Determine if we need to switch layout
        let isRussian = text.contains { "абвгдеёжзийклмнопрстуфхцчшщъыьэюя".contains(String($0).lowercased()) }
        
        // Check current layout
        if let currentID = getCurrentInputSourceId() {
             let isCurrentRussian = currentID.contains("Russian")
             if isRussian && !isCurrentRussian {
                 _ = switchToInputSourceContaining("Russian")
             } else if !isRussian && isCurrentRussian {
                 _ = switchToInputSourceContaining("English")
             }
        }
        
        // 2. Delete typed characters
        let deleteCount = keyBuffer.count
        logDebug("Deleting \(deleteCount) chars for suggestion...")
        for _ in 0..<deleteCount {
            sendKey(51) // Backspace
            usleep(500)
        }
        
        // 3. Paste new text
        pasteString(text)
        
        // Clear buffer
        keyBuffer.removeAll()
        clearSuggestion()
    }
    
    private func pasteString(_ str: String) {
        let pasteboard = NSPasteboard.general
        let old = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(str, forType: .string)
        
        // Command+V
        // 'v' is 9
        sendKey(9, flags: .maskCommand)
        
        // Restore clipboard after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let old = old {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
    }

    private func processBuffer(proxy: CGEventTapProxy, triggerKeyCode: Int? = nil) -> Bool {
        if switchingDisabled {
            logDebug("processBuffer: skipped (switchingDisabled=true)")
            return false
        }
        if !autoSwitchEnabled {
            logDebug("processBuffer: skipped (autoSwitchEnabled=false)")
            return false
        }
        // Allow short words (1 char) for RU singles like "я", "э"
        if isProcessing {
            logDebug("processBuffer: skipped (isProcessing=true)")
            return false
        }


        let snapshot = keyBuffer
        // Filter for detection (only letters)
        let filteredCodes = snapshot.compactMap { info -> Int? in
            guard let chars = KeyMapper.shared.getChars(for: info.code) else {
                logDebug("Skipping key code \(info.code) - no mapping found")
                return nil
            }
            if isLetter(chars.en) || isLetter(chars.ru) {
                return info.code
            }
            logDebug("Skipping key code \(info.code) (\(chars.en)/\(chars.ru)) - not a letter")
            return nil
        }
        
        logDebug("Buffer count: \(snapshot.count), Filtered count: \(filteredCodes.count)")
        
        guard !filteredCodes.isEmpty else {
            logDebug("Not enough filtered characters for detection (0)")
            return false
        }
        
        if let detectedLang = LanguageManager.shared.detectLanguage(for: filteredCodes) {
            logDebug("Language detected: \(detectedLang) for buffer count: \(snapshot.count)")
            let spLog = OSLog(subsystem: "com.babylonfish.app", category: "autoswitch")
            os_signpost(.event, log: spLog, name: "detectLanguage", "detected=%{public}@ len=%d", String(describing: detectedLang), filteredCodes.count)
            
            // Check current input source
            guard let currentID = getCurrentInputSourceId() else {
                logDebug("Could not get current input source ID.")
                return false
            }
            
            let isCurrentRussian = currentID.contains("Russian")
            let isCurrentEnglish = currentID.contains("US") || currentID.contains("English") || currentID.contains("ABC")
            
            if detectedLang == .russian && isCurrentRussian {
                logDebug("Detected Russian, but already on Russian layout. Ignoring.")
                return false
            }
            if detectedLang == .english && isCurrentEnglish {
                logDebug("Detected English, but already on English layout. Ignoring.")
                return false
            }
            
            logDebug("Switching layout to \(detectedLang)...")
            switchAndReplace(targetLang: detectedLang, buffer: snapshot, triggerKeyCode: triggerKeyCode)
            return true
        }
        return false
    }
    
    private func switchAndReplace(targetLang: Language, buffer: [KeyInfo], triggerKeyCode: Int?) {
        // Prevent infinite loops
        isProcessing = true
        defer { isProcessing = false }
        
        // Build strings for learning
        var enWord = ""
        var ruWord = ""
        for info in buffer {
            if let chars = KeyMapper.shared.getChars(for: info.code) {
                enWord += chars.en
                ruWord += chars.ru
            }
        }
        LanguageManager.shared.learnDecision(target: targetLang, enWord: enWord, ruWord: ruWord)
        
        // Record switch for undo
        // Length includes the word + potentially the trigger key (Space/Enter) which is restored later
        // If triggerKeyCode is present, it means user typed Word + Space/Enter.
        // To undo, they must backspace the Space/Enter (1) + Word (buffer.count).
        // However, usually they delete the Space, then the Word.
        let undoLength = buffer.count + (triggerKeyCode != nil ? 1 : 0)
        
        lastSwitch = LastSwitchInfo(
            timestamp: Date().timeIntervalSince1970,
            targetLang: targetLang,
            enWord: enWord,
            ruWord: ruWord,
            length: undoLength
        )
        consecutiveBackspaceCount = 0
        
        logDebug("Executing switchAndReplace -> \(targetLang)")
        let spLog = OSLog(subsystem: "com.babylonfish.app", category: "autoswitch")
        let spID = OSSignpostID(log: spLog)
        os_signpost(.begin, log: spLog, name: "switchAndReplace", signpostID: spID, "lang=%{public}@ count=%d", String(describing: targetLang), buffer.count)

        // Clear internal buffer immediately to avoid double processing
        keyBuffer.removeAll()

        // Switch Layout
        let targetIDPart = (targetLang == .russian) ? "Russian" : "English"
        logDebug("Attempting to switch input source to one containing: \(targetIDPart)")
        
        if switchToInputSourceContaining(targetIDPart) {
             logDebug("Input source switch command sent.")
             os_signpost(.event, log: spLog, name: "selectInputSource", "ok target=%{public}@", targetIDPart)
        } else {
             logDebug("FAILED to find/switch input source.")
             os_signpost(.event, log: spLog, name: "selectInputSource", "fail target=%{public}@", targetIDPart)
        }

        // Delete characters
        // We need to delete buffer.count characters.
        // Since we swallowed the trigger key (Space/Enter) in handleKeyDown if it existed,
        // it hasn't been typed yet. So we ONLY delete the buffer content.
        let deleteCount = buffer.count
        
        logDebug("Deleting \(deleteCount) characters...")
        for _ in 0..<deleteCount {
            sendKey(51) // Backspace
            usleep(500) // 0.5ms delay to ensure system processes events
        }
        
        logDebug("Re-typing \(buffer.count) keys...")
        for info in buffer {
            sendKey(info.code, flags: info.flags)
            usleep(500)
        }
        
        // Restore trigger key if it existed
        if let trigger = triggerKeyCode {
            logDebug("Restoring trigger key: \(trigger)")
            sendKey(trigger)
        }
        
        os_signpost(.end, log: spLog, name: "switchAndReplace", signpostID: spID)
    }
    
    private func checkUndoLearning() {
        guard let ls = lastSwitch else { return }
        
        // Timeout (e.g. 15 seconds)
        if Date().timeIntervalSince1970 - ls.timestamp > 15 {
            lastSwitch = nil
            return
        }
        
        if consecutiveBackspaceCount >= ls.length {
            logDebug("Undo Learning Triggered! Unlearning \(ls.enWord)/\(ls.ruWord)")
            LanguageManager.shared.unlearnDecision(target: ls.targetLang, enWord: ls.enWord, ruWord: ls.ruWord)
            
            // Clear lastSwitch so we don't trigger again for the same word
            lastSwitch = nil
        }
    }
    
    private func sendKey(_ keyCode: Int, flags: CGEventFlags = []) {
        // Create key down and up
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
    
    private func switchToInputSourceContaining(_ partialID: String) -> Bool {
        let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        
        // First try to find exact match preference?
        // Prioritize: "Russian" vs "Russian - PC" etc.
        
        for source in sources {
            // Check if it's a keyboard layout
            let category = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory)
            if let catPtr = category {
                let catStr = Unmanaged<CFString>.fromOpaque(catPtr).takeUnretainedValue() as String
                if catStr == "TISCategoryKeyboardInputSource" {
                    
                    if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                        let sourceID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
                        
                        // Check if enabled (selected)
                        // Actually TISCreateInputSourceList(nil, false) returns only enabled/capable ones usually?
                        // "false" param means "includeAllInstalled". false = only enabled? No.
                        // "false" -> includeAllInstalled = false. So returns only selected/enabled.
                        
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

    private func isLetter(_ s: String) -> Bool {
        guard let scalar = s.unicodeScalars.first else { return false }
        return CharacterSet.letters.contains(scalar)
    }
    
    private func isSecureField() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result == .success, let element = focusedElement {
            let axElement = element as! AXUIElement
            var subrole: AnyObject?
            AXUIElementCopyAttributeValue(axElement, kAXSubroleAttribute as CFString, &subrole)
            
            if let subroleStr = subrole as? String {
                if subroleStr == "AXSecureTextField" {
                    return true
                }
            }
        }
        return false
    }
    
    private func handleDoubleShift() {
        // 1. Get Selected Text
        var selectedText = getSelectedText()
        
        if selectedText == nil {
            selectedText = getSelectedTextViaClipboard()
        }
        
        guard let text = selectedText, !text.isEmpty else { return }
        
        // 2. Convert Text (Simple char mapping inversion)
        let convertedText = convertTextLayout(text)
        
        // 3. Replace Text
        replaceSelectedText(with: convertedText)
        
        // 4. Switch Layout globally too? Yes.
        // For double shift, we just toggle to the other one.
        if let current = getCurrentInputSourceId() {
            if current.contains("Russian") {
                _ = switchToInputSourceContaining("English") // or US
            } else {
                _ = switchToInputSourceContaining("Russian")
            }
        }
    }
    
    private func getSelectedTextViaClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        _ = pasteboard.changeCount
        
        // Simulate Cmd+C
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true) // C
        cDown?.flags = .maskCommand
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        cUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false)
        
        let loc = CGEventTapLocation.cghidEventTap
        cmdDown?.post(tap: loc)
        cDown?.post(tap: loc)
        cUp?.post(tap: loc)
        cmdUp?.post(tap: loc)
        
        // Wait briefly? This is blocking in the event tap, which is bad.
        // But since this is triggered by Double Shift, we are not in the critical typing path usually.
        // However, blocking the tap blocks all input.
        // We can't really wait here safely without freezing the system.
        // We'll return nil and hope the user tries again, or use a short spin lock (dangerous).
        // A better way is to schedule a check on the runloop.
        
        // For this demo, we'll try to read immediately (might fail if app is slow)
        // or assumes the user selected text.
        
        // Actually, if we just posted the event, the clipboard won't update instantly.
        // So this fallback is flaky without async handling.
        // Let's rely on AX first.
        return nil 
    }
    
    private func getSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard let element = focusedElement else { return nil }
        let axElement = element as! AXUIElement
        
        var selectedTextValue: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        
        return selectedTextValue as? String
    }
    
    private func replaceSelectedText(with newText: String) {
        // Attempt to set kAXSelectedTextAttribute
        // This only works for editable fields that support it
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        var success = false
        if let element = focusedElement {
            let axElement = element as! AXUIElement
            // Try setting value
            let error = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, newText as CFTypeRef)
            if error == .success {
                success = true
            }
        }
        
        if !success {
            // Fallback: Clipboard Method
            replaceViaClipboard(newText: newText)
        }
    }
    
    private func replaceViaClipboard(newText: String) {
        let pasteboard = NSPasteboard.general
        _ = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(newText, forType: .string)
        
        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true) // Cmd
        cmdDown?.flags = .maskCommand
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // V
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        vUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false)
        
        let loc = CGEventTapLocation.cghidEventTap
        cmdDown?.post(tap: loc)
        vDown?.post(tap: loc)
        vUp?.post(tap: loc)
        cmdUp?.post(tap: loc)
        
        // Restore clipboard after a small delay? 
        // Realistically, users might want the converted text in clipboard.
        // If we want to be nice, we restore old, but that's complex with async paste.
        // Let's leave it in clipboard.
    }
    
    private func convertTextLayout(_ text: String) -> String {
        var result = ""
        // This is reverse mapping. We have chars, we need to find the keycode, then map to other lang.
        // This is O(N*M) unless we build a reverse map.
        // For demo, we iterate.
        
        for char in text {
            let s = String(char).lowercased()
            var found = false
            for (_, (en, ru)) in KeyMapper.shared.map {
                if en == s {
                    result += ru
                    found = true
                    break
                } else if ru == s {
                    result += en
                    found = true
                    break
                }
            }
            if !found { result += String(char) }
        }
        return result
    }
}
