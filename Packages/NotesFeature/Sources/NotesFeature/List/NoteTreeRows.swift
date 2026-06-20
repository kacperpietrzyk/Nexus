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
/// Tapping the folder **name** selects it as a container (via `onSelectFolder`);
/// the system disclosure chevron retains its own hit target for expansion.
struct NoteFolderDisclosure<Menu: View>: View {
    let node: NoteTreeModel.FolderNode
    let selection: UUID?
    let isExpanded: (String) -> Bool
    let setExpanded: (String, Bool) -> Void
    let onSelect: (UUID) -> Void
    /// Per-note pin toggle; mirrors the seam used by the flat-section `leaf(_:)`
    /// path. `nil` would suppress the hover star for every note in this folder
    /// tree — pass a non-nil closure to show it (same as non-folder leaves).
    var onTogglePin: ((Note) -> Void)?
    /// Per-note context menu, supplied by the owner so Library notes share the
    /// same Move / Convert / Delete actions as the flat-section leaves.
    @ViewBuilder let noteMenu: (Note) -> Menu
    /// Optional multi-select model; when provided, each leaf gets `.selectable`.
    var selectionModel: SelectionModel<UUID>?
    /// Called with the folder's full path when the folder name is tapped.
    var onSelectFolder: ((String) -> Void)?
    /// Returns `true` when the folder at the given path is the active container.
    var isSelectedFolder: ((String) -> Bool)?

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
                    onTogglePin: onTogglePin,
                    noteMenu: noteMenu,
                    selectionModel: selectionModel,
                    onSelectFolder: onSelectFolder,
                    isSelectedFolder: isSelectedFolder
                )
                .padding(.leading, DS.Space.m)
            }
            ForEach(node.notes) { note in
                leafRow(for: note)
                    .padding(.leading, DS.Space.m)
            }
        } label: {
            HStack(spacing: DS.Space.xs) {
                Label(node.name, systemImage: "folder")
                    .font(DS.FontToken.bodyStrong)
                    .foregroundStyle(
                        (isSelectedFolder?(node.id) ?? false)
                            ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary
                    )
                Spacer(minLength: 0)
                NexusCount(value: node.totalNoteCount, font: NexusType.metaMono)
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelectFolder?(node.id) }
        }
    }

    @ViewBuilder private func leafRow(for note: Note) -> some View {
        let leaf = NoteTreeLeaf(
            note: note,
            isCanonical: false,
            isSelected: note.id == selection,
            onTogglePin: onTogglePin.map { toggle in { toggle(note) } }
        )
        .onTapGesture {
            // In multi-select mode the row tap toggles selection instead of
            // opening the note (the `.selectable` checkmark is presentation only).
            if let model = selectionModel, model.isSelecting {
                withAnimation(DS.Motion.selection) { model.toggle(id: note.id) }
            } else {
                onSelect(note.id)
            }
        }
        .contextMenu { noteMenu(note) }

        if let model = selectionModel {
            leaf.selectable(
                isSelecting: model.isSelecting,
                isSelected: model.isSelected(id: note.id),
                onToggle: { model.toggle(id: note.id) }
            )
        } else {
            leaf
        }
    }
}

#endif
