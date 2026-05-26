import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@MainActor
@Test func conflictLog_init_defaults() {
    let entry = ConflictLog(itemKind: .debug, itemID: UUID(), resolution: .lastWriteWins, summary: "test")
    #expect(entry.resolution == .lastWriteWins)
    #expect(entry.summary == "test")
    #expect(entry.timestamp <= .now)
}

@MainActor
@Test func conflictLog_persists() throws {
    let container = try NexusModelContainer.makeInMemory()
    let context = ModelContext(container)
    let entry = ConflictLog(itemKind: .debug, itemID: UUID(), resolution: .setMerge, summary: "tags merged")
    context.insert(entry)
    try context.save()

    let all = try context.fetch(FetchDescriptor<ConflictLog>())
    #expect(all.count == 1)
    #expect(all.first?.resolution == .setMerge)
}
