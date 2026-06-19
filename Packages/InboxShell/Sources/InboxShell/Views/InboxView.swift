import NexusUI
import SwiftUI

public struct InboxView: View {
    let registry: FeedRegistry
    let onUnreadCountChanged: @MainActor (Int) -> Void
    let onOpen: @MainActor (FeedItem) -> Void
    let onItemsChanged: @MainActor ([FeedItem]) -> Void
    let markSeen: @MainActor (FeedItem) async -> Void
    let dismissItem: @MainActor (FeedItem) async -> Void
    let snoozeItem: @MainActor (FeedItem, Date) async -> Void

    @State var items: [FeedItem] = []
    @State var error: String?
    @State var selectedItem: FeedItem?
    @State var reloadGeneration = 0
    @State var selection = SelectionModel<String>()
    @State var snoozeTarget: FeedItem?
    @State var localActiveFilter: InboxFilter = .all
    let externalActiveFilter: Binding<InboxFilter>?

    var activeFilter: Binding<InboxFilter> { externalActiveFilter ?? $localActiveFilter }

    public init(
        registry: FeedRegistry = .shared,
        activeFilter: Binding<InboxFilter>? = nil,
        onUnreadCountChanged: @escaping @MainActor (Int) -> Void = { _ in },
        onItemsChanged: @escaping @MainActor ([FeedItem]) -> Void = { _ in },
        onOpen: @escaping @MainActor (FeedItem) -> Void,
        markSeen: @escaping @MainActor (FeedItem) async -> Void = { _ in },
        dismiss: @escaping @MainActor (FeedItem) async -> Void = { _ in },
        snooze: @escaping @MainActor (FeedItem, Date) async -> Void = { _, _ in }
    ) {
        self.registry = registry
        self.externalActiveFilter = activeFilter
        self.onUnreadCountChanged = onUnreadCountChanged
        self.onItemsChanged = onItemsChanged
        self.onOpen = onOpen
        self.markSeen = markSeen
        self.dismissItem = dismiss
        self.snoozeItem = snooze
    }

    public var body: some View {
        layout
            .selectAllCommandTarget(in: selection, ids: filteredItems.map(\.id))
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

    var filteredItems: [FeedItem] { activeFilter.wrappedValue.apply(to: items) }

    var inboxFilterBar: some View {
        NexusTabBar(items: InboxFilter.tabItems, active: activeFilter)
    }

    @MainActor
    func reload(selectFirstItem: Bool) async {
        reloadGeneration += 1
        let generation = reloadGeneration
        do {
            let loaded = try await registry.items(now: Date())
            guard generation == reloadGeneration else { return }
            items = loaded
            error = nil
            reconcileSelection(selectFirstItem: selectFirstItem)
            onItemsChanged(items)
            onUnreadCountChanged(items.filter { $0.stream != .bridge && $0.isUnread(now: Date()) }.count)
        } catch {
            guard generation == reloadGeneration else { return }
            items = []
            selectedItem = nil
            self.error = String(describing: error)
            onItemsChanged(items)
            onUnreadCountChanged(0)
        }
    }

    @MainActor
    func reconcileSelection(selectFirstItem: Bool) {
        guard !filteredItems.isEmpty else { selectedItem = nil; return }
        if let selectedItem, filteredItems.contains(where: { $0.id == selectedItem.id }) { return }
        if selectFirstItem {
            selectedItem = filteredItems.first
            if let first = selectedItem, first.stream != .bridge { Task { await markSeenAndRefresh(first) } }
        }
    }

    @MainActor func open(_ item: FeedItem) {
        onOpen(item)
        if item.stream != .bridge { Task { await markSeenAndRefresh(item) } }
    }

    @MainActor func markSeenAndRefresh(_ item: FeedItem) async {
        await markSeen(item)
        await registry.invalidate()
        await reload(selectFirstItem: false)
    }

    @MainActor func dismiss(_ item: FeedItem) async {
        await dismissItem(item)
        await registry.invalidate()
        await reload(selectFirstItem: true)
    }

    @MainActor func snooze(_ item: FeedItem, until date: Date) async {
        await snoozeItem(item, date)
        await registry.invalidate()
        await reload(selectFirstItem: true)
    }
}

/// Inbox triage filter. Public so the host can hoist the active selection
/// into the control-mode top-bar band. Cases map 1:1 to `FeedStream` plus .all.
public enum InboxFilter: String, Hashable, Sendable, CaseIterable {
    case all
    case agent
    case meeting

    public var displayLabel: String {
        switch self {
        case .all: return "All"
        case .agent: return "Agent"
        case .meeting: return "Meetings"
        }
    }

    public static let tabItems: [NexusTabBarItem<InboxFilter>] = InboxFilter.allCases.map {
        NexusTabBarItem(id: $0, label: $0.displayLabel)
    }

    public func apply(to items: [FeedItem]) -> [FeedItem] {
        switch self {
        case .all: return items
        case .agent: return items.filter { $0.stream == .agent }
        case .meeting: return items.filter { $0.stream == .meeting }
        }
    }

    public func count(in items: [FeedItem]) -> Int { apply(to: items).count }
}
