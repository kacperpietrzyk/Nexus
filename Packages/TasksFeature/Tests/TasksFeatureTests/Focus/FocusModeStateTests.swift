import Foundation
import Testing

@testable import TasksFeature

@Suite("FocusModeState")
struct FocusModeStateTests {
    @MainActor
    @Test("toggle enters when candidate is present")
    func toggle_entersWhenCandidatePresent() {
        let state = FocusModeState()
        let candidateID = UUID()
        state.toggle(pickFrom: { candidateID })
        #expect(state.isInFocus)
        #expect(state.pinnedTaskID == candidateID)
    }

    @MainActor
    @Test("toggle increments emptyHintTrigger when no candidate")
    func toggle_emptyTriggersHint() {
        let state = FocusModeState()
        let before = state.emptyHintTrigger
        state.toggle(pickFrom: { nil })
        #expect(!state.isInFocus)
        #expect(state.pinnedTaskID == nil)
        #expect(state.emptyHintTrigger == before + 1)
        state.toggle(pickFrom: { nil })
        #expect(state.emptyHintTrigger == before + 2)
    }

    @MainActor
    @Test("toggle exits when already in focus")
    func toggle_exitsWhenInFocus() {
        let state = FocusModeState()
        state.enter(taskID: UUID())
        #expect(state.isInFocus)
        state.toggle(pickFrom: { UUID() })
        #expect(!state.isInFocus)
        #expect(state.pinnedTaskID == nil)
    }

    @MainActor
    @Test("exit clears pinned task ID")
    func exit_clearsTaskID() {
        let state = FocusModeState()
        state.enter(taskID: UUID())
        state.exit()
        #expect(!state.isInFocus)
        #expect(state.pinnedTaskID == nil)
    }
}
