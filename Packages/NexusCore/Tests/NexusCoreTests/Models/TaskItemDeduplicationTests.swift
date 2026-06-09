import Foundation
import Testing

@testable import NexusCore

@Test func dedupedByID_keepsFirstOccurrencePerID_preservingOrder() {
    let a = TaskItem(title: "A")
    let aDuplicate = TaskItem(id: a.id, title: "A (stale-entity clone)")
    let b = TaskItem(title: "B")
    let bDuplicate = TaskItem(id: b.id, title: "B (stale-entity clone)")

    let deduped = [a, aDuplicate, b, bDuplicate].dedupedByID()

    #expect(deduped.count == 2)
    #expect(deduped.map(\.id) == [a.id, b.id])
    // First occurrence wins — the originals, not the clones.
    #expect(deduped.map(\.title) == ["A", "B"])
}

@Test func dedupedByID_isNoOpOnCleanList() {
    let tasks = [TaskItem(title: "A"), TaskItem(title: "B"), TaskItem(title: "C")]
    let deduped = tasks.dedupedByID()
    #expect(deduped.map(\.id) == tasks.map(\.id))
}

@Test func dedupedByID_emptyStaysEmpty() {
    #expect([TaskItem]().dedupedByID().isEmpty)
}
