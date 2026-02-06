import Foundation
import Cocoa

/// Анализирует контекст ввода для принятия решений об игнорировании
class ContextAnalyzer {
    private var contextRules: [ContextRule] = []
    private var appExceptions: [AppException] = []
    
    /// Проверяет, является ли поле ввода защищенным (пароль)
    func isSecureField() -> Bool {
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
    
    /// Проверяет, является ли текущее приложение терминалом
    func isTerminalApp() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        
        let terminalNames = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "io.alacritty",
            "net.kovidgoyal.kitty",
            "org.gnu.Emacs",
            "org.vim.MacVim",
            "com.microsoft.VSCode", // Хотя VS Code это IDE, но часто используется как терминал
        ]
        
        if let bundleId = app.bundleIdentifier {
            return terminalNames.contains(bundleId)
        }
        
        // Проверяем по имени процесса
        let processName = app.localizedName?.lowercased() ?? ""
        let terminalProcessNames = ["terminal", "iterm", "iterm2", "alacritty", "kitty", "vim", "nvim", "emacs"]
        return terminalProcessNames.contains { processName.contains($0) }
    }
    
    /// Проверяет, является ли текущее приложение IDE
    func isIDE() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        
        let ideBundleIds = [
            "com.jetbrains.intellij",
            "com.jetbrains.AppCode",
            "com.jetbrains.CLion",
            "com.jetbrains.datagrip",
            "com.jetbrains.goland",
            "com.jetbrains.PhpStorm",
            "com.jetbrains.pycharm",
            "com.jetbrains.rider",
            "com.jetbrains.rubymine",
            "com.jetbrains.WebStorm",
            "com.microsoft.VSCode",
            "com.sublimetext.4",
            "com.visualstudio.code.oss",
            "com.apple.dt.Xcode",
            "com.electron.zed",
        ]
        
        if let bundleId = app.bundleIdentifier {
            for ideId in ideBundleIds {
                if bundleId.hasPrefix(ideId) {
                    return true
                }
            }
        }
        
        // Проверяем по имени процесса
        let processName = app.localizedName?.lowercased() ?? ""
        let ideProcessNames = ["xcode", "visual studio", "vscode", "intellij", "pycharm", "clion", "webstorm", "phpstorm", "rider", "rubymine", "appcode", "datagrip", "goland", "sublime", "zed"]
        return ideProcessNames.contains { processName.contains($0) }
    }
    
    /// Проверяет, является ли текущее приложение игрой
    func isGame() -> Bool {
        // Игры часто работают в полноэкранном режиме и имеют определенные window titles
        // Упрощенная проверка: полноэкранный режим или отсутствие меню
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        
        // Проверяем bundle ID игр (Steam, Epic, etc.)
        if let bundleId = app.bundleIdentifier {
            let gameIndicators = ["com.valvesoftware.steam", "com.epicgames", "unity.", "unrealengine", "com.blizzard", "com.ea."]
            for indicator in gameIndicators {
                if bundleId.contains(indicator) {
                    return true
                }
            }
        }
        
        // Проверяем по window title (если есть)
        if let windowTitle = getActiveWindowTitle()?.lowercased() {
            let gameKeywords = ["steam", "epic games", "battle.net", "origin", "ubisoft", "playstation", "xbox"]
            for keyword in gameKeywords {
                if windowTitle.contains(keyword) {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Определяет, следует ли отключить переключение в текущем контексте
    func shouldDisableSwitching() -> Bool {
        // 1. Проверяем secure field (всегда отключаем)
        if isSecureField() {
            logDebug("ContextAnalyzer: secure field detected, disabling switching")
            return true
        }
        
        // 2. Проверяем правила контекста из конфигурации
        if let action = evaluateContextRules() {
            logDebug("ContextAnalyzer: context rule matched, action: \(action)")
            return action == .disableSwitching
        }
        
        // 3. Проверяем исключения для приложений
        if let action = evaluateAppExceptions() {
            logDebug("ContextAnalyzer: app exception matched, action: \(action)")
            return action == .disableSwitching
        }
        
        // 4. Запасная эвристика для обратной совместимости
        let isTerminal = isTerminalApp()
        let isGameApp = isGame()
        if isTerminal || isGameApp {
            logDebug("ContextAnalyzer: fallback heuristic - terminal: \(isTerminal), game: \(isGameApp)")
            return true
        }
        
        logDebug("ContextAnalyzer: switching enabled for current context")
        return false
    }
    
    /// Оценивает правила контекста
    private func evaluateContextRules() -> ContextAction? {
        for rule in contextRules {
            switch rule.type {
            case .terminal:
                if isTerminalApp() { return rule.action }
            case .ide:
                if isIDE() { return rule.action }
            case .game:
                if isGame() { return rule.action }
            case .passwordField:
                if isSecureField() { return rule.action }
            case .custom:
                // Пока не поддерживаем кастомные правила
                break
            }
        }
        return nil
    }
    
    /// Оценивает исключения для приложений
    private func evaluateAppExceptions() -> ContextAction? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        
        for exception in appExceptions {
            var matches = true
            
            // Проверяем bundleId
            if let bundleId = exception.bundleId,
               let appBundleId = app.bundleIdentifier,
               appBundleId != bundleId {
                matches = false
            }
            
            // Проверяем processName
            if let processName = exception.processName,
               let appProcessName = app.localizedName,
               appProcessName != processName {
                matches = false
            }
            
            // Проверяем windowTitle
            if let windowTitle = exception.windowTitle,
               let activeTitle = getActiveWindowTitle(),
               activeTitle != windowTitle {
                matches = false
            }
            
            if matches {
                return exception.action
            }
        }
        
        return nil
    }
    
    /// Получает заголовок активного окна
    private func getActiveWindowTitle() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard let element = focusedElement else { return nil }
        let axElement = element as! AXUIElement
        
        var window: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXWindowAttribute as CFString, &window)
        
        guard let windowElement = window else { return nil }
        let axWindow = windowElement as! AXUIElement
        
        var title: AnyObject?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &title)
        
        return title as? String
    }
    
    /// Устанавливает правила контекста
    func setContextRules(_ rules: [ContextRule]) {
        contextRules = rules
        logDebug("ContextAnalyzer: set \(rules.count) context rules")
    }
    
    /// Устанавливает исключения для приложений
    func setAppExceptions(_ exceptions: [AppException]) {
        appExceptions = exceptions
        logDebug("ContextAnalyzer: set \(exceptions.count) app exceptions")
    }
}