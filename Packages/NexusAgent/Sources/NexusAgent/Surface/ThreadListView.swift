import Foundation
import NexusUI
import SwiftUI

/// Relative date buckets for the macOS thread rail. Newest first; only
/// non-empty buckets render a header. Pinned threads float above all buckets.
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
    public let onUnarchive: (UUID) -> Void
    public let onDelete: (UUID) -> Void
    public let onRename: (UUID, String) -> Void
    public let onTogglePin: (UUID) -> Void
    public let onExportMarkdown: (UUID) -> String

    /// Multi-select state, owned by the caller so the rail host can react.
    @State private var selection = SelectionModel<UUID>()
    @State private var undo = UndoController()
    @State private var renamingThreadID: UUID?
    @State private var renameText = ""

    public init(
        threads: [AgentThread],
        currentThreadID: UUID?,
        onSelect: @escaping (UUID) -> Void,
        onArchive: @escaping (UUID) -> Void,
        onUnarchive: @escaping (UUID) -> Void = { _ in },
        onDelete: @escaping (UUID) -> Void = { _ in },
        onRename: @escaping (UUID, String) -> Void = { _, _ in },
        onTogglePin: @escaping (UUID) -> Void = { _ in },
        onExportMarkdown: @escaping (UUID) -> String = { _ in "" }
    ) {
        self.threads = threads
        self.currentThreadID = currentThreadID
        self.onSelect = onSelect
        self.onArchive = onArchive
        self.onUnarchive = onUnarchive
        self.onDelete = onDelete
        self.onRename = onRename
        self.onTogglePin = onTogglePin
        self.onExportMarkdown = onExportMarkdown
    }

    public var body: some View {
        platformList
            // Global ⌘A + palette "Select All Items": select every active
            // (non-archived) thread — the same set the BulkActionBar's allIDs use.
            .selectAllCommandTarget(in: selection, ids: Self.filterActive(threads: threads).map(\.id))
            .onReceive(NotificationCenter.default.publisher(for: .nexusSelectAllActiveSurface)) { _ in
                selection.enterSelection()
                selection.selectAll(Self.filterActive(threads: threads).map(\.id))
            }
    }

    @ViewBuilder
    private var platformList: some View {
        #if os(macOS)
        macList
            .undoToast(undo)
            .background(renameAlert)
        #else
        iosList
            .undoToast(undo)
            .background(renameAlert)
        #endif
    }

    // MARK: - macOS (Liquid rail)

    #if os(macOS)
    /// macOS rail: a `ScrollView` of date-grouped rows (eyebrow header per
    /// bucket) over the shell's glass content panel. Pinned threads float above
    /// the date-bucketed sections. Long-press enters multi-select mode.
    private var macList: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    let pinned = Self.filterPinned(threads: threads)
                    if !pinned.isEmpty {
                        bucketHeader("Pinned")
                        ForEach(pinned, id: \.id) { thread in
                            threadButton(thread)
                        }
                    }
                    ForEach(Self.bucketed(threads: threads, now: Date()), id: \.bucket) { group in
                        bucketHeader(group.bucket.title)
                        ForEach(group.threads, id: \.id) { thread in
                            threadButton(thread)
                        }
                    }
                }
                .padding(.horizontal, DS.Space.xs)
                .padding(.top, DS.Space.xs)
                .padding(.bottom, selection.isSelecting ? 56 + DS.Space.m : DS.Space.m)
            }
            .scrollIndicators(.never)

            BulkActionBar(
                model: selection,
                allIDs: Self.filterActive(threads: threads).map(\.id),
                actions: bulkActions
            )
            .padding(.horizontal, DS.Space.xs)
            .padding(.bottom, DS.Space.xs)
        }
    }

    private func threadButton(_ thread: AgentThread) -> some View {
        Button {
            if !selection.isSelecting { onSelect(thread.id) }
        } label: {
            ThreadRow(
                thread: thread,
                isSelected: thread.id == currentThreadID,
                isPinned: thread.pinnedAt != nil
            )
        }
        .buttonStyle(.plain)
        .selectable(
            isSelecting: selection.isSelecting,
            isSelected: selection.isSelected(id: thread.id),
            onToggle: { selection.toggle(id: thread.id) }
        )
        .onLongPressGesture {
            selection.enterSelection()
            selection.toggle(id: thread.id)
        }
        .contextMenu {
            threadContextMenu(thread)
        }
        .accessibilityAddTraits(thread.id == currentThreadID ? .isSelected : [])
    }

    /// Tracked-caption date eyebrow (Today / Yesterday / Earlier / Pinned).
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
        ZStack(alignment: .bottom) {
            List {
                let pinned = Self.filterPinned(threads: threads)
                if !pinned.isEmpty {
                    Section("Pinned") {
                        ForEach(pinned, id: \.id) { thread in
                            iosRow(thread)
                        }
                    }
                }
                Section {
                    ForEach(Self.sorted(threads: Self.filterActive(threads: threads)), id: \.id) { thread in
                        iosRow(thread)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(NexusColor.Background.panel)

            BulkActionBar(
                model: selection,
                allIDs: Self.filterActive(threads: threads).map(\.id),
                actions: bulkActions
            )
            .padding(.horizontal, DS.Space.s)
            .padding(.bottom, DS.Space.xs)
        }
    }

    private func iosRow(_ thread: AgentThread) -> some View {
        Button {
            if !selection.isSelecting { onSelect(thread.id) }
        } label: {
            ThreadRow(
                thread: thread,
                isSelected: thread.id == currentThreadID,
                isPinned: thread.pinnedAt != nil
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(rowBackground(for: thread))
        .selectable(
            isSelecting: selection.isSelecting,
            isSelected: selection.isSelected(id: thread.id),
            onToggle: { selection.toggle(id: thread.id) }
        )
        .onLongPressGesture {
            selection.enterSelection()
            selection.toggle(id: thread.id)
        }
        .swipeActions(edge: .leading) {
            Button {
                onTogglePin(thread.id)
            } label: {
                Label(
                    thread.pinnedAt == nil ? "Pin" : "Unpin",
                    systemImage: thread.pinnedAt == nil ? "pin" : "pin.slash"
                )
            }
            .tint(DS.ColorToken.accentPrimary)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                let id = thread.id
                onArchive(id)
                undo.show(message: "Thread archived", icon: "archivebox") {
                    onUnarchive(id)
                }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Button(role: .destructive) {
                onDelete(thread.id)
                // Hard delete — irreversible; no undo toast.
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            threadContextMenu(thread)
        }
        .accessibilityAddTraits(thread.id == currentThreadID ? .isSelected : [])
    }

    private func rowBackground(for thread: AgentThread) -> Color {
        thread.id == currentThreadID ? NexusColor.Background.raised : NexusColor.Background.panel
    }
    #endif

    // MARK: - Shared: context menu

    @ViewBuilder
    private func threadContextMenu(_ thread: AgentThread) -> some View {
        // Rename — inline sheet handled via renamingThreadID state
        Button {
            renamingThreadID = thread.id
            renameText = thread.title
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            onTogglePin(thread.id)
        } label: {
            Label(
                thread.pinnedAt == nil ? "Pin" : "Unpin",
                systemImage: thread.pinnedAt == nil ? "pin" : "pin.slash"
            )
        }

        Button {
            PasteboardCopy.string(onExportMarkdown(thread.id))
        } label: {
            Label("Export as Markdown", systemImage: "doc.plaintext")
        }

        Divider()

        Button(role: .destructive) {
            let id = thread.id
            onArchive(id)
            undo.show(message: "Thread archived", icon: "archivebox") {
                onUnarchive(id)
            }
        } label: {
            Label("Archive", systemImage: "archivebox")
        }

        Button(role: .destructive) {
            onDelete(thread.id)
            // Hard delete — irreversible; no undo toast.
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Bulk actions

    private var bulkActions: [BulkAction] {
        var actions: [BulkAction] = []
        actions.append(BulkAction(label: "Archive", systemImage: "archivebox") { [self] in bulkArchive() })
        actions.append(BulkAction(label: "Delete", systemImage: "trash", role: .destructive) { [self] in bulkDelete() })
        return actions
    }

    private func bulkArchive() {
        let ids = Array(selection.selectedIDs)
        ids.forEach { onArchive($0) }
        selection.exitSelection()
        undo.show(message: "Archived \(ids.count)", icon: "archivebox") { [self] in
            ids.forEach { onUnarchive($0) }
        }
    }

    private func bulkDelete() {
        let ids = Array(selection.selectedIDs)
        ids.forEach { onDelete($0) }
        selection.exitSelection()
        // Hard delete — irreversible; no undo toast.
    }

}

// MARK: - Pure ordering / bucketing (nonisolated statics; moved outside struct for type_body_length)

extension ThreadListView {
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

    /// Returns pinned threads (newest-pinned first), excluding archived threads.
    nonisolated public static func filterPinned(threads: [AgentThread]) -> [AgentThread] {
        threads
            .filter { $0.archivedAt == nil && $0.pinnedAt != nil }
            .sorted { lhs, rhs in
                guard let lhsPin = lhs.pinnedAt, let rhsPin = rhs.pinnedAt else { return false }
                return lhsPin > rhsPin
            }
    }

    /// Active (unpinned) threads, newest first, grouped into Today / Yesterday / Earlier.
    /// Pinned threads are excluded — they render in their own section above.
    nonisolated public static func bucketed(
        threads: [AgentThread],
        now: Date,
        calendar: Calendar = .current
    ) -> [(bucket: ThreadDateBucket, threads: [AgentThread])] {
        let active = sorted(threads: filterActive(threads: threads))
            .filter { $0.pinnedAt == nil }
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

// MARK: - Rename alert overlay

extension ThreadListView {
    /// Overlays a simple rename alert when `renamingThreadID` is set.
    /// The `body` property cannot present alerts directly on the `ZStack` without
    /// a `@State` binding — we add a transparent `.alert` modifier here.
    var renameAlert: some View {
        let isPresenting = Binding<Bool>(
            get: { renamingThreadID != nil },
            set: { if !$0 { renamingThreadID = nil } }
        )
        return Color.clear
            .alert("Rename Thread", isPresented: isPresenting) {
                TextField("Title", text: $renameText)
                Button("Rename") {
                    if let id = renamingThreadID {
                        onRename(id, renameText)
                    }
                    renamingThreadID = nil
                }
                Button("Cancel", role: .cancel) {
                    renamingThreadID = nil
                }
            }
    }
}
