import NexusUI
import SwiftUI

public struct InboxView: View {
    let registry: InboxSourceRegistry
    let readStateStore: InboxReadStateStore
    let onUnreadCountChanged: @MainActor (Int) -> Void
    let onOpen: @MainActor (InboxItem) -> Void
    let onItemsChanged: @MainActor ([InboxItem]) -> Void

    @State var items: [InboxItem] = []
    @State var error: String?
    @State var selectedItem: InboxItem?
    // Stale-reload guard: a slow reload racing a newer one must not clobber
    // the fresher one's items/error/selection or re-publish via onItemsChanged.
    // Mirrors TodayDashboard.reloadGeneration (§5 contract).
    @State var reloadGeneration = 0
    @State var readItemIDs: Set<UUID> = []
    // Windowing state. The Inbox no longer materializes every no-date task
    // (~1383) on entry — it fetches a page and grows it on scroll. `totalItemCount`
    // / `sourceTotals` carry the TRUE uncapped counts so the badge + section
    // pills stay accurate while the rendered list is only a window.
    @State var windowLimit = InboxView.initialWindow
    @State var totalItemCount = 0
    @State var sourceTotals: [String: Int] = [:]
    // `reachedEnd` latches once a grow yields no new rows (the no-date `count()`
    // over-counts archived-project tasks the list post-filter drops, so the
    // window can plateau below `totalItemCount`); `isLoadingMore` debounces the
    // fire-on-appear so a burst of `.onAppear` doesn't stack grows.
    @State var reachedEnd = false
    @State var isLoadingMore = false

    // Multi-select + undo — shared across both platform layouts.
    @State var selection = SelectionModel<UUID>()
    @State var undo = UndoController()

    // Variable-snooze sheet: non-nil while the picker sheet is presented.
    @State var snoozeTarget: InboxItem?

    static let initialWindow = 50
    static let pageGrowth = 100
    // Internal fallback owner for the active filter when the host does not
    // hoist it. macOS hoists it (the §1a control-mode top bar in the Mac
    // shell drives this same state); iOS keeps the internal owner so its
    // in-list filter bar works without any host wiring.
    @State var localActiveFilter: InboxFilter = .all
    let externalActiveFilter: Binding<InboxFilter>?

    var activeFilter: Binding<InboxFilter> {
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
        layout
            // Global ⌘A: publish this Inbox's "select all" into the focused scene
            // so the shell's menu-bar command routes ⌘A here. `selectAll` over the
            // visible (filtered) set, entering selection mode. macOS / iPad mount
            // exactly one list destination at a time; the compact-iPhone TabView
            // keeps tabs mounted, but a hardware-keyboard ⌘A there is the only
            // (benign, unverified) double-publish edge — see PR notes.
            .selectAllCommandTarget(in: selection, ids: filteredItems.map(\.id))
            // Palette "Select All Items" path (the menu-bar ⌘A uses the focused
            // value instead). macOS / iPad mount one list surface at a time.
            .onReceive(NotificationCenter.default.publisher(for: .nexusSelectAllActiveSurface)) { _ in
                selection.enterSelection()
                selection.selectAll(filteredItems.map(\.id))
            }
    }

    @ViewBuilder
    private var layout: some View {
        #if os(macOS)
        macLayout
        #else
        iosLayout
        #endif
    }

    var filteredItems: [InboxItem] {
        activeFilter.wrappedValue.apply(to: items)
    }

    var inboxFilterBar: some View {
        NexusTabBar(items: InboxFilter.tabItems, active: activeFilter)
    }

    var unreadCount: Int {
        // True total minus everything marked read. Mirrors `ContentView`'s
        // closed-Inbox formula exactly so the badge doesn't jump on enter/exit.
        max(0, totalItemCount - readItemIDs.count)
    }

    @MainActor
    func reload(selectFirstItem: Bool) async {
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
            // remount that resets `@State`) and merge any marks made this session.
            readItemIDs = readStateStore.load().union(readItemIDs)
            readStateStore.save(readItemIDs)
            reconcileSelection(selectFirstItem: selectFirstItem)
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

    /// Grow the window by one page when the last row scrolls into view.
    @MainActor
    func loadMore() async {
        guard !reachedEnd, !isLoadingMore else { return }
        guard items.count < totalItemCount else { reachedEnd = true; return }
        isLoadingMore = true
        let before = items.count
        windowLimit += Self.pageGrowth
        await reload(selectFirstItem: false)
        if items.count <= before { reachedEnd = true }
        isLoadingMore = false
    }

    @MainActor
    func reconcileSelection(selectFirstItem: Bool) {
        guard !items.isEmpty else { selectedItem = nil; return }
        if let selectedItem, filteredItems.contains(where: { $0.id == selectedItem.id }) { return }
        if selectFirstItem {
            selectedItem = filteredItems.first
            if let first = selectedItem { markRead(first) }
        }
    }

    @MainActor
    func markRead(_ item: InboxItem) {
        readItemIDs.insert(item.id)
        readStateStore.save(readItemIDs)
    }

    @MainActor
    func markUnread(_ item: InboxItem) {
        readItemIDs.remove(item.id)
        readStateStore.save(readItemIDs)
        onUnreadCountChanged(unreadCount)
    }

    // archive/snooze request `selectFirstItem: true`, but if a concurrent
    // `didSave` reload wins the generation race the stale-return skips
    // `reconcileSelection` and the "auto-select next" UX is silently dropped.
    // This is §5-correct (matches the Today anchor) and benign.
    @MainActor
    func archive(_ item: InboxItem) async {
        try? await registry.archive(item)
        await registry.invalidateCache()
        await reload(selectFirstItem: true)
        onUnreadCountChanged(unreadCount)
    }

    @MainActor
    func delete(_ item: InboxItem) async {
        try? await registry.delete(item)
        await registry.invalidateCache()
        await reload(selectFirstItem: true)
        onUnreadCountChanged(unreadCount)
        undo.show(message: "Deleted \"\(item.title)\"", icon: "trash") {
            Task {
                try? await registry.restore(item)
                await registry.invalidateCache()
                await reload(selectFirstItem: false)
            }
        }
    }

    @MainActor
    func snooze(_ item: InboxItem, hours: Int) async {
        let date = Date().addingTimeInterval(TimeInterval(hours * 60 * 60))
        try? await registry.snooze(item, until: date)
        await registry.invalidateCache()
        await reload(selectFirstItem: true)
        onUnreadCountChanged(unreadCount)
    }

    /// Snooze until tomorrow at 9 AM local time.
    @MainActor
    func snoozeTomorrow(_ item: InboxItem) async {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let nineAM = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        try? await registry.snooze(item, until: nineAM)
        await registry.invalidateCache()
        await reload(selectFirstItem: true)
        onUnreadCountChanged(unreadCount)
    }

    @MainActor
    func markAllRead() async {
        // Windowing means `items` is only a page — mark EVERY inbox id via a full
        // fetch. Rare + user-initiated (off the hot nav path), so the full
        // materialization is fine; falls back to the loaded window if it fails.
        let allIDs = (try? await registry.allItems().map(\.id)) ?? items.map(\.id)
        readItemIDs.formUnion(allIDs)
        readStateStore.save(readItemIDs)
        onUnreadCountChanged(unreadCount)
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
        case .all: return items
        case .people: return items.filter { $0.category == .people }
        case .digests: return items.filter { $0.category == .digests }
        case .mentions: return items.filter { $0.category == .mentions }
        }
    }

    /// Count of items this filter would surface, derived from the SAME
    /// already-loaded set the list renders. No new query — presentation
    /// derivation for the §1a top-bar tab idiom.
    public func count(in items: [InboxItem]) -> Int {
        apply(to: items).count
    }
}
