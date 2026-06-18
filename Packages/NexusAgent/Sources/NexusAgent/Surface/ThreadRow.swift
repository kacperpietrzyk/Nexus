import NexusUI
import SwiftUI

#if os(macOS)
/// Selected thread-row corner radius — matches the main sidebar nav row
/// (`LiquidSidebarNavRow`, `docs/03_COMPONENTS.md` §Sidebar: "nav row radius:
/// 10 pt") so the Agent rail's active marker reads as the same rounded glass
/// pill, not a full-bleed rectangle.
private let threadRowCornerRadius: CGFloat = 10
#endif

/// A single thread row for the Agent rail: title + relative timestamp + optional
/// pin indicator. Extracted from `ThreadListView` to keep that file under the
/// swiftlint file-length limit.
struct ThreadRow: View {
    let thread: AgentThread
    let isSelected: Bool
    let isPinned: Bool

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.accentPrimary.opacity(0.75))
                    }
                    Text(Self.displayTitle(for: thread))
                        .font(isSelected ? DS.FontToken.bodyStrong : DS.FontToken.body)
                        .foregroundStyle(isSelected ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary)
                        .lineLimit(1)
                }

                Text(thread.updatedAt, style: .relative)
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, DS.Space.xs)
        .background { rowBackground }
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var rowBackground: some View {
        #if os(macOS)
        RoundedRectangle(cornerRadius: threadRowCornerRadius, style: .continuous)
            .fill(selectionFill)
            .overlay {
                if isSelected {
                    ZStack {
                        DS.ColorToken.accentPrimary.opacity(0.060)
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), Color.white.opacity(0.026), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: threadRowCornerRadius, style: .continuous))
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: threadRowCornerRadius, style: .continuous)
                        .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
                }
            }
            .shadow(
                color: isSelected ? DS.ColorToken.accentPrimary.opacity(0.08) : .clear,
                radius: 8,
                x: 0,
                y: 0
            )
        #else
        EmptyView()
        #endif
    }

    #if os(macOS)
    private var selectionFill: Color {
        if isSelected { return Color.white.opacity(0.052) }
        if hovering { return Color.white.opacity(0.04) }
        return .clear
    }
    #endif

    nonisolated private static func displayTitle(for thread: AgentThread) -> String {
        let trimmed = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
