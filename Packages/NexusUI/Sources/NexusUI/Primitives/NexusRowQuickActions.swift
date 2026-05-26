import SwiftUI

/// One quick action in a row's hover affordance cluster (LabKit
/// `LabRowAction`). Unlike the visual-only lab original, production carries a
/// real handler.
public struct NexusRowQuickAction: Identifiable {
    public let id = UUID()
    public let icon: String
    /// VoiceOver label for the icon-only button. When `nil`, VoiceOver falls
    /// back to announcing the raw SF Symbol name (`icon`) — pass a real label.
    /// Codebase `.accessibilityLabel` convention is English (see RULING-T).
    public let accessibilityLabel: String?
    public let action: () -> Void

    public init(
        icon: String,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }
}

/// Compact quick-action cluster revealed on row hover (LabKit `LabRowAction`
/// row). Surfaces own when it is shown (e.g. on `.onHover`); this primitive is
/// just the cluster + its press affordance.
public struct NexusRowQuickActions: View {
    public let actions: [NexusRowQuickAction]

    public init(actions: [NexusRowQuickAction]) {
        self.actions = actions
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(actions) { quickAction in
                Button(action: quickAction.action) {
                    Image(systemName: quickAction.icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NexusColor.Text.tertiary)
                        .frame(width: 22, height: 22)
                        .background(
                            Color.white.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(NexusPressableButtonStyle())
                .accessibilityLabel(quickAction.accessibilityLabel ?? quickAction.icon)
            }
        }
    }
}

#Preview {
    NexusRowQuickActions(actions: [
        .init(icon: "checkmark") {},
        .init(icon: "clock") {},
    ])
    .padding(40)
    .background(NexusColor.Background.base)
}
