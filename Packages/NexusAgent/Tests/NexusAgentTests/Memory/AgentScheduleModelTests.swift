import Foundation
import Testing

@testable import NexusAgent

@Test func scheduleDefaults() {
    let s = AgentSchedule(
        name: "Morning Brief",
        cronExpression: "0 8 * * *",
        prompt: "Zbuduj brief dnia…"
    )
    #expect(s.enabled)
    #expect(s.kind == .builtIn)
    #expect(s.lastRunStatus == .pending)
}
