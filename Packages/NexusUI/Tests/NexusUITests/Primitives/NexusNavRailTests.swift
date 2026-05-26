#if !os(watchOS)
import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusNavRail v4")
struct NexusNavRailTests {
    @MainActor
    @Test("Builds with avatar slot + items")
    func buildWithAvatar() {
        struct Stub: View {
            var body: some View { Color.clear }
        }

        let items: [NexusNavRailItem<Int>] = [
            .init(id: 0, systemImage: "circle.dotted", label: "Today"),
            .init(id: 1, systemImage: "tray", label: "Inbox", count: 5),
        ]
        let rail = NexusNavRail(items: items, active: .constant(0)) {
            Stub()
        }

        _ = rail.body
    }

    @MainActor
    @Test("Builds without avatar slot")
    func buildWithoutAvatar() {
        let items: [NexusNavRailItem<String>] = [
            .init(id: "today", systemImage: "circle.dotted", label: "Today")
        ]
        let rail = NexusNavRail(items: items, active: .constant("today"))

        _ = rail.body
    }

    @MainActor
    @Test("LabIconRail metrics (rail 54, icon 34×34)")
    func metrics() {
        #expect(NexusNavRail<Int, EmptyView>.railWidth == 54)
        #expect(NexusNavRail<Int, EmptyView>.logoSize == 32)
        #expect(NexusNavRail<Int, EmptyView>.buttonWidth == 34)
        #expect(NexusNavRail<Int, EmptyView>.buttonHeight == 34)
    }

    @Test("Item preserves id, icon, label, and count")
    func itemProperties() {
        let item = NexusNavRailItem(id: "inbox", systemImage: "tray", label: "Inbox", count: 5)

        #expect(item.id == "inbox")
        #expect(item.systemImage == "tray")
        #expect(item.label == "Inbox")
        #expect(item.count == 5)
    }

    @MainActor
    @Test("bottomItem renders without affecting existing call sites (nil default)")
    func bottomItemIsNilByDefault() {
        let items: [NexusNavRailItem<String>] = [
            .init(id: "today", systemImage: "circle.dotted", label: "Today")
        ]
        // No bottomItem arg — existing call shape byte-preserved; bottomItem is nil.
        let rail = NexusNavRail(items: items, active: .constant("today"))
        #expect(rail.bottomItem == nil)
        _ = rail.body
    }

    @MainActor
    @Test("bottomItem pin slot builds and is not included in items")
    func bottomItemPinSlot() {
        let items: [NexusNavRailItem<String>] = [
            .init(id: "today", systemImage: "circle.dotted", label: "Today"),
            .init(id: "inbox", systemImage: "tray", label: "Inbox"),
        ]
        let settings = NexusNavRailItem(id: "settings", systemImage: "gearshape", label: "Settings")
        let rail = NexusNavRail(items: items, active: .constant("today"), bottomItem: settings)
        // bottomItem is the pinned item, not in the scrolling list.
        #expect(rail.items.count == 2)
        #expect(rail.bottomItem?.id == "settings")
        _ = rail.body
    }
}
#endif
