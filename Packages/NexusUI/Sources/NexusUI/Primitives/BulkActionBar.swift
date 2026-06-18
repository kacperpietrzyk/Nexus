import SwiftUI

/// One bulk action surfaced in the `BulkActionBar` — a label, an SF Symbol, an
/// optional destructive role, and the work to run against the current
/// selection. The surface owns reading `model.selectedIDs` inside `action`.
public struct BulkAction: Identifiable {
    public let id = UUID()
    public let label: String
    public let systemImage: String
    public let role: ButtonRole?
    public let action: () -> Void

    public init(
        label: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }
}

/// Liquid-glass action bar pinned to the bottom of a multi-select surface.
///
/// Shows only while `model.hasSelection` (selecting + non-empty). Displays the
/// count, a Select-All / Deselect-All toggle, a Cancel control, and the
/// injected bulk actions. Present it yourself in a bottom `safeAreaInset` /
/// `overlay(alignment: .bottom)`; the bar handles its own enter/exit.
public struct BulkActionBar<ID: Hashable>: View {
    @Bindable var model: SelectionModel<ID>
    let allIDs: [ID]
    let actions: [BulkAction]

    /// - Parameters:
    ///   - model: the surface's selection model.
    ///   - allIDs: every selectable id on the surface — backs Select-All and the
    ///     "all selected" check that flips the toggle to Deselect-All.
    ///   - actions: the bulk actions (run against `model.selectedIDs`).
    public init(
        model: SelectionModel<ID>,
        allIDs: [ID],
        actions: [BulkAction]
    ) {
        self._model = Bindable(model)
        self.allIDs = allIDs
        self.actions = actions
    }

    private var allSelected: Bool {
        !allIDs.isEmpty && model.selectedIDs.count >= allIDs.count
    }

    public var body: some View {
        Group {
            if model.hasSelection {
                bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DS.Motion.panelReveal, value: model.hasSelection)
    }

    private var bar: some View {
        HStack(spacing: DS.Space.m) {
            Text("\(model.count) selected")
                .font(DS.FontToken.bodyStrong)
                .foregroundStyle(DS.ColorToken.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(1)

            Button(allSelected ? "Deselect All" : "Select All") {
                withAnimation(DS.Motion.selection) {
                    if allSelected { model.clear() } else { model.selectAll(allIDs) }
                }
            }
            .buttonStyle(BulkBarTextButtonStyle())
            .lineLimit(1)

            Spacer(minLength: DS.Space.s)

            // Action labels collapse to icon-only when the surface is too narrow
            // (e.g. the ~280pt Meetings sidebar) so the bar stays a single-line
            // capsule that fits the pane instead of wrapping or overflowing.
            ForEach(actions) { action in
                Button(role: action.role) {
                    action.action()
                } label: {
                    ViewThatFits(in: .horizontal) {
                        Label(action.label, systemImage: action.systemImage)
                            .font(DS.FontToken.button)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                        Label(action.label, systemImage: action.systemImage)
                            .font(DS.FontToken.button)
                            .labelStyle(.iconOnly)
                    }
                }
                .buttonStyle(BulkBarActionButtonStyle(isDestructive: action.role == .destructive))
            }

            Button {
                withAnimation(DS.Motion.panelReveal) { model.exitSelection() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(LiquidPressButtonStyle())
            .accessibilityLabel("Cancel selection")
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.s)
        .liquidGlass(.strong, radius: DS.Radius.pill)
        .padding(.horizontal, DS.Space.l)
        .padding(.bottom, DS.Space.m)
    }
}

/// Neutral text control (Select-All / Deselect-All).
private struct BulkBarTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.FontToken.button)
            .foregroundStyle(DS.ColorToken.textSecondary)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// A bulk action pill — neutral glass, or danger-tinted when destructive.
private struct BulkBarActionButtonStyle: ButtonStyle {
    let isDestructive: Bool

    private var ink: Color {
        isDestructive ? DS.ColorToken.statusDanger : DS.ColorToken.textPrimary
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ink)
            .padding(.horizontal, DS.Space.m)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(isDestructive ? DS.ColorToken.statusDanger.opacity(0.14) : DS.ColorToken.glassSelected)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .stroke(
                        isDestructive ? DS.ColorToken.statusDanger.opacity(0.40) : DS.ColorToken.strokeHairline,
                        lineWidth: 1
                    )
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}
