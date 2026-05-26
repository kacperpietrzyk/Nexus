import Foundation
import Testing

@testable import NexusCore

@MainActor
@Test func link_initializesWithExplicitEndpoints() {
    let from = (ItemKind.task, UUID())
    let to = (ItemKind.meeting, UUID())
    let link = Link(from: from, to: to, linkKind: .actionItem)
    #expect(link.fromKind == .task)
    #expect(link.fromID == from.1)
    #expect(link.toKind == .meeting)
    #expect(link.toID == to.1)
    #expect(link.linkKind == .actionItem)
    #expect(link.order == nil)
    #expect(link.createdAt <= .now)
}

@MainActor
@Test func link_orderIsOptionalAndSettable() {
    let link = Link(from: (.task, UUID()), to: (.task, UUID()), linkKind: .child, order: 3)
    #expect(link.order == 3)
}

@MainActor
@Test func link_endpoints_returnTuples() {
    let fromID = UUID()
    let toID = UUID()
    let link = Link(from: (.note, fromID), to: (.task, toID), linkKind: .mentions)
    let from = link.fromEndpoint
    let to = link.toEndpoint
    #expect(from.kind == .note)
    #expect(from.id == fromID)
    #expect(to.kind == .task)
    #expect(to.id == toID)
}

@MainActor
@Test func link_idempotencyKey_isStableForSameEndpoints() {
    let fromID = UUID()
    let toID = UUID()
    let a = Link(from: (.task, fromID), to: (.meeting, toID), linkKind: .source)
    let b = Link(from: (.task, fromID), to: (.meeting, toID), linkKind: .source)
    #expect(a.idempotencyKey == b.idempotencyKey)
    #expect(a.id != b.id)
}
