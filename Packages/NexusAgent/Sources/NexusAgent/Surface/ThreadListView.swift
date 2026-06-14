import Foundation
import NexusUI
import SwiftUI

#if os(macOS)
/// Selected thread-row corner radius — matches the main sidebar nav row
/// (`LiquidSidebarNavRow`, `docs/03_COMPONENTS.md` §Sidebar: "nav row radius:
/// 10 pt") so the Agent rail's active marker reads as the same rounded glass
/// pill, not a full-bleed rectangle.
private let threadRowCornerRadius: CGFloat = 10
#endif

/// Relative date buckets for the macOS thread rail. Newest first; only
/// non-empty buckets render a header.
public enum ThreadDateBucket: String, CaseIterable, Hashable, Sendable {
    case today
    case yesterday
    case earlier

    public var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .earlier: return "Earlier"
        }
    }
}

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
        #if os(macOS)
        macList
        #else
        iosList
        #endif
    }

    // MARK: - macOS (Liquid rail)

    #if os(macOS)
    /// macOS rail: a `ScrollView` of date-grouped rows (eyebrow header per
    /// bucket) over the shell's glass content panel. The `List`/`.sidebar`
    /// path is iOS-only — on macOS it forced a full-bleed rectangular row
    /// background for the selection; this gives the active thread a rounded
    /// glass pill with depth, matching `LiquidSidebarNavRow`.
    private var macList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(Self.bucketed(threads: threads, now: Date()), id: \.bucket) { group in
                    bucketHeader(group.bucket.title)
                    ForEach(group.threads, id: \.id) { thread in
                        Button {
                            onSelect(thread.id)
                        } label: {
                            ThreadRow(thread: thread, isSelected: thread.id == currentThreadID)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                onArchive(thread.id)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }
                        .accessibilityAddTraits(thread.id == currentThreadID ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, DS.Space.xs)
            .padding(.top, DS.Space.xs)
            .padding(.bottom, DS.Space.m)
        }
        .scrollIndicators(.never)
    }

    /// Tracked-caption date eyebrow (Today / Yesterday / Earlier) — the same
    /// idiom as the chat's "Recent tools" rail header.
    private func bucketHeader(_ title: String) -> some View {
        Text(title)
            .font(DS.FontToken.caption)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(DS.ColorToken.textTertiary)
            .padding(.horizontal, DS.Space.xs)
            .padding(.top, DS.Space.s)
            .padding(.bottom, DS.Space.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif

    // MARK: - iOS (native split sidebar)

    #if os(iOS)
    private var iosList: some View {
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

    private func rowBackground(for thread: AgentThread) -> Color {
        thread.id == currentThreadID ? NexusColor.Background.raised : NexusColor.Background.panel
    }
    #endif

    // MARK: - Pure ordering / bucketing

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

    /// Active threads, newest first, grouped into Today / Yesterday / Earlier.
    /// Only non-empty buckets are returned, in display order.
    nonisolated public static func bucketed(
        threads: [AgentThread],
        now: Date,
        calendar: Calendar = .current
    ) -> [(bucket: ThreadDateBucket, threads: [AgentThread])] {
        let active = sorted(threads: filterActive(threads: threads))
        // "Yesterday" is resolved against the injected `now` (not the wall
        // clock) so the bucketing is fully deterministic and testable —
        // `Calendar.isDateInYesterday` would silently compare against the real
        // current date instead.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        var grouped: [ThreadDateBucket: [AgentThread]] = [:]
        for thread in active {
            let bucket: ThreadDateBucket
            if calendar.isDate(thread.updatedAt, inSameDayAs: now) {
                bucket = .today
            } else if calendar.isDate(thread.updatedAt, inSameDayAs: yesterday) {
                bucket = .yesterday
            } else {
                bucket = .earlier
            }
            grouped[bucket, default: []].append(thread)
        }
        return ThreadDateBucket.allCases.compactMap { bucket in
            guard let rows = grouped[bucket], !rows.isEmpty else { return nil }
            return (bucket, rows)
        }
    }
}

private struct ThreadRow: View {
    let thread: AgentThread
    let isSelected: Bool

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
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
        // Rounded glass pill matching `LiquidSidebarNavRow`: selected rows take
        // the glass-selected fill + a faint accent tint, a top-leading sheen,
        // a hairline stroke and a soft accent glow (depth); hover rows take a
        // one-step-lighter wash. iOS keeps its `listRowBackground` pairing.
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
