import Foundation
import Testing

@testable import NexusCore

@Suite("WorkflowState")
struct WorkflowStateTests {
    /// Raw values are CloudKit-bound. Note `canceled` is American (one `l`),
    /// distinct from `ProjectStatus.cancelled` (two `l`s).
    @Test("raw values are stable")
    func rawValues() {
        #expect(WorkflowState.backlog.rawValue == "backlog")
        #expect(WorkflowState.todo.rawValue == "todo")
        #expect(WorkflowState.inProgress.rawValue == "inProgress")
        #expect(WorkflowState.inReview.rawValue == "inReview")
        #expect(WorkflowState.done.rawValue == "done")
        #expect(WorkflowState.canceled.rawValue == "canceled")
        #expect(WorkflowState.duplicate.rawValue == "duplicate")
    }

    @Test("all cases are covered")
    func allCases() {
        #expect(WorkflowState.allCases.count == 7)
    }

    @Test("Codable round-trips")
    func codable() throws {
        for state in WorkflowState.allCases {
            let encoded = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(WorkflowState.self, from: encoded)
            #expect(decoded == state)
        }
    }

    /// Table 5.1: the forced status for every workflow state.
    @Test(
        "forcedStatus follows table 5.1",
        arguments: [
            (WorkflowState.backlog, TaskStatus.open),
            (.todo, .open),
            (.inProgress, .open),
            (.inReview, .open),
            (.done, .done),
            (.canceled, .done),
            (.duplicate, .done),
        ]
    )
    func forcedStatus(state: WorkflowState, expected: TaskStatus) {
        #expect(state.forcedStatus == expected)
    }

    @Test(
        "only canceled/duplicate are terminal non-completions",
        arguments: [
            (WorkflowState.backlog, false),
            (.todo, false),
            (.inProgress, false),
            (.inReview, false),
            (.done, false),
            (.canceled, true),
            (.duplicate, true),
        ]
    )
    func terminalNonCompletion(state: WorkflowState, expected: Bool) {
        #expect(state.isTerminalNonCompletion == expected)
    }
}
