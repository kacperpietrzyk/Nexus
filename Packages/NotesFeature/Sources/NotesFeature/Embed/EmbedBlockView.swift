import NexusCore
import NexusUI
import SwiftUI

/// Inline read-only preview of an embedded object (spec §10). Resolves a
/// lightweight snapshot (title + status) via the core resolver; tapping opens the
/// object. Cross-module targets the core resolver can't reach (e.g. Meeting)
/// render as an unresolved placeholder — a known limitation, not an error.
struct EmbedBlockView: View {
    let ref: UUID
    let kind: ItemKind
    let model: NoteEditorModel
    let onOpen: (UUID) -> Void

    var body: some View {
        Button {
            onOpen(ref)
        } label: {
            NexusCard(padding: 12) {
                HStack(spacing: 10) {
                    Image(systemName: glyph)
                        .foregroundStyle(NexusColor.Text.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot?.title ?? "Unresolved \(kindLabel)")
                            .nexusType(.body)
                            .foregroundStyle(
                                snapshot == nil ? NexusColor.Text.muted : NexusColor.Text.primary
                            )
                            .lineLimit(1)
                        if let status = snapshot?.status {
                            Text(status)
                                .nexusType(.eyebrow)
                                .foregroundStyle(NexusColor.Text.tertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(snapshot == nil)
    }

    private var snapshot: NoteRepository.EmbedSnapshot? { model.embedSnapshot(for: ref) }

    private var kindLabel: String {
        switch kind {
        case .note: return "note"
        case .task: return "task"
        case .project: return "project"
        case .section: return "section"
        default: return "item"
        }
    }

    private var glyph: String {
        switch kind {
        case .note: return "note.text"
        case .task: return "checkmark.square"
        case .project: return "folder"
        case .section: return "list.bullet"
        default: return "doc"
        }
    }
}
