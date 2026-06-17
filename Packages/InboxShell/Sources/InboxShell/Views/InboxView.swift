import NexusUI
import SwiftUI

public struct InboxView: View {
    private let registry: InboxSourceRegistry
    private let readStateStore: InboxReadStateStore
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
    // Windowing state. The Inbox no longer materializes every no-date task
    // (~1383) on entry — it fetches a page and grows it on scroll. `totalItemCount`
    // / `sourceTotals` carry the TRUE uncapped counts so the badge + section
    // pills stay accurate while the rendered list is only a window.
    @State private var windowLimit = InboxView.initialWindow
    @State private var totalItemCount = 0
    @State private var sourceTotals: [String: Int] = [:]
    // `reachedEnd` latches once a grow yields no new rows (the no-date `count()`
    // over-counts archived-project tasks the list post-filter drops, so the
    // window can plateau below `totalItemCount`); `isLoadingMore` debounces the
    // fire-on-appear so a burst of `.onAppear` doesn't stack grows.
    @State private var reachedEnd = false
    @State private var isLoadingMore = false

    private static let initialWindow = 50
    private static let pageGrowth = 100
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
        readStateStore: InboxReadStateStore = .shared,
        activeFilter: Binding<InboxFilter>? = nil,
        onUnreadCountChanged: @escaping @MainActor (Int) -> Void = { _ in },
        onItemsChanged: @escaping @MainActor ([InboxItem]) -> Void = { _ in },
        onOpen: @escaping @MainActor (InboxItem) -> Void
    ) {
        self.registry = registry
        self.readStateStore = readStateStore
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
                totalsBySourceID: sourceTotals,
                readItemIDs: $readItemIDs,
                selectedItem: $selectedItem,
                onReachEnd: { Task { await loadMore() } }
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
        .reloadOnStoreChange {
            Task {
                await registry.invalidateCache()
                await reload(selectFirstItem: false)
            }
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
        // Pull-to-refresh means "force fresh": invalidate so sources whose data
        // can change without a ModelContext.didSave (e.g. network-backed
        // digests/mentions) re-query, matching today's always-fresh behaviour.
        .refreshable {
            await registry.invalidateCache()
            await reload(selectFirstItem: false)
        }
        .reloadOnStoreChange {
            Task {
                await registry.invalidateCache()
                await reload(selectFirstItem: false)
            }
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
                    .onAppear {
                        // Scroll-to-grow: the last visible row pages the window in.
                        if item.id == filteredItems.last?.id { Task { await loadMore() } }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await archive(item) }
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        // Categorical swipe action → secondary ink (glyph+label carry
                        // distinction; sibling actions share one ink step, tint never dropped).
                        .tint(DS.ColorToken.textSecondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            Task { await snooze(item, hours: 1) }
                        } label: {
                            Label("1h", systemImage: "clock")
                        }
                        // Sibling action shares Archive's ink step (tint never dropped).
                        .tint(DS.ColorToken.textSecondary)
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
        // A fresh reload re-opens paging: new data (or a larger window) may have
        // more rows than the last grow saw. `loadMore` re-latches `reachedEnd`
        // after its own grow if there is still nothing new.
        reachedEnd = false
        do {
            let window = try await registry.window(limit: windowLimit)
            guard generation == reloadGeneration else { return }
            items = window.items
            sourceTotals = window.totalsBySourceID
            totalItemCount = window.totalItemCount
            error = nil
            // Rehydrate read state from durable storage (survives the tab-switch
            // remount that resets `@State`) and merge any marks made this
            // session. NO pruning to loaded ids: `items` is now only a window,
            // so intersecting would drop marks for items outside the page and
            // they'd re-appear unread on scroll. The set is bounded by the inbox
            // id space and `InboxItem.id` is stable, so unbounded growth is a
            // non-issue. Trade-off: ids of items that LEFT the inbox
            // (archived/snoozed/completed) linger, so `totalItemCount - readCount`
            // can undercount — the badge errs low, an accepted approximation.
            readItemIDs = readStateStore.load().union(readItemIDs)
            readStateStore.save(readItemIDs)
            reconcileSelection(selectFirstItem: selectFirstItem)
            // Only the winning reload publishes: a stale reload must not call
            // back at all (§5 — all reports after the stale-guard). The unread
            // badge now depends on `totalItemCount`, which only a reload sets, so
            // it must be re-reported here (not only on `readItemIDs` change).
            onItemsChanged(items)
            onUnreadCountChanged(unreadCount)
        } catch {
            guard generation == reloadGeneration else { return }
            items = []
            sourceTotals = [:]
            totalItemCount = 0
            selectedItem = nil
            self.error = String(describing: error)
            onItemsChanged(items)
            onUnreadCountChanged(unreadCount)
        }
    }

    /// Grow the window by one page when the last row scrolls into view. Latches
    /// `reachedEnd` once a grow yields no new rows so the fire-on-appear can't
    /// loop at the bottom (the no-date `count()` over-counts archived-project
    /// tasks the list post-filter drops, so the window plateaus below
    /// `totalItemCount`).
    @MainActor
    private func loadMore() async {
        guard !reachedEnd, !isLoadingMore else { return }
        guard items.count < totalItemCount else {
            reachedEnd = true
            return
        }
        isLoadingMore = true
        let before = items.count
        windowLimit += Self.pageGrowth
        await reload(selectFirstItem: false)
        if items.count <= before { reachedEnd = true }
        isLoadingMore = false
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
        readStateStore.save(readItemIDs)
    }

    // archive/snooze request `selectFirstItem: true`, but if a concurrent
    // `didSave` reload wins the generation race the stale-return skips
    // `reconcileSelection` and the "auto-select next" UX is silently dropped.
    // This is §5-correct (matches the Today anchor) and benign — documented
    // so a future audit of this flow isn't surprised.
    @MainActor
    private func archive(_ item: InboxItem) async {
        try? await registry.archive(item)
        // The mutation changes the source's items; drop the cache so the reload
        // below reflects the removal immediately (don't wait for the debounced
        // store-change observer).
        await registry.invalidateCache()
        await reload(selectFirstItem: true)
        onUnreadCountChanged(unreadCount)
    }

    @MainActor
    private func snooze(_ item: InboxItem, hours: Int) async {
        let date = Date().addingTimeInterval(TimeInterval(hours * 60 * 60))
        try? await registry.snooze(item, until: date)
        // Snooze removes the item from the live list; drop the cache so the
        // reload reflects it immediately (mirrors archive).
        await registry.invalidateCache()
        await reload(selectFirstItem: true)
        onUnreadCountChanged(unreadCount)
    }

    @MainActor
    private func markAllRead() async {
        // Windowing means `items` is only a page — marking just the visible
        // window would leave the badge (total − readCount) high. Mark EVERY
        // inbox id read via a one-shot full fetch. This is rare + user-initiated
        // (off the hot navigation path), so the full materialization is fine;
        // it falls back to the loaded window if the fetch fails.
        let allIDs = (try? await registry.allItems().map(\.id)) ?? items.map(\.id)
        readItemIDs.formUnion(allIDs)
        // Persist immediately: the user may switch tabs (unmounting this view)
        // before any reload/`didSave` would otherwise flush the set.
        readStateStore.save(readItemIDs)
        onUnreadCountChanged(unreadCount)
    }

    private var unreadCount: Int {
        // True total minus everything marked read. Mirrors `ContentView`'s
        // closed-Inbox formula exactly so the badge doesn't jump on enter/exit.
        max(0, totalItemCount - readItemIDs.count)
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
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
            if let body = item.body, !body.isEmpty {
                Text(body)
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .lineLimit(2)
            }
            if !item.tags.isEmpty {
                Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(DS.FontToken.metadata)
                    // Tag metadata sits one ink step below the snippet — matches the
                    // Mac reader pane's neutral LiquidPill tags.
                    .foregroundStyle(DS.ColorToken.textTertiary)
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
