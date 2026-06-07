import Foundation
import Testing

@testable import NexusCore

@Test func scheduledBlock_defaultsToProposedAutoWithNilExternalEvent() {
    let taskID = UUID()
    let start = Date(timeIntervalSince1970: 1_000)
    let end = Date(timeIntervalSince1970: 4_600)
    let block = ScheduledBlock(taskID: taskID, start: start, end: end)

    #expect(block.kind == .scheduledBlock)
    #expect(block.taskID == taskID)
    #expect(block.start == start)
    #expect(block.end == end)
    #expect(block.status == .proposed)
    #expect(block.origin == .auto)
    #expect(block.externalEventID == nil)
    #expect(block.deletedAt == nil)
    #expect(block.title.isEmpty)
}

@Test func scheduledBlock_statusAccessorReflectsRaw() {
    let block = ScheduledBlock(
        taskID: UUID(),
        start: .now,
        end: .now,
        status: .accepted,
        origin: .manual,
        externalEventID: "EV-1"
    )
    #expect(block.status == .accepted)
    #expect(block.statusRaw == "accepted")
    #expect(block.origin == .manual)
    #expect(block.originRaw == "manual")
    #expect(block.externalEventID == "EV-1")
}

@Test func scheduledBlock_statusAccessorFallsBackOnUnknownRaw() {
    let block = ScheduledBlock(taskID: UUID(), start: .now, end: .now)
    block.statusRaw = "garbage"
    block.originRaw = "garbage"
    #expect(block.status == .proposed)
    #expect(block.origin == .auto)
}

@Test func scheduledBlock_conformsToLinkable() {
    let block: any Linkable = ScheduledBlock(taskID: UUID(), start: .now, end: .now)
    #expect(block.kind == .scheduledBlock)
}
