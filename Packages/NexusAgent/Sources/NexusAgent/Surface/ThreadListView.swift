import Foundation
import NexusUI
import SwiftUI

public struct ThreadListView: View {
    public let threads: [AgentThread]
    public let currentThreadID: UUID?
    public let onSelect: (UUID) -> Void
    public let onArchive: (UUID) -> Void

    public init(
        threads: [AgentThread],
        currentThreadID: UUID?,
        onSelect: @escaping (UUID) -> Void,
        onArchive: @escaping (UUID) -> Void
    ) {
        self.threads = threads
        self.currentThreadID = currentThreadID
        self.onSelect = onSelect
        self.onArchive = onArchive
    }

    public var body: some View {
        List(Self.sorted(threads: Self.filterActive(threads: threads)), id: \.id) { thread in
            Button {
                onSelect(thread.id)
            } label: {
                ThreadRow(
                    thread: thread,
                    isSelected: thread.id == currentThreadID
                )
            }
            .buttonStyle(.plain)
            .listRowBackground(rowBackground(for: thread))
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    onArchive(thread.id)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }
            .accessibilityAddTraits(thread.id == currentThreadID ? .isSelected : [])
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(containerBackground)
    }

    /// Liquid re-skin (container level): transparent on macOS so the thread
    /// rail sits on the shell's glass content panel instead of an opaque
    /// graphite slab; iOS keeps the Linear panel surface under its own shell.
    private var containerBackground: Color {
        #if os(macOS)
        return Color.clear
        #else
        return NexusColor.Background.panel
        #endif
    }

    nonisolated public static func sorted(threads: [AgentThread]) -> [AgentThread] {
        threads.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.uuidString > rhs.id.uuidString
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    nonisolated public static func filterActive(threads: [AgentThread]) -> [AgentThread] {
        threads.filter { $0.archivedAt == nil }
    }

    private func rowBackground(for thread: AgentThread) -> Color {
        // Liquid re-skin (macOS): rows are transparent over the shell's glass;
        // the selected row uses the DS glass-selected overlay. iOS keeps the
        // Linear panel/raised pairing under its own opaque shell.
        #if os(macOS)
        return thread.id == currentThreadID ? DS.ColorToken.glassSelected : Color.clear
        #else
        return thread.id == currentThreadID ? NexusColor.Background.raised : NexusColor.Background.panel
        #endif
    }
}

private struct ThreadRow: View {
    let thread: AgentThread
    let isSelected: Bool

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            selectedIndicator

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.displayTitle(for: thread))
                    .font(isSelected ? DS.FontToken.bodyStrong : DS.FontToken.body)
                    .foregroundStyle(isSelected ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary)
                    .lineLimit(1)

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
        .background {
            // Hover wash one step below the glass-selected row background the
            // List supplies for the active thread (macOS only — `hovering`
            // never flips elsewhere).
            if hovering && !isSelected {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            }
        }
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
        .accessibilityElement(children: .combine)
    }

    private var selectedIndicator: some View {
        // Liquid active-selection: a 2pt accent glow line on the leading edge
        // of the selected row (03_COMPONENTS §SidebarNavRow idiom).
        Capsule()
            .fill(DS.ColorToken.accentPrimary)
            .frame(width: 3, height: 28)
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
    }

    nonisolated private static func displayTitle(for thread: AgentThread) -> String {
        let trimmed = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
