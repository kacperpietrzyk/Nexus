import Testing

@testable import NexusUI

@MainActor
@Suite struct SelectionModelTests {
    @Test func startsEmptyAndNotSelecting() {
        let model = SelectionModel<Int>()
        #expect(model.selectedIDs.isEmpty)
        #expect(model.isSelecting == false)
        #expect(model.hasSelection == false)
        #expect(model.selectedIDs.isEmpty)
    }

    @Test func toggleAddsThenRemoves() {
        let model = SelectionModel<Int>()
        model.toggle(id: 1)
        #expect(model.isSelected(id: 1))
        #expect(model.count == 1)
        model.toggle(id: 1)
        #expect(model.isSelected(id: 1) == false)
        #expect(model.selectedIDs.isEmpty)
    }

    @Test func enterAndExitSelection() {
        let model = SelectionModel<Int>()
        model.enterSelection()
        #expect(model.isSelecting)
        model.toggle(id: 7)
        #expect(model.hasSelection)
        model.exitSelection()
        #expect(model.isSelecting == false)
        #expect(model.selectedIDs.isEmpty)
        #expect(model.hasSelection == false)
    }

    @Test func selectAllUnionsIDs() {
        let model = SelectionModel<Int>()
        model.toggle(id: 1)
        model.selectAll([1, 2, 3])
        #expect(model.selectedIDs == [1, 2, 3])
    }

    @Test func clearKeepsSelectionMode() {
        let model = SelectionModel<String>()
        model.enterSelection()
        model.selectAll(["a", "b"])
        model.clear()
        #expect(model.selectedIDs.isEmpty)
        #expect(model.isSelecting)  // clear does NOT exit selection mode
    }

    @Test func hasSelectionRequiresBothModeAndNonEmpty() {
        let model = SelectionModel<Int>()
        model.toggle(id: 1)  // selected but not in selection mode yet
        #expect(model.hasSelection == false)
        model.enterSelection()
        #expect(model.hasSelection)
    }
}
