import AppKit
import SwiftUI

@MainActor
final class DetectionNotificationWindow: NSPanel {
    init(view: DetectionNotificationView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        contentViewController = NSHostingController(rootView: view)
    }

    func present(on screen: NSScreen) {
        let frame = screen.visibleFrame
        let x = frame.maxX - self.frame.width - 24
        let y = frame.maxY - self.frame.height - 24
        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.orderOut(nil)
        }
    }
}
