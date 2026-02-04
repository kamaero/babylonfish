import Cocoa
import ApplicationServices

class OverlayWindow: NSWindow {
    static let shared = OverlayWindow()
    
    private var borderView: NSBox!
    private var fadeTimer: Timer?
    private var isFading = false
    
    init() {
        // Create a borderless, transparent window
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating // Above normal windows
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        
        // Setup Border View
        let view = NSBox(frame: .zero)
        view.boxType = .custom
        // view.borderType = .lineBorder // Deprecated
        view.borderWidth = 4
        view.cornerRadius = 10
        view.fillColor = .clear
        view.contentViewMargins = .zero
        self.contentView = view
        self.borderView = view
    }
    
    func flash(color: NSColor) {
        DispatchQueue.main.async {
            self.stopFade()
            
            var targetFrame: NSRect?
            
            if let frame = self.getActiveWindowFrame() {
                // Add some padding
                targetFrame = frame.insetBy(dx: -6, dy: -6)
            } else {
                // Fallback to screen bounds if no window found (e.g. Accessibility permission missing)
                if let screen = NSScreen.main {
                     // Show a visible border around the screen
                     targetFrame = screen.visibleFrame.insetBy(dx: 10, dy: 10)
                }
            }
            
            guard let finalFrame = targetFrame else { return }
            
            self.setFrame(finalFrame, display: true)
            self.borderView.borderColor = color
            self.alphaValue = 1.0
            self.orderFront(nil)
        }
    }
    
    func notifyTyping() {
        DispatchQueue.main.async {
            guard self.isVisible, self.alphaValue > 0, !self.isFading else { return }
            self.startFadeOut()
        }
    }
    
    private func startFadeOut() {
        isFading = true
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            self.alphaValue -= 0.1
            if self.alphaValue <= 0 {
                self.orderOut(nil)
                self.stopFade()
            }
        }
    }
    
    private func stopFade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        isFading = false
    }
    
    private func getActiveWindowFrame() -> NSRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result == .success, let element = focusedElement {
            let axElement = element as! AXUIElement
            
            // Get the Window of the focused element
            var window: AnyObject?
            AXUIElementCopyAttributeValue(axElement, kAXWindowAttribute as CFString, &window)
            
            if let windowElement = window as! AXUIElement? {
                var position: AnyObject?
                var size: AnyObject?
                
                AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &position)
                AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &size)
                
                if let posValue = position, let sizeValue = size {
                    var point = CGPoint.zero
                    var size = CGSize.zero
                    AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
                    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                    
                    // Cocoa coordinates are inverted vertically
                    // But wait, setFrame uses screen coordinates where (0,0) is bottom-left?
                    // AX uses top-left.
                    // We need to convert.
                    
                    if let screen = NSScreen.main {
                        let newY = screen.frame.height - point.y - size.height
                        return NSRect(x: point.x, y: newY, width: size.width, height: size.height)
                    }
                }
            }
        }
        return nil
    }
}
