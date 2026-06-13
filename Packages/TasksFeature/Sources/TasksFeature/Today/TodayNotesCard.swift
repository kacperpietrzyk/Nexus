import NexusCore
import NexusUI
import SwiftUI

/// Tag pills shown per note before truncating — keeps dense rows readable.
private let noteTagCap = 2

/// `Notes & Knowledge` card (spec §Main bottom row 2): the most recently
/// updated notes with their tags as pills and the real Link-graph degree.
struct TodayNotesCard: View {

    let notes: [LiquidNoteSummary]
    let onOpenNotes: () -> Void

    var body: some View {
        TodayGlassCard("Notes & Knowledge") {
            if notes.isEmpty {
                LiquidEmptyState(
                    systemImage: "note.text",
                    message: "No notes yet — capture what you know."
                ) {
                    LiquidPrimaryButton("Open Notes", action: onOpenNotes)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(notes) { summary in
                        TodayNoteRow(summary: summary, action: onOpenNotes)
                    }
                    Spacer(minLength: 0)
                    LiquidCardFooterLink("Open all notes", action: onOpenNotes)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

private struct TodayNoteRow: View {
    let summary: LiquidNoteSummary
    let action: () -> Void

    @State private var hovering = false

    private var title: String {
        summary.note.title.isEmpty ? "Untitled note" : summary.note.title
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.s) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.ColorToken.accentCyan)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title)
                        .font(DS.FontToken.bodyStrong)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                        .lineLimit(1)

                    if !summary.note.tags.isEmpty {
                        HStack(spacing: DS.Space.xxs) {
                            ForEach(summary.note.tags.prefix(noteTagCap), id: \.self) { tag in
                                LiquidPill(tag, color: DS.ColorToken.accentPurple)
                            }
                            if summary.note.tags.count > noteTagCap {
                                Text("+\(summary.note.tags.count - noteTagCap)")
                                    .font(DS.FontToken.caption)
                                    .foregroundStyle(DS.ColorToken.textMuted)
                            }
                        }
                    }

                    if summary.linkCount > 0 {
                        Text(summary.linkCount == 1 ? "1 link" : "\(summary.linkCount) links")
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.m)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .fill(hovering ? Color.white.opacity(0.030) : Color.white.opacity(0.006))
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(0.026), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .stroke(Color.white.opacity(0.050), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open note \(title)")
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
    }
}
