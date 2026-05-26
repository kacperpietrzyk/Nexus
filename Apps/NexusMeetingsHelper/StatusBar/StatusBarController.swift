import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    enum State: Equatable {
        case idle
        case detection
        case recording(elapsedSec: Int)
        case processing
    }

    private let item: NSStatusItem
    private var popover: NSPopover?
    private var state: State = .idle

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        applyIcon()
    }

    func update(state: State) {
        self.state = state
        applyIcon()
    }

    private func applyIcon() {
        guard let button = item.button else { return }
        button.contentTintColor = nil

        switch state {
        case .idle:
            button.image = NSImage(
                systemSymbolName: "record.circle",
                accessibilityDescription: "Nexus Meetings idle"
            )
            button.title = ""
        case .detection:
            button.image = NSImage(
                systemSymbolName: "record.circle",
                accessibilityDescription: "Meeting detected"
            )
            button.contentTintColor = .systemYellow
            button.title = ""
        case .recording(let elapsedSec):
            button.image = NSImage(
                systemSymbolName: "record.circle.fill",
                accessibilityDescription: "Recording meeting"
            )
            button.contentTintColor = .systemRed
            button.title = "  \(Self.formatElapsed(elapsedSec))"
        case .processing:
            button.image = NSImage(
                systemSymbolName: "gearshape.fill",
                accessibilityDescription: "Processing meeting"
            )
            button.contentTintColor = .systemYellow
            button.title = ""
        }
    }

    @objc private func togglePopover() {
        let popover = popover ?? makePopover()
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = item.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 220)
        popover.contentViewController = NSHostingController(rootView: StatusBarMenuBuilder.makeRoot())
        self.popover = popover
        return popover
    }

    private static func formatElapsed(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        let seconds = clamped % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
