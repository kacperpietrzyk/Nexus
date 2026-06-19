import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
@Suite struct FeedItemStateRepositoryTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([FeedItemState.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func upsertInsertsThenUpdatesSameRow() throws {
        let repo = FeedItemStateRepository(context: try makeContext())
        let first = try repo.upsert(key: "meeting:a") { $0.seenAt = Date(timeIntervalSince1970: 1) }
        let second = try repo.upsert(key: "meeting:a") { $0.dismissedAt = Date(timeIntervalSince1970: 2) }
        #expect(first.key == second.key)
        let all = try repo.all()
        #expect(all.count == 1)
        #expect(all["meeting:a"]?.seenAt != nil)
        #expect(all["meeting:a"]?.dismissedAt != nil)
    }

    @Test func allCollapsesDuplicateKeysKeepingNewest() throws {
        let context = try makeContext()
        context.insert(FeedItemState(key: "dup", updatedAt: Date(timeIntervalSince1970: 1)))
        context.insert(FeedItemState(key: "dup", seenAt: Date(), updatedAt: Date(timeIntervalSince1970: 9)))
        try context.save()
        let repo = FeedItemStateRepository(context: context)
        let all = try repo.all()
        #expect(all.count == 1)
        #expect(all["dup"]?.seenAt != nil)  // newest updatedAt wins
        // The stale duplicate is purged.
        #expect(try context.fetch(FetchDescriptor<FeedItemState>()).count == 1)
    }
}
