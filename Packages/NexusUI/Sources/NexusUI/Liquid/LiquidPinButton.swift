import SwiftUI

/// A star toggle button used to pin / unpin an item to the Today view.
/// Appears accent-filled when pinned; muted when unpinned. macOS callers
/// typically reveal it on row hover; iOS callers always show it.
public struct LiquidPinButton: View {
    let isPinned: Bool
    let toggle: () -> Void

    public init(isPinned: Bool, toggle: @escaping () -> Void) {
        self.isPinned = isPinned
        self.toggle = toggle
    }

    public var body: some View {
        Button(action: toggle) {
            Image(systemName: isPinned ? "star.fill" : "star")
                .foregroundStyle(isPinned ? DS.ColorToken.accentPrimary : DS.ColorToken.textTertiary)
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Unpin from Today" : "Pin to Today")
        .accessibilityLabel(isPinned ? "Unpin from Today" : "Pin to Today")
    }
}
