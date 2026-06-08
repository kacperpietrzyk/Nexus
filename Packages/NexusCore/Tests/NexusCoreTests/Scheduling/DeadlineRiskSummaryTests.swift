import Foundation
import Testing

@testable import NexusCore

@Suite("DeadlineRiskSummary")
struct DeadlineRiskSummaryTests {
    private func risk(
        _ severity: DeadlineRiskSeverity,
        slack: Double,
        id: UUID = UUID()
    ) -> DeadlineRisk {
        DeadlineRisk(taskID: id, severity: severity, projectedSlackHours: slack, suggestedStartBy: nil)
    }

    @Test("Drops on-track entries and reports no pressure when all clear")
    func noPressure() {
        let summary = DeadlineRiskSummary.make(from: [
            risk(.onTrack, slack: 5),
            risk(.onTrack, slack: 12),
        ])
        #expect(!summary.hasPressure)
        #expect(summary.mostUrgent == nil)
        #expect(summary.atRiskCount == 0)
        #expect(summary.tightCount == 0)
    }

    @Test("Partitions at-risk vs tight and picks the lowest-slack as most urgent")
    func partitionsAndPicksUrgent() {
        let atRisk = risk(.atRisk, slack: -3)
        let tight = risk(.tight, slack: 1.5)
        let onTrack = risk(.onTrack, slack: 8)

        let summary = DeadlineRiskSummary.make(from: [tight, onTrack, atRisk])

        #expect(summary.hasPressure)
        #expect(summary.atRiskTaskIDs == [atRisk.taskID])
        #expect(summary.tightTaskIDs == [tight.taskID])
        // -3 < 1.5 → the at-risk task is the most urgent.
        #expect(summary.mostUrgent?.taskID == atRisk.taskID)
    }

    @Test("Orders each tier by ascending slack, tie-broken by id (deterministic)")
    func deterministicOrder() {
        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!
        let a = risk(.atRisk, slack: -1, id: highID)
        let b = risk(.atRisk, slack: -1, id: lowID)
        let c = risk(.atRisk, slack: -5, id: UUID())

        let summary = DeadlineRiskSummary.make(from: [a, b, c])

        // -5 first; then the two -1 entries tie-broken by id ascending.
        #expect(summary.atRiskTaskIDs == [c.taskID, lowID, highID])
        #expect(summary.mostUrgent?.taskID == c.taskID)
    }
}
