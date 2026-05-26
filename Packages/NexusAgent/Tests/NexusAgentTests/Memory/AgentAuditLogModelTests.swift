import Foundation
import Testing

@testable import NexusAgent

@Test func auditLogDefaults() {
    let log = AgentAuditLog(
        toolName: "tasks.snooze",
        inputJSON: Data(),
        outputJSON: Data()
    )
    #expect(log.toolName == "tasks.snooze")
    #expect(log.affectedItemIDs.isEmpty)
    #expect(log.inverseAction == nil)
    #expect(log.undoneAt == nil)
}
