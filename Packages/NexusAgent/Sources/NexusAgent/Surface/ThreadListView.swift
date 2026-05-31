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
        .background(NexusColor.Background.panel)
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
        // Linear flat surface: selected row uses Background.raised for subtle
        // elevation contrast over the panel background; unselected stays panel.
        thread.id == currentThreadID ? NexusColor.Background.raised : NexusColor.Background.panel
    }
}

private struct ThreadRow: View {
    let thread: AgentThread
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            selectedIndicator

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.displayTitle(for: thread))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? NexusColor.Text.primary : NexusColor.Text.secondary)
                    .lineLimit(1)

                Text(thread.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var selectedIndicator: some View {
        // Linear active-selection: lime indicator bar (the single primary-action
        // accent for this surface). Hidden when unselected; Line.regular fill
        // is moot at opacity 0 but kept for zero-cost intent clarity.
        Capsule()
            .fill(isSelected ? NexusColor.Accent.lime : NexusColor.Line.regular)
            .frame(width: 4, height: 28)
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
    }

    nonisolated private static func displayTitle(for thread: AgentThread) -> String {
        let trimmed = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
