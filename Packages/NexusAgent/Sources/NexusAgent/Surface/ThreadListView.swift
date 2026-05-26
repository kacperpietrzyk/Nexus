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
        // §2 value-identical zero-pixel rename: Accent.soft ≡ Glass.surface2
        // (both white.opacity(0.06)) — the achromatic-translucent-fill class,
        // never a §3 de-hue. Else-branch already achromatic, untouched.
        thread.id == currentThreadID ? NexusColor.Glass.surface2 : NexusColor.Background.panel
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
        // §2 value-identical zero-pixel rename: Accent.solid ≡ Text.primary
        // (both 0xF2F2F4). A selection indicator correctly carries the
        // most-salient ink (state-via-contrast vs the unselected Line.regular);
        // a selection indicator's emphasis IS its function, distinct from a
        // decorative identity glyph, so the identity-glyph-is-not-Emphasis §3
        // override does not fire — the hex-equal §2 path stands.
        Capsule()
            .fill(isSelected ? NexusColor.Text.primary : NexusColor.Line.regular)
            .frame(width: 4, height: 28)
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
    }

    nonisolated private static func displayTitle(for thread: AgentThread) -> String {
        let trimmed = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
