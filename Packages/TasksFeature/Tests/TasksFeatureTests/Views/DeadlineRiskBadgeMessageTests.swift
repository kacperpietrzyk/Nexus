import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("Deadline-risk inspector badge copy (spec §19.1)")
struct DeadlineRiskBadgeMessageTests {
    private let startBy = Date(timeIntervalSince1970: 1_780_682_400)  // 18:00 UTC

    private func risk(_ severity: DeadlineRiskSeverity, startBy: Date?) -> DeadlineRisk {
        DeadlineRisk(taskID: UUID(), severity: severity, projectedSlackHours: -1, suggestedStartBy: startBy)
    }

    @Test("At-risk with a start time leads with the tier and a HH:mm start")
    func atRiskWithStart() {
        let message = TaskDetailInspector.deadlineRiskRowMessage(risk(.atRisk, startBy: startBy))
        #expect(message.hasPrefix("At risk · start by "))
        #expect(!message.hasSuffix("start by "))  // a concrete time was appended
    }

    @Test("Tight with a start time uses the tight tier label")
    func tightWithStart() {
        let message = TaskDetailInspector.deadlineRiskRowMessage(risk(.tight, startBy: startBy))
        #expect(message.hasPrefix("Tight · start by "))
    }

    @Test("No start time falls back to a tier-specific, non-empty message")
    func fallbackWithoutStart() {
        let atRisk = TaskDetailInspector.deadlineRiskRowMessage(risk(.atRisk, startBy: nil))
        let tight = TaskDetailInspector.deadlineRiskRowMessage(risk(.tight, startBy: nil))
        #expect(atRisk == "At risk · projected to miss the deadline")
        #expect(tight == "Tight · little slack before the deadline")
    }
}
