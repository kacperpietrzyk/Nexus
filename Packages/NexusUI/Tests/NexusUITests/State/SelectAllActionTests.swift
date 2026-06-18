import Testing

@testable import NexusUI

@MainActor
@Suite struct SelectAllActionTests {
    @Test func performEntersSelectionAndSelectsIDs() {
        let model = SelectionModel<Int>()
        let action = SelectAllAction(identity: ObjectIdentifier(model)) {
            model.enterSelection()
            model.selectAll([1, 2, 3])
        }

        #expect(model.isSelecting == false)
        action()
        #expect(model.isSelecting)
        #expect(model.selectedIDs == [1, 2, 3])
    }

    @Test func sameIdentityComparesEqual() {
        let model = SelectionModel<Int>()
        let identity = ObjectIdentifier(model)
        let lhs = SelectAllAction(identity: identity) {}
        let rhs = SelectAllAction(identity: identity) {}
        // Closures aren't Equatable; identity drives focused-value diffing so the
        // same surface re-publishing each render does not thrash the menu state.
        #expect(lhs == rhs)
    }

    @Test func differentIdentityComparesUnequal() {
        let modelA = SelectionModel<Int>()
        let modelB = SelectionModel<Int>()
        let lhs = SelectAllAction(identity: ObjectIdentifier(modelA)) {}
        let rhs = SelectAllAction(identity: ObjectIdentifier(modelB)) {}
        #expect(lhs != rhs)
    }
}
