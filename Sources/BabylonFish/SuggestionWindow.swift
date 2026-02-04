import Cocoa
import SwiftUI

class SuggestionWindow: NSPanel {
    private var hostingView: NSHostingView<SuggestionView>?
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.nonactivatingPanel, .hudWindow, .utilityWindow, .borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
    }
    
    func showSuggestion(_ text: String, at point: CGPoint) {
        let view = SuggestionView(text: text)
        if hostingView == nil {
            hostingView = NSHostingView(rootView: view)
            self.contentView = hostingView
        } else {
            hostingView?.rootView = view
        }
        
        self.setFrameOrigin(point)
        self.orderFront(nil)
    }
    
    func hide() {
        self.orderOut(nil)
    }
}

struct SuggestionView: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.uturn.backward")
                .foregroundColor(.white)
                .font(.system(size: 12, weight: .bold))
            
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
            
            Text("⏎")
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .padding(2)
                .background(Color.white.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.8))
        )
        .frame(height: 40)
    }
}
