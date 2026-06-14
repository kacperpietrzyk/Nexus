import Foundation
import NexusCore
import Testing
@testable import TasksFeature

@Suite("ProjectExecutionModel type stats")
struct ProjectExecutionModelTypeStatsTests {
    @Test("daysRemaining counts whole calendar days, clamping past to negative")
    func daysRemaining() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let in3 = now.addingTimeInterval(3 * 86_400)
        #expect(ProjectExecutionModel.daysRemaining(to: in3, from: now) == 3)
        let ago2 = now.addingTimeInterval(-2 * 86_400)
        #expect(ProjectExecutionModel.daysRemaining(to: ago2, from: now) == -2)
    }

    @Test("kpiLabels picks type-appropriate base tiles")
    func kpiLabels() {
        #expect(ProjectExecutionModel.kpiLabels(for: .sales) == ["Open", "Done"])
        #expect(ProjectExecutionModel.kpiLabels(for: .implementation) == ["Open", "Done", "Overdue"])
        #expect(ProjectExecutionModel.kpiLabels(for: .generic) == ["Open", "Done", "Overdue"])
    }
}
