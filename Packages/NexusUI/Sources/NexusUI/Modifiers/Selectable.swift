import SwiftUI

/// Reveals a leading multi-select checkmark on a custom row without relying on
/// `List(selection:)`.
///
/// This modifier is **presentation only** — it does NOT capture taps. Inside a
/// `List`, an overlay/`allowsHitTesting` tap layer is swallowed by the list's
/// own row hit-testing, so the row never toggles. The reliable pattern is for
/// the call site to route its existing tap by selection mode:
///
///     .onTapGesture { selection.isSelecting ? selection.toggle(id: id) : open() }
///
/// The view-tree SHAPE stays constant across the `isSelecting` flip (the
/// checkmark is always present, collapsed to zero width when idle): a `List`
/// re-diffs every row when selection mode toggles, and inserting/removing a
/// subview mid-diff crashes SwiftUI's row-trait machinery (EXC_BAD_ACCESS in
/// the selection update guard).
public struct SelectableModifier: ViewModifier {
    let isSelecting: Bool
    let isSelected: Bool
    let onToggle: (() -> Void)?

    public init(isSelecting: Bool, isSelected: Bool, onToggle: (() -> Void)? = nil) {
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        self.onToggle = onToggle
    }

    public func body(content: Content) -> some View {
        // NO `.animation(_:value:)` here: an implicit animation on the row
        // subtree collides with `NexusAppear`'s in-flight stagger `withAnimation`
        // when the windowed List tears a row down mid-flight, dealloc-crashing
        // the AttributeGraph (`destroy for NexusAppear`, EXC_BAD_ACCESS).
        HStack(spacing: 0) {
            // The checkmark is the obvious tap target in select mode, so it must
            // toggle on tap: it is prepended OUTSIDE the row's own tap area, so
            // without this `onTapGesture` tapping the circle did nothing.
            SelectionCheckmark(isSelected: isSelected)
                .frame(width: isSelecting ? 24 : 0)
                .padding(.trailing, isSelecting ? DS.Space.s : 0)
                .opacity(isSelecting ? 1 : 0)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { if isSelecting { onToggle?() } }
                .accessibilityHidden(true)
            content
        }
    }
}

/// The leading selection indicator: a filled lime check when selected, a hollow
/// ring when not. Sized to sit comfortably beside a row's leading glyph.
public struct SelectionCheckmark: View {
    public let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? NexusColor.Accent.lime : NexusColor.Line.strong,
                    lineWidth: 1.5
                )
                .frame(width: 20, height: 20)
            if isSelected {
                Circle()
                    .fill(NexusColor.Accent.lime)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NexusColor.Accent.limeInk)
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Reveals a leading multi-select checkmark. Transparent passthrough until
    /// `isSelecting`.
    ///
    /// Pass EXPLICIT values read from the surface's `SelectionModel` at the call
    /// site (e.g. inside the `ForEach`), NOT via the model inside the modifier:
    /// reading `selection.isSelected(id:)` in the parent body is what makes the
    /// parent observe the selection set and re-render the row when it toggles.
    /// A `@Bindable` read inside the modifier does not reliably re-invalidate.
    ///
    /// - Parameters:
    ///   - isSelecting: whether the surface is in multi-select mode.
    ///   - isSelected: whether THIS row is currently selected.
    ///   - onToggle: toggles THIS row; invoked when the checkmark is tapped.
    public func selectable(
        isSelecting: Bool,
        isSelected: Bool,
        onToggle: (() -> Void)? = nil
    ) -> some View {
        modifier(SelectableModifier(isSelecting: isSelecting, isSelected: isSelected, onToggle: onToggle))
    }
}
