import NexusCore
import NexusUI
import SwiftUI

#if os(macOS)

/// A Liquid list row for one note: role glyph + title + trailing backlinks/date
/// metadata, a one-line preview from the denormalized `plainText` cache (never
/// the block blob — spec §4.1), and a strip of tag pills. Hover answers with a
/// fill wash only (dense list — no scale per the implementation guide).
struct LiquidNoteRow: View {
    let note: Note
    let backlinkCount: Int
    let onOpen: () -> Void
    let onDelete: () -> Void
    /// Extra context-menu items injected by the list (e.g. Move to Folder).
    let extraContextMenu: AnyView?

    @State private var hovering = false

    /// Row hover wash — same value family as `LiquidTaskRow` (white 4%).
    private static let hoverFill = Color.white.opacity(0.04)

    private var tags: [String] {
        NoteListGrouping.normalizedTags(note.tags)
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: DS.Space.s) {
                roleGlyph
                    .frame(width: 16, alignment: .center)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: DS.Space.s) {
                        Text(displayTitle)
                            .font(DS.FontToken.bodyStrong)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: DS.Space.s)

                        if backlinkCount > 0 {
                            backlinkBadge
                        }

                        Text(note.updatedAt, format: .relative(presentation: .named))
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textTertiary)
                            .lineLimit(1)
                    }

                    if !preview.isEmpty {
                        Text(preview)
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                            .lineLimit(1)
                    }

                    if !tags.isEmpty {
                        HStack(spacing: DS.Space.xs) {
                            ForEach(tags.prefix(4), id: \.self) { tag in
                                LiquidPill(tag, color: DS.ColorToken.accentCyan)
                            }
                            if tags.count > 4 {
                                Text("+\(tags.count - 4)")
                                    .font(DS.FontToken.caption)
                                    .foregroundStyle(DS.ColorToken.textMuted)
                            }
                        }
                        .padding(.top, 1)
                    }
                }
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .fill(hovering ? Self.hoverFill : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        .contextMenu {
            if let extraContextMenu {
                extraContextMenu
                Divider()
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel(Text(displayTitle))
    }

    private var backlinkBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.turn.up.left")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.ColorToken.textTertiary)
            Text("\(backlinkCount)")
                .font(DS.FontToken.caption)
                .monospacedDigit()
                .foregroundStyle(DS.ColorToken.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(backlinkCount) backlinks"))
    }

    private var displayTitle: String {
        note.title.isEmpty ? "Untitled" : note.title
    }

    private var preview: String {
        note.plainText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder private var roleGlyph: some View {
        switch note.role {
        case .free:
            Image(systemName: "note.text")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.ColorToken.textMuted)
        case .projectPage:
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.ColorToken.textTertiary)
        case .dailyNote:
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.ColorToken.textTertiary)
        case .template:
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.ColorToken.textTertiary)
        }
    }
}

#endif

#if !os(macOS)

/// A single row in the notes list: a role glyph + title, a one-line preview drawn
/// from the denormalized `plainText` cache (never the block blob — spec §4.1), and
/// a metadata strip of tag chips + an optional backlink count. iOS only — macOS
/// renders `LiquidNoteRow`.
struct NoteListRow: View {
    let note: Note
    let backlinkCount: Int

    private var tags: [String] {
        NoteListGrouping.normalizedTags(note.tags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                roleGlyph
                Text(displayTitle)
                    .nexusType(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if backlinkCount > 0 {
                    backlinkBadge
                }
            }
            if !preview.isEmpty {
                Text(preview)
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.muted)
                    .lineLimit(1)
            }
            if !tags.isEmpty {
                tagStrip
            }
        }
        .padding(.vertical, 2)
    }

    private var backlinkBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.turn.up.left")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(NexusColor.Text.tertiary)
            NexusCount(value: backlinkCount, font: NexusType.metaMono)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(backlinkCount) backlinks"))
    }

    private var tagStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    NexusChip(tag, systemImage: "number")
                }
            }
        }
        .scrollDisabled(tags.count <= 3)
    }

    private var displayTitle: String {
        note.title.isEmpty ? "Untitled" : note.title
    }

    private var preview: String {
        note.plainText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder private var roleGlyph: some View {
        switch note.role {
        case .free:
            EmptyView()
        case .projectPage:
            Image(systemName: "folder")
                .foregroundStyle(NexusColor.Text.tertiary)
                .font(.caption)
        case .dailyNote:
            Image(systemName: "calendar")
                .foregroundStyle(NexusColor.Text.tertiary)
                .font(.caption)
        case .template:
            Image(systemName: "doc.on.doc")
                .foregroundStyle(NexusColor.Text.tertiary)
                .font(.caption)
        }
    }
}

#endif
