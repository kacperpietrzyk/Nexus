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
                QuickActionButton(quickAction: quickAction)
            }
        }
    }
}

/// A single hover-reactive quick-action button. Private internal so the public
/// `NexusRowQuickAction`/`NexusRowQuickActions` API stays frozen — this only
/// carries the per-button hover state Linear's neutral→primary ink swap needs.
private struct QuickActionButton: View {
    let quickAction: NexusRowQuickAction

    @State private var isHovered = false

    /// Linear quick-actions are neutral hover chrome: Storm Cloud at rest,
    /// Porcelain on hover. A destructive action (inferred from its icon, since
    /// the model carries no role flag) instead resolves to Warning Red — but
    /// only on hover, never at rest.
    private var iconColor: Color {
        guard isHovered else { return NexusColor.Text.tertiary }
        return isDestructive ? NexusColor.Status.danger : NexusColor.Text.primary
    }

    /// Quick actions never use the lime accent (reserved for primary actions /
    /// selection). The hover fill is a neutral raised surface, transparent at
    /// rest so the cluster reads as ghost chrome.
    private var backgroundColor: Color {
        isHovered ? NexusColor.Background.controlHover : .clear
    }

    /// Heuristic: the model has no destructive role, so we infer it from the
    /// SF Symbol the surface passed. Keeps the public API frozen while still
    /// honoring the destructive-on-hover treatment if a delete action appears.
    private var isDestructive: Bool {
        let destructiveIcons: Set<String> = [
            "trash", "trash.fill", "trash.slash", "xmark.bin", "xmark.bin.fill",
        ]
        return destructiveIcons.contains(quickAction.icon)
    }

    var body: some View {
        Button(action: quickAction.action) {
            Image(systemName: quickAction.icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 22, height: 22)
                .background(
                    backgroundColor,
                    in: RoundedRectangle(cornerRadius: NexusRadius.r1)
                )
        }
        .buttonStyle(NexusPressableButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(quickAction.accessibilityLabel ?? quickAction.icon)
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
