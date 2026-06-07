import Foundation
import Testing

@testable import NexusCore

@Test func taskItem_durationDefaultsToNil() {
    let task = TaskItem(title: "Write report")
    #expect(task.estimatedDurationSeconds == nil)
    #expect(task.durationSourceRaw == nil)
    #expect(task.durationSource == nil)
}

@Test func taskItem_durationSourceAccessorReflectsRaw() {
    let task = TaskItem(
        title: "Write report",
        estimatedDurationSeconds: 3_600,
        durationSource: .explicit
    )
    #expect(task.estimatedDurationSeconds == 3_600)
    #expect(task.durationSourceRaw == "explicit")
    #expect(task.durationSource == .explicit)
}

@Test func taskItem_durationSourceAccessorFallsBackOnUnknownRaw() {
    let task = TaskItem(title: "Write report")
    task.durationSourceRaw = "garbage"
    #expect(task.durationSource == nil)
}

@Test func taskItem_estimatedSourceRoundTrips() {
    let task = TaskItem(
        title: "Quick call",
        estimatedDurationSeconds: 1_800,
        durationSource: .estimated
    )
    #expect(task.durationSource == .estimated)
    #expect(task.durationSourceRaw == "estimated")
}
