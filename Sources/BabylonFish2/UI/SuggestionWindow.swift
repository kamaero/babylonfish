import Cocoa
import Carbon

class SuggestionWindow: NSWindow {
    private let suggestionLabel: NSTextField
    private let actionLabel: NSTextField
    private var currentSuggestion: String = ""
    private var currentAction: String = ""
    private var windowVisible: Bool = false
    private var hideTimer: Timer?
    
    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 300, height: 80)
        
        suggestionLabel = NSTextField(labelWithString: "")
        suggestionLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        suggestionLabel.textColor = .textColor
        suggestionLabel.alignment = .center
        suggestionLabel.frame = NSRect(x: 20, y: 40, width: 260, height: 24)
        
        actionLabel = NSTextField(labelWithString: "")
        actionLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        actionLabel.textColor = .secondaryLabelColor
        actionLabel.alignment = .center
        actionLabel.frame = NSRect(x: 20, y: 15, width: 260, height: 20)
        
        let contentView = NSView(frame: contentRect)
        contentView.addSubview(suggestionLabel)
        contentView.addSubview(actionLabel)
        
        super.init(contentRect: contentRect,
                  styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered,
                  defer: false)
        
        self.level = .floating
        self.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        self.hasShadow = true
        self.isOpaque = false
        self.contentView = contentView
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.isMovableByWindowBackground = false
        self.ignoresMouseEvents = true
        
        updateAppearance()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showSuggestion(_ suggestion: String, action: String, at point: NSPoint) {
        currentSuggestion = suggestion
        currentAction = action
        
        suggestionLabel.stringValue = suggestion
        actionLabel.stringValue = action
        
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowWidth: CGFloat = 300
        let windowHeight: CGFloat = 80
        
        var windowOrigin = point
        windowOrigin.x -= windowWidth / 2
        windowOrigin.y += 20
        
        if windowOrigin.x < screenFrame.minX {
            windowOrigin.x = screenFrame.minX
        }
        if windowOrigin.x + windowWidth > screenFrame.maxX {
            windowOrigin.x = screenFrame.maxX - windowWidth
        }
        if windowOrigin.y + windowHeight > screenFrame.maxY {
            windowOrigin.y = screenFrame.maxY - windowHeight
        }
        
        self.setFrameOrigin(windowOrigin)
        
        if !windowVisible {
            self.alphaValue = 0
            self.orderFront(nil)
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                self.animator().alphaValue = 1.0
            }
            
            windowVisible = true
        }
        
        scheduleHide()
    }
    
    func hideSuggestion() {
        guard windowVisible else { return }
        
        hideTimer?.invalidate()
        hideTimer = nil
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 0
        } completionHandler: {
            self.orderOut(nil)
            self.windowVisible = false
        }
    }
    
    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.hideSuggestion()
        }
    }
    
    private func updateAppearance() {
        if #available(macOS 10.14, *) {
            let isDarkMode = NSApp.effectiveAppearance.name == .darkAqua
            self.backgroundColor = isDarkMode ? 
                NSColor.windowBackgroundColor.withAlphaComponent(0.95) :
                NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        }
    }
    
    func updatePosition(for cursorPosition: NSPoint) {
        guard windowVisible else { return }
        
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowWidth: CGFloat = 300
        let windowHeight: CGFloat = 80
        
        var windowOrigin = cursorPosition
        windowOrigin.x -= windowWidth / 2
        windowOrigin.y += 20
        
        if windowOrigin.x < screenFrame.minX {
            windowOrigin.x = screenFrame.minX
        }
        if windowOrigin.x + windowWidth > screenFrame.maxX {
            windowOrigin.x = screenFrame.maxX - windowWidth
        }
        if windowOrigin.y + windowHeight > screenFrame.maxY {
            windowOrigin.y = screenFrame.maxY - windowHeight
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            self.animator().setFrameOrigin(windowOrigin)
        }
    }
    
    func showCorrection(_ original: String, corrected: String, at point: NSPoint) {
        showSuggestion(corrected, action: "Press Tab to accept correction", at: point)
    }
    
    func showCompletion(_ completion: String, at point: NSPoint) {
        showSuggestion(completion, action: "Press Tab to complete", at: point)
    }
    
    func showLanguageSwitch(_ language: String, at point: NSPoint) {
        showSuggestion("Switched to \(language)", action: "Layout changed automatically", at: point)
    }
}