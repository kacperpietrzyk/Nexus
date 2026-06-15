import SwiftUI

extension View {
    /// translateY(-2pt) + brightness(1.04) on hover.
    /// Canvas reference: screen-amb.jsx:376-390.
    public func nexusHoverLift() -> some View {
        modifier(HoverLiftModifier())
    }
}

private struct HoverLiftModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func body(content: Content) -> some View {
        // Reduce Motion suppresses the positional lift; brightness (a
        // non-positional cue) is retained so hover still reads.
        let base =
            content
            .offset(y: hovering && !reduceMotion ? -2 : 0)
            .brightness(hovering ? 0.04 : 0)
            .animation(.timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.25), value: hovering)
        #if os(watchOS)
        return base
        #else
        return base.onHover { hovering = $0 }
        #endif
    }
}
