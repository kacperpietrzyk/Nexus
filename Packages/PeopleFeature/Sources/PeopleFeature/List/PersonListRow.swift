import NexusCore
import NexusUI
import SwiftUI

/// Row hover wash — same value as the Liquid kit's dense-list rows
/// (`LiquidListKit.taskRowHoverFill`, private there): no scale in dense lists,
/// just a subtle fill.
let personRowHoverFill = Color.white.opacity(0.04)

/// A single row in the people list: glass avatar pill + display name + a dense
/// secondary line (company · email) + a trailing meeting-count label. Liquid
/// language: DS type scale, hover wash on macOS, no chip chrome.
struct PersonListRow: View {
    let person: Person
    /// Attended-meeting count for the trailing label; resolved once via a batched
    /// fetch by the list. Defaults to 0 (no label) for reuse sites — e.g. the merge
    /// picker — that have no count to show.
    var meetingCount: Int = 0

    @State private var hovering = false

    var body: some View {
        HStack(spacing: DS.Space.s) {
            LiquidAvatar(name: displayName, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s)
            if meetingCount > 0 {
                Text(meetingLabel)
                    .font(DS.FontToken.metadata)
                    .monospacedDigit()
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .accessibilityLabel(
                        "\(meetingCount) \(meetingCount == 1 ? "meeting" : "meetings")"
                    )
            }
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, DS.Space.xs)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(hovering ? personRowHoverFill : .clear)
        }
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
    }

    private var displayName: String {
        person.displayName.isEmpty ? "Unnamed" : person.displayName
    }

    /// Secondary line: company/role joined with the first contact detail by a
    /// middot. Drops empty parts so a company-only or email-only person reads
    /// cleanly.
    private var subtitle: String {
        let company = person.company?.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = [person.email, person.phone]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return [company, contact]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var meetingLabel: String {
        meetingCount == 1 ? "1 meeting" : "\(meetingCount) meetings"
    }
}
