import Foundation
import Testing

@testable import TasksFeature

@Suite("CycleAssignmentSelection")
struct CycleAssignmentSelectionTests {
    @Test("maps optional cycleID to and from the tagged selection")
    func mapsOptionalCycleID() {
        let id = UUID()
        #expect(CycleAssignmentSelection.from(cycleID: nil) == .none)
        #expect(CycleAssignmentSelection.from(cycleID: id) == .assigned(id))
        #expect(CycleAssignmentSelection.none.cycleID == nil)
        #expect(CycleAssignmentSelection.assigned(id).cycleID == id)
    }
}
