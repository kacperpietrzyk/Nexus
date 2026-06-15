import SwiftUI
import Testing

@testable import NexusUI

@Suite("LiquidTabBar")
struct LiquidTabBarTests {

    private func bar(active: String) -> LiquidTabBar<String> {
        LiquidTabBar(
            items: [
                .init(id: "open", label: "Open", systemImage: "circle", count: 8),
                .init(id: "done", label: "Done", systemImage: "checkmark.circle", count: 4),
                .init(id: "blocked", label: "Blocked", systemImage: "minus.circle", count: 2),
            ],
            active: .constant(active)
        )
    }

    @Test("isActive maps the active id to exactly one tab")
    func activeMapping() {
        let tabs = bar(active: "done")
        #expect(tabs.isActive("done"))
        #expect(!tabs.isActive("open"))
        #expect(!tabs.isActive("blocked"))
    }

    @Test("Items preserve their order, identity and counts")
    func itemOrder() {
        let tabs = bar(active: "open")
        #expect(tabs.items.map(\.id) == ["open", "done", "blocked"])
        #expect(tabs.items.map(\.label) == ["Open", "Done", "Blocked"])
        #expect(tabs.items.map(\.count) == [8, 4, 2])
    }

    @Test("Item stores optional image and a nil count")
    func itemMetadata() {
        let item = LiquidTabBarItem(id: "open", label: "Open")
        #expect(item.systemImage == nil)
        #expect(item.count == nil)
    }

    @Test("Bound active tab updates flow through isActive")
    func boundActive() {
        var current = "open"
        let binding = Binding(get: { current }, set: { current = $0 })
        let tabs = LiquidTabBar(
            items: [.init(id: "open", label: "Open"), .init(id: "done", label: "Done")],
            active: binding
        )
        #expect(tabs.isActive("open"))
        current = "done"
        #expect(tabs.isActive("done"))
    }
}
