import AppKit
import SwiftUI

@MainActor
final class RecordingPanelWindow: NSPanel {
    init(view: RecordingPanelView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isMovableByWindowBackground = true
        title = "Recording"
        contentViewController = NSHostingController(rootView: view)
    }
}
