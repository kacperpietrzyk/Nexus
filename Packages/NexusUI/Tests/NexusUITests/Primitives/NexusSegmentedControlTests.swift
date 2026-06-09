import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusSegmentedControl")
struct NexusSegmentedControlTests {

    private func control(selection: String) -> NexusSegmentedControl<String> {
        NexusSegmentedControl(
            items: [
                .init(id: "day", label: "Day"),
                .init(id: "week", label: "Week"),
                .init(id: "month", label: "Month"),
            ],
            selection: .constant(selection)
        )
    }

    @Test("isSelected maps the active id to exactly one segment")
    func selectionMapping() {
        let bar = control(selection: "week")
        #expect(bar.isSelected("week"))
        #expect(!bar.isSelected("day"))
        #expect(!bar.isSelected("month"))
    }

    @Test("Items preserve their order and identity")
    func itemOrder() {
        let bar = control(selection: "day")
        #expect(bar.items.map(\.id) == ["day", "week", "month"])
        #expect(bar.items.map(\.label) == ["Day", "Week", "Month"])
    }

    @Test("Segment height matches the compact control vocabulary")
    func segmentHeight() {
        #expect(NexusSegmentedControl<String>.segmentHeight == 26)
    }
}
