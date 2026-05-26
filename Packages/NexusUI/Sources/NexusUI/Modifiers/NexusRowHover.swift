import SwiftUI

extension View {
    /// Azure accent tint (4% alpha) on row hover — v4 cool palette.
    /// Canvas reference: screen-amb.jsx:392-409.
    public func nexusRowHover() -> some View {
        modifier(RowHoverModifier())
    }
}

private struct RowHoverModifier: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        let base =
            content
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? NexusColor.Text.primary.opacity(0.04) : .clear)
            )
            .animation(.easeOut(duration: 0.15), value: hovering)
        #if os(watchOS)
        return base
        #else
        return base.onHover { hovering = $0 }
        #endif
    }
}
