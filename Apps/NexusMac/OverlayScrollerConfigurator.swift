#if os(macOS)
import AppKit
import SwiftUI

/// Forces every `NSScrollView` in the hosting window to the modern **overlay**
/// scroller style — a thin, auto-hiding knob with no track — regardless of the
/// user's system "Show scroll bars" preference (which otherwise renders the
/// prominent legacy tracked scroller). One subtle, unified scrollbar across the
/// whole app. Attach once at the window root via
/// `.background(OverlayScrollerConfigurator())`.
///
/// `scrollerStyle` is a per-instance override, so this wins over the system
/// `.legacy`/"Always" setting. SwiftUI builds `List`'s scroll view lazily and
/// can rebuild it on navigation, so the style is re-applied on every SwiftUI
/// update and a few deferred passes after first layout.
struct OverlayScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleApply(from: view, delays: [0.0, 0.2, 0.6])
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleApply(from: nsView, delays: [0.0])
    }

    private func scheduleApply(from view: NSView, delays: [TimeInterval]) {
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view] in
                guard let window = view?.window else { return }
                Self.applyOverlayStyle(to: window.contentView)
            }
        }
    }

    private static func applyOverlayStyle(to view: NSView?) {
        guard let view else { return }
        if let scrollView = view as? NSScrollView, scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
        for subview in view.subviews {
            applyOverlayStyle(to: subview)
        }
    }
}
#endif
