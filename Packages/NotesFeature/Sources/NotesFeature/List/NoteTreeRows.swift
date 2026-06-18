#if os(macOS)

import NexusCore
import NexusUI
import SwiftUI

/// One note leaf in the tree. Mirrors the visual family of `LiquidNoteRow` —
/// hover wash, `glassSelected` fill on selection, role-aware glyph.
struct NoteTreeLeaf: View {
    let note: Note
    let isCanonical: Bool
    let isSelected: Bool
    /// Optional pin toggle; `nil` hides the star (e.g. canonical project pages,
    /// templates — structural notes that should not be pinned to Today).
    var onTogglePin: (() -> Void)?

    @State private var hovering = false

    private static let hoverFill = Color.white.opacity(0.04)

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: isCanonical ? "doc.badge.gearshape" : "circle.fill")
                .font(.system(size: isCanonical ? 10 : 4))
                .foregroundStyle(
                    isCanonical ? DS.ColorToken.textSecondary : DS.ColorToken.textTertiary
                )
                .frame(width: 12)
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(DS.FontToken.body)
                .foregroundStyle(
                    isSelected ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary
                )
                .lineLimit(1)
            Spacer(minLength: 0)
            if let onTogglePin {
                LiquidPinButton(isPinned: note.isPinned, toggle: onTogglePin)
                    .opacity(hovering || note.isPinned ? 1 : 0)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, DS.Space.xs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                .fill(isSelected ? DS.ColorToken.glassSelected : hovering ? Self.hoverFill : .clear)
        )
        .contentShape(Rectangle())
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
    }
}

/// A recursive Library folder node using `DisclosureGroup`.
/// Each folder shows its name, nested sub-folders, and leaf notes.
struct NoteFolderDisclosure<Menu: View>: View {
    let node: NoteTreeModel.FolderNode
    let selection: UUID?
    let isExpanded: (String) -> Bool
    let setExpanded: (String, Bool) -> Void
    let onSelect: (UUID) -> Void
    /// Per-note context menu, supplied by the owner so Library notes share the
    /// same Move / Convert / Delete actions as the flat-section leaves.
    @ViewBuilder let noteMenu: (Note) -> Menu

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { isExpanded(node.id) },
                set: { setExpanded(node.id, $0) }
            )
        ) {
            ForEach(node.children) { child in
                NoteFolderDisclosure(
                    node: child,
                    selection: selection,
                    isExpanded: isExpanded,
                    setExpanded: setExpanded,
                    onSelect: onSelect,
                    noteMenu: noteMenu
                )
                .padding(.leading, DS.Space.m)
            }
            ForEach(node.notes) { note in
                NoteTreeLeaf(
                    note: note,
                    isCanonical: false,
                    isSelected: note.id == selection
                )
                .padding(.leading, DS.Space.m)
                .onTapGesture { onSelect(note.id) }
                .contextMenu { noteMenu(note) }
            }
        } label: {
            Label(node.name, systemImage: "folder")
                .font(DS.FontToken.bodyStrong)
                .foregroundStyle(DS.ColorToken.textPrimary)
        }
    }
}

#endif
