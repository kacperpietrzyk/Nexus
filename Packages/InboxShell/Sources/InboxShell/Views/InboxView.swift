import NexusUI
import SwiftData
import SwiftUI

public struct InboxView: View {
    private let registry: InboxSourceRegistry
    private let onUnreadCountChanged: @MainActor (Int) -> Void
    private let onOpen: @MainActor (InboxItem) -> Void
    private let onItemsChanged: @MainActor ([InboxItem]) -> Void

    @State private var items: [InboxItem] = []
    @State private var error: String?
    @State private var selectedItem: InboxItem?
    // Stale-reload guard: a slow reload racing a newer one must not clobber
    // the fresher one's items/error/selection or re-publish via onItemsChanged.
    // Mirrors TodayDashboard.reloadGeneration (§5 contract).
    @State private var reloadGeneration = 0
    @State private var readItemIDs: Set<UUID> = []
    // Internal fallback owner for the active filter when the host does not
    // hoist it. macOS hoists it (the §1a control-mode top bar in the Mac
    // shell drives this same state); iOS keeps the internal owner so its
    // in-list filter bar works without any host wiring.
    @State private var localActiveFilter: InboxFilter = .all
    private let externalActiveFilter: Binding<InboxFilter>?

    private var activeFilter: Binding<InboxFilter> {
        externalActiveFilter ?? $localActiveFilter
    }

    public init(
        registry: InboxSourceRegistry = .shared,
        activeFilter: Binding<InboxFilter>? = nil,
        onUnreadCountChanged: @escaping @MainActor (Int) -> Void = { _ in },
        onItemsChanged: @escaping @MainActor ([InboxItem]) -> Void = { _ in },
        onOpen: @escaping @MainActor (InboxItem) -> Void
    ) {
        self.registry = registry
        self.externalActiveFilter = activeFilter
        self.onUnreadCountChanged = onUnreadCountChanged
        self.onItemsChanged = onItemsChanged
        self.onOpen = onOpen
    }

    public var body: some View {
        #if os(macOS)
        macLayout
        #else
        iosLayout
        #endif
    }

    #if os(macOS)
    private var macLayout: some View {
        // Inbox-oracle 2-column geometry (`Lab/InboxPreview.swift`): LEFT
        // list panel leading (max content width 560, panel padding
        // leading 26 / bottom 24) + RIGHT reader pane fixed 380, HStack
        // `.top`. §1a control mode: the filter tabs were relocated out of
        // this panel header into the Mac shell's top-bar band.
        HStack(alignment: .top, spacing: 0) {
            InboxListPanel(
                items: filteredItems,
                error: error,
                readItemIDs: $readItemIDs,
                selectedItem: $selectedItem
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Spacer(minLength: 36)

            InboxReaderPane(
                item: selectedItem,
                emptyState: filteredItems.isEmpty ? .emptyInbox : .noSelection,
                onOpen: { item in onOpen(item) },
                onArchive: { item in Task { await archive(item) } },
                onSnooze: { item, hours in Task { await snooze(item, hours: hours) } }
            )
            .frame(width: InboxLayout.readerWidth)
            .frame(maxHeight: .infinity)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .padding(.trailing, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await reload(selectFirstItem: true) }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Task { await reload(selectFirstItem: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nexusMarkInboxRead)) { _ in
            Task { await markAllRead() }
        }
        .onChange(of: readItemIDs) { _, _ in
            onUnreadCountChanged(unreadCount)
        }
    }
    #endif

    private var iosLayout: some View {
        VStack(spacing: 8) {
            inboxFilterBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
            listContent
        }
        .background(Color.clear)
        .task { await reload(selectFirstItem: false) }
        .refreshable { await reload(selectFirstItem: false) }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Task { await reload(selectFirstItem: false) }
        }
    }

    private var listContent: some View {
        List {
            if error != nil {
                ContentUnavailableView("Couldn't load the Inbox", systemImage: "exclamationmark.triangle")
                    .listRowBackground(Color.clear)
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    "Inbox is empty",
                    systemImage: "tray",
                    description: Text("New mentions, digests, and captured items appear here.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredItems) { item in
                    Button {
                        onOpen(item)
                    } label: {
                        InboxCompactRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await archive(item) }
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        // §2 value-identical rename: Semantic.positive == Text.secondary (0xC7C8CE);
                        // §3 categorical swipe action → Text.secondary (glyph+label carry distinction,
                        // never two hues for sibling actions — MP-4.1 .tint-don't-drop precedent).
                        .tint(NexusColor.Text.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            Task { await snooze(item, hours: 1) }
                        } label: {
                            Label("1h", systemImage: "clock")
                        }
                        // §3 categorical swipe sibling → same Text.secondary as Archive above
                        // (MP-4.1 .tint-don't-drop precedent; two sibling actions share one ink step).
                        .tint(NexusColor.Text.secondary)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var filteredItems: [InboxItem] {
        activeFilter.wrappedValue.apply(to: items)
    }

    private var inboxFilterBar: some View {
        NexusTabBar(items: InboxFilter.tabItems, active: activeFilter)
    }

    @MainActor
    private func reload(selectFirstItem: Bool) async {
        reloadGeneration += 1
        let generation = reloadGeneration
        do {
            let loaded = try await registry.allItems()
            guard generation == reloadGeneration else { return }
            items = loaded
            error = nil
            reconcileSelection(selectFirstItem: selectFirstItem)
            // Only the winning reload publishes its set: a stale reload must
            // not call back at all (§5 — both writes after the stale-guard).
            onItemsChanged(items)
        } catch {
            guard generation == reloadGeneration else { return }
            items = []
            selectedItem = nil
            self.error = String(describing: error)
            onItemsChanged(items)
        }
    }

    @MainActor
    private func reconcileSelection(selectFirstItem: Bool) {
        guard !items.isEmpty else {
            selectedItem = nil
            return
        }

        if let selectedItem, filteredItems.contains(where: { $0.id == selectedItem.id }) {
            return
        }

        if selectFirstItem {
            selectedItem = filteredItems.first
            if let first = selectedItem {
                markRead(first)
            }
        }
    }

    @MainActor
    private func markRead(_ item: InboxItem) {
        readItemIDs.insert(item.id)
    }

    // archive/snooze request `selectFirstItem: true`, but if a concurrent
    // `didSave` reload wins the generation race the stale-return skips
    // `reconcileSelection` and the "auto-select next" UX is silently dropped.
    // This is §5-correct (matches the Today anchor) and benign — documented
    // so a future audit of this flow isn't surprised.
    @MainActor
    private func archive(_ item: InboxItem) async {
        try? await registry.archive(item)
        await reload(selectFirstItem: true)
        onUnreadCountChanged(unreadCount)
    }

    @MainActor
    private func snooze(_ item: InboxItem, hours: Int) async {
        let date = Date().addingTimeInterval(TimeInterval(hours * 60 * 60))
        try? await registry.snooze(item, until: date)
        await reload(selectFirstItem: true)
        onUnreadCountChanged(unreadCount)
    }

    @MainActor
    private func markAllRead() async {
        readItemIDs.formUnion(items.map(\.id))
    }

    private var unreadCount: Int {
        items.filter { !readItemIDs.contains($0.id) }.count
    }
}

/// Inbox triage filter. Public so the host can hoist the active selection
/// into the §1a control-mode top-bar band (the Mac shell drives the same
/// state the in-Inbox filtering consumes). Label strings match the accepted
/// Inbox oracle (`Lab/InboxPreview.swift` — visual source of truth).
public enum InboxFilter: String, Hashable, Sendable, CaseIterable {
    case all
    case people
    case digests
    case mentions

    /// Tab label, 1:1 with the Inbox oracle's `InboxTab` strings.
    public var displayLabel: String {
        switch self {
        case .all: return "All"
        case .people: return "People"
        case .digests: return "Digests"
        case .mentions: return "Mentions"
        }
    }

    public static let tabItems: [NexusTabBarItem<InboxFilter>] = InboxFilter.allCases.map {
        NexusTabBarItem(id: $0, label: $0.displayLabel)
    }

    public func apply(to items: [InboxItem]) -> [InboxItem] {
        switch self {
        case .all:
            return items
        case .people:
            return items.filter { $0.category == .people }
        case .digests:
            return items.filter { $0.category == .digests }
        case .mentions:
            return items.filter { $0.category == .mentions }
        }
    }

    /// Count of items this filter would surface, derived from the SAME
    /// already-loaded set the list renders (`InboxItemCategory` over
    /// `items`). No new query, no new behaviour — presentation derivation
    /// for the §1a top-bar tab idiom (oracle shows a count beside each tab).
    public func count(in items: [InboxItem]) -> Int {
        apply(to: items).count
    }
}

private struct InboxCompactRow: View {
    let item: InboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .nexusType(.bodySmall)
                .foregroundStyle(NexusColor.Text.primary)
            if let body = item.body, !body.isEmpty {
                Text(body)
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .lineLimit(2)
            }
            if !item.tags.isEmpty {
                Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                    .nexusType(.caption)
                    // §3 Mac-mirror: InboxReaderPane uses NexusChip(tone:.neutral) for tags,
                    // which resolves to Text.tertiary (NexusChip.swift:72). Caption-level metadata
                    // below title (primary) and snippet (tertiary) — Text.tertiary is the matched step.
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// `InboxItemGroup` (category-grouped flat structure) and the macOS list
// panel / section / row / avatar views were superseded by the data-driven
// §3 section idiom and moved to the `InboxView+Sections.swift` sibling
// (MP-3.1 slice 2). `InboxCompactRow` above stays — it is the iOS list row,
// untouched by this Mac-only slice.
