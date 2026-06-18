import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

// MARK: - decisionsProvider model-state

@Suite("LiquidTodayModel decisions state")
struct LiquidTodayModelDecisionsStateTests {

    @Test("reload() stores decisions returned by the injected decisionsProvider")
    @MainActor
    func decisionsProviderPopulatesState() async throws {
        let container = try ModelContainer(
            for: TaskItem.self, Link.self, Project.self, Note.self, ScheduledBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let now = Date.now
        let model = LiquidTodayModel()

        let rows = [
            LiquidTodayMeetingDecisions(
                meetingID: UUID(),
                meetingTitle: "Sprint Review",
                meetingDate: now,
                decisions: ["Ship feature X", "Defer feature Y"]
            )
        ]
        let expected = LiquidTodayModel.aggregateDecisions(rows, cap: 5)

        await model.reload(
            modelContext: context,
            calendarProvider: MockCalendarEventProvider(status: .denied),
            calendarEventsEnabled: false,
            decisionsProvider: { expected },
            briefProvider: nil,
            now: now
        )

        #expect(model.decisions == expected)
    }

    @Test("reload() with nil decisionsProvider leaves decisions empty")
    @MainActor
    func nilDecisionsProviderLeavesEmpty() async throws {
        let container = try ModelContainer(
            for: TaskItem.self, Link.self, Project.self, Note.self, ScheduledBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let model = LiquidTodayModel()

        await model.reload(
            modelContext: context,
            calendarProvider: MockCalendarEventProvider(status: .denied),
            calendarEventsEnabled: false,
            decisionsProvider: nil,
            briefProvider: nil,
            now: .now
        )

        #expect(model.decisions.isEmpty)
    }
}
