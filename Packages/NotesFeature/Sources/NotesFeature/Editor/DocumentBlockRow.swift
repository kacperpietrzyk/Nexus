#if os(macOS)

import NexusCore
import NexusUI
import SwiftUI

/// One macOS document block row: gutter (⋮ handle + "+" button) on the left,
/// `BlockView` on the right, per-row hover state, and a `.dropDestination` for
/// drag-reorder. Lives outside `NoteEditorView` to respect the 600-line file
/// limit (pre-existing in that file).
struct DocumentBlockRow: View {
    let block: Block
    let model: NoteEditorModel
    let ordinal: Int?
    let isEditing: Bool
    let fieldFocus: FocusState<UUID?>.Binding
    let isDropTarget: Bool
    let topPadding: CGFloat
    let onActivate: () -> Void
    let onOpenRef: (UUID) -> Void
    let onAdd: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let turnInto: [(String, () -> Void)]
    let onDrop: (String) -> Bool
    let setDropTarget: (Bool) -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.xs) {
            BlockGutter(
                blockID: block.id,
                isHovering: hovering,
                canEdit: model.canEdit,
                onAdd: onAdd,
                onDelete: onDelete,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
                turnInto: turnInto
            )
            BlockView(
                block: block,
                model: model,
                onOpenRef: onOpenRef,
                ordinal: ordinal,
                isEditing: isEditing,
                onActivate: onActivate,
                focusBinding: fieldFocus
            )
        }
        .padding(.top, topPadding)
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle()
                    .fill(DS.ColorToken.accentCyan)
                    .frame(height: 2)
            }
        }
        .onHover { hovering = $0 }
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first else { return false }
            return onDrop(first)
        } isTargeted: {
            setDropTarget($0)
        }
    }
}

#endif
