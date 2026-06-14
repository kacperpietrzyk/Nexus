import Testing
@testable import NexusCore

@Suite("ProjectStage")
struct ProjectStageTests {
    @Test("each type's stage preset is non-empty except generic")
    func presets() {
        #expect(ProjectType.implementation.stages.first == .kickoff)
        #expect(ProjectType.implementation.stages.last == .closed)
        #expect(ProjectType.sales.stages == [.lead, .qualifying, .proposal, .tender, .won, .lost])
        #expect(ProjectType.audit.stages == [.auditPlan, .auditExecution, .auditReport])
        #expect(ProjectType.internalDev.stages == [.planning, .building, .reviewing, .shipped])
        #expect(ProjectType.generic.stages.isEmpty)
    }

    @Test("every type's terminal stage maps to a completed-ish coarse status")
    func terminalSymmetry() {
        #expect(ProjectStage.closed.coarseStatus == .completed)
        #expect(ProjectStage.won.coarseStatus == .completed)
        #expect(ProjectStage.lost.coarseStatus == .cancelled)
        #expect(ProjectStage.auditReport.coarseStatus == .completed)
        #expect(ProjectStage.shipped.coarseStatus == .completed)
    }

    @Test("early stages map to planned/active")
    func earlyStages() {
        #expect(ProjectStage.lead.coarseStatus == .planned)
        #expect(ProjectStage.kickoff.coarseStatus == .active)
        #expect(ProjectStage.installation.coarseStatus == .active)
    }

    @Test("raw values round-trip")
    func rawRoundTrip() {
        for stage in ProjectStage.allCases {
            #expect(ProjectStage(rawValue: stage.rawValue) == stage)
        }
    }
}
