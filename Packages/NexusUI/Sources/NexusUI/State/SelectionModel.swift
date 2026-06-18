import Observation

/// Multi-select state for arbitrary custom rows.
///
/// Nexus rows are mostly custom glass `Button`s rather than SwiftUI `List`
/// rows, so selection cannot ride on `List(selection:)`. This plain
/// `@Observable` carries the selection set and the selection-mode flag; the
/// `.selectable(id:in:)` row modifier intercepts taps against it, and
/// `BulkActionBar` reads it to drive the bottom action bar.
///
/// `@MainActor` for parity with the other UI models (e.g.
/// `ProposalConfirmCardModel`); the test suite already runs `@MainActor`.
@MainActor
@Observable
public final class SelectionModel<ID: Hashable> {
    /// The currently selected row ids.
    public private(set) var selectedIDs: Set<ID> = []
    /// Whether the surface is in multi-select mode. While `false`, rows behave
    /// normally and `.selectable` is a transparent passthrough.
    public private(set) var isSelecting = false

    public init() {}

    /// Number of selected rows. Convenience for the bulk bar's "N selected".
    public var count: Int { selectedIDs.count }

    /// True when selection mode is active and at least one row is selected —
    /// the condition `BulkActionBar` uses to decide whether to show itself.
    public var hasSelection: Bool { isSelecting && !selectedIDs.isEmpty }

    public func isSelected(id: ID) -> Bool { selectedIDs.contains(id) }

    /// Toggles a single row. Entering selection mode implicitly the first time
    /// a row is toggled is left to the surface (call `enterSelection()` first);
    /// toggling on its own only mutates the set.
    public func toggle(id: ID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// Selects every id in `ids` (union). Used by the bar's Select-All control.
    public func selectAll(_ ids: some Sequence<ID>) {
        selectedIDs.formUnion(ids)
    }

    /// Clears the selection set but stays in selection mode.
    public func clear() {
        selectedIDs.removeAll()
    }

    /// Enters multi-select mode (rows start intercepting taps).
    public func enterSelection() {
        isSelecting = true
    }

    /// Exits multi-select mode and clears the set (rows return to normal).
    public func exitSelection() {
        isSelecting = false
        selectedIDs.removeAll()
    }
}
