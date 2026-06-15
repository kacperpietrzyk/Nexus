import NexusCore
import Testing

@testable import NexusAgentTools

/// T1: the MCP/agent write path must accept completion-anchored RRULEs.
/// Validation flows through `RRuleParser.parse`, which understands `ANCHOR=`
/// since the core change — this locks the acceptance end-to-end.
@Suite("Task tools accept ANCHOR=COMPLETION")
struct TasksRecurrenceAnchorValidationTests {
    @Test("optionalRecurrenceRule passes an anchored rule through verbatim")
    func acceptsCompletionAnchoredRule() throws {
        let rule = try TasksStructuredCreateArguments.optionalRecurrenceRule(
            .string("FREQ=DAILY;ANCHOR=COMPLETION"))
        #expect(rule == "FREQ=DAILY;ANCHOR=COMPLETION")
    }

    @Test("optionalRecurrenceRule still rejects a malformed anchored rule")
    func rejectsInvalidAnchoredRule() {
        #expect(throws: (any Error).self) {
            _ = try TasksStructuredCreateArguments.optionalRecurrenceRule(
                .string("FREQ=DAILY;ANCHOR=WHENEVER"))
        }
    }
}
