import Foundation
import Testing

@testable import NexusCore

@Test func linkDedupedByID_keepsFirstOccurrencePerID_preservingOrder() {
    let a = Link(from: (.note, UUID()), to: (.task, UUID()), linkKind: .mentions)
    let aDuplicate = Link(from: (.note, a.fromID), to: (.task, a.toID), linkKind: .mentions)
    // Make aDuplicate share the same id as `a` (CloudKit ghost row scenario).
    let aGhost = makeLink(id: a.id, from: (.note, a.fromID), to: (.task, a.toID), linkKind: .mentions)
    let b = Link(from: (.meeting, UUID()), to: (.note, UUID()), linkKind: .actionItem)
    let bGhost = makeLink(id: b.id, from: (.meeting, b.fromID), to: (.note, b.toID), linkKind: .actionItem)

    let deduped = [a, aGhost, b, bGhost].dedupedByID()

    #expect(deduped.count == 2)
    #expect(deduped.map(\.id) == [a.id, b.id])
}

@Test func linkDedupedByID_isNoOpOnCleanList() {
    let links = [
        Link(from: (.note, UUID()), to: (.task, UUID()), linkKind: .mentions),
        Link(from: (.meeting, UUID()), to: (.note, UUID()), linkKind: .actionItem),
        Link(from: (.task, UUID()), to: (.person, UUID()), linkKind: .mentions),
    ]
    let deduped = links.dedupedByID()
    #expect(deduped.map(\.id) == links.map(\.id))
}

@Test func linkDedupedByID_emptyStaysEmpty() {
    #expect([Link]().dedupedByID().isEmpty)
}

@Test func linkDedupedByID_preservesOrderFirstOccurrenceWins() {
    // Three links; second and third are duplicates of the first two respectively.
    let a = Link(from: (.note, UUID()), to: (.task, UUID()), linkKind: .mentions)
    let b = Link(from: (.note, UUID()), to: (.task, UUID()), linkKind: .mentions)
    let aGhost = makeLink(id: a.id, from: (.note, a.fromID), to: (.task, a.toID), linkKind: .mentions)
    let bGhost = makeLink(id: b.id, from: (.note, b.fromID), to: (.task, b.toID), linkKind: .mentions)

    // Input order: a, b, a-ghost, b-ghost
    let deduped = [a, b, aGhost, bGhost].dedupedByID()

    #expect(deduped.count == 2)
    // Original order preserved: a first, then b.
    #expect(deduped[0].id == a.id)
    #expect(deduped[1].id == b.id)
}

// MARK: - Helpers

/// Build a `Link` with a pre-set `id` to simulate a CloudKit ghost-row duplicate.
private func makeLink(id: UUID, from: (ItemKind, UUID), to: (ItemKind, UUID), linkKind: LinkKind) -> Link {
    let link = Link(from: from, to: to, linkKind: linkKind)
    link.id = id
    return link
}
