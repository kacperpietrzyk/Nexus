import Foundation
import SwiftData
import Testing

@testable import NexusCore

@MainActor
@Test func debugItem_initializesWithDefaults() {
    let item = DebugItem(title: "Hello")
    #expect(item.title == "Hello")
    #expect(item.kind == .debug)
    #expect(item.deletedAt == nil)
    #expect(item.createdAt <= .now)
    #expect(item.updatedAt == item.createdAt)
}

@MainActor
@Test func debugItem_softDeleteSetsDeletedAt() {
    let item = DebugItem(title: "x")
    #expect(item.deletedAt == nil)
    let stamp = Date()
    item.deletedAt = stamp
    #expect(item.deletedAt == stamp)
}

@MainActor
@Test func debugItem_conformsToLinkable() {
    let item: any Linkable = DebugItem(title: "x")
    #expect(item.kind == .debug)
}
