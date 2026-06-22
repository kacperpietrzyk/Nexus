import Foundation
import Testing

@testable import NexusMeetings

private func makeMeeting(id: UUID = UUID(), title: String) -> Meeting {
    Meeting(
        id: id,
        title: title,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        detectionSource: .manual
    )
}

@Test func meetingDedupedByID_keepsFirstOccurrencePerID_preservingOrder() {
    let a = makeMeeting(title: "A")
    let aGhost = makeMeeting(id: a.id, title: "A (stale-entity clone)")
    let b = makeMeeting(title: "B")
    let bGhost = makeMeeting(id: b.id, title: "B (stale-entity clone)")

    let deduped = [a, aGhost, b, bGhost].dedupedByID()

    #expect(deduped.count == 2)
    #expect(deduped.map(\.id) == [a.id, b.id])
    // First occurrence wins — the originals, not the clones.
    #expect(deduped.map(\.title) == ["A", "B"])
}

@Test func meetingDedupedByID_isNoOpOnCleanList() {
    let meetings = [
        makeMeeting(title: "A"),
        makeMeeting(title: "B"),
        makeMeeting(title: "C"),
    ]
    let deduped = meetings.dedupedByID()
    #expect(deduped.map(\.id) == meetings.map(\.id))
}

@Test func meetingDedupedByID_emptyStaysEmpty() {
    #expect([Meeting]().dedupedByID().isEmpty)
}
