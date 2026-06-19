#if os(macOS)

import NexusUI
import SwiftUI

/// The left hover gutter for one document block (macOS): a ⋮ drag handle (the
/// reorder drag SOURCE — never the text), a "+" to insert below, and a menu on
/// the handle (Delete / Turn into / Move up / Move down).
struct BlockGutter: View {
    let blockID: UUID
    let isHovering: Bool
    let canEdit: Bool
    let onAdd: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    /// (label, action) pairs for "Turn into".
    let turnInto: [(String, () -> Void)]

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(Array(turnInto.enumerated()), id: \.offset) { _, item in
                    Button(item.0) { item.1() }
                }
                Divider()
                Button("Move Up") { onMoveUp() }
                Button("Move Down") { onMoveDown() }
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .draggable(blockID.uuidString)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 34, alignment: .leading)
        .opacity(isHovering && canEdit ? 1 : 0)
        .padding(.top, 3)
        .accessibilityHidden(!isHovering)
    }
}

#endif
