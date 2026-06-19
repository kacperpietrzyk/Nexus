#if os(macOS)

import NexusUI
import SwiftUI

/// The left hover gutter for one document block (macOS): a ⋮ drag handle (the
/// reorder drag SOURCE — a plain draggable image, NOT a Menu, since a Menu would
/// swallow the drag gesture) and a "+" to insert a block below. Block actions
/// (Delete / Turn into / Move) live on the row's right-click context menu.
struct BlockGutter: View {
    let blockID: UUID
    let isHovering: Bool
    let canEdit: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(DS.ColorToken.textTertiary)
                .contentShape(Rectangle())
                .draggable(blockID.uuidString)
                .help("Drag to reorder")

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Add block below")
        }
        .frame(width: 34, alignment: .leading)
        .opacity(isHovering && canEdit ? 1 : 0)
        .padding(.top, 3)
    }
}

#endif
