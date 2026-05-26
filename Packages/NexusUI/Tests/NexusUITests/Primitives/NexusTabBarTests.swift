#if !os(watchOS)
import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusTabBar v4")
struct NexusTabBarTests {
    @MainActor
    @Test("Builds with items")
    func build() {
        let items: [NexusTabBarItem<String>] = [
            .init(id: "all", label: "All"),
            .init(id: "open", label: "Open", count: 3),
        ]
        let tabBar = NexusTabBar(items: items, active: .constant("all"))

        _ = tabBar.body
    }

    @MainActor
    @Test("Canvas metrics stay fixed")
    func metrics() {
        #expect(NexusTabBar<String>.itemHeight == 26)
        #expect(NexusTabBar<String>.horizontalPadding == 12)
    }

    @Test("Item preserves id, label, icon, and count")
    func itemProperties() {
        let item = NexusTabBarItem(id: "today", label: "Today", systemImage: "sun.max", count: 7)

        #expect(item.id == "today")
        #expect(item.label == "Today")
        #expect(item.systemImage == "sun.max")
        #expect(item.count == 7)
    }
}
#endif
