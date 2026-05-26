import Foundation
import Testing

@testable import NexusAgent

@Suite
struct AgentMemoryStoreTests {
    @Test func memoryStoreUpsert() throws {
        let store = AgentMemoryStore(context: try AgentTestSupport.makeContext())
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let updatedAt = createdAt.addingTimeInterval(60)

        let firstID = try store.upsert(
            scope: "global",
            key: "prefers-pl",
            content: "v1",
            now: createdAt
        )
        let secondID = try store.upsert(
            scope: "global",
            key: "prefers-pl",
            content: "v2",
            now: updatedAt
        )
        let entry = try #require(try store.find(scope: "global", key: "prefers-pl"))

        #expect(secondID == firstID)
        #expect(entry.id == firstID)
        #expect(entry.content == "v2")
        #expect(entry.createdAt == createdAt)
        #expect(entry.updatedAt == updatedAt)
    }

    @Test func memoryStoreScopeFilter() throws {
        let store = AgentMemoryStore(context: try AgentTestSupport.makeContext())

        _ = try store.upsert(scope: "global", key: "a", content: "1")
        _ = try store.upsert(scope: "project:abc", key: "b", content: "2")

        #expect(try store.list(scope: "global").count == 1)
        #expect(try store.list(scope: "project:abc").count == 1)
    }

    @Test func memoryStoreScopeFilterSupportsCategoryPrefixes() throws {
        let store = AgentMemoryStore(context: try AgentTestSupport.makeContext())
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        _ = try store.upsert(scope: "global", key: "a", content: "1", now: now)
        _ = try store.upsert(scope: "project:x", key: "b", content: "2", now: now.addingTimeInterval(60))
        _ = try store.upsert(scope: "project:y", key: "c", content: "3", now: now.addingTimeInterval(120))
        _ = try store.upsert(scope: "tag:y", key: "d", content: "4", now: now.addingTimeInterval(180))

        #expect(try store.list(matching: .global).map(\.key) == ["a"])
        #expect(try store.list(matching: .project).map(\.key) == ["c", "b"])
        #expect(try store.list(matching: .tag).map(\.key) == ["d"])
    }

    @Test func memoryStoreSoftDeleteMarksEntryAndHidesFromLists() throws {
        let ctx = try AgentTestSupport.makeContext()
        let store = AgentMemoryStore(context: ctx)
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_500)
        let id = try store.upsert(scope: "global", key: "a", content: "1")

        try store.softDelete(id: id, now: deletedAt)

        let entry = try #require(try store.find(id: id, includeDeleted: true))
        #expect(entry.deletedAt == deletedAt)
        #expect(entry.updatedAt == deletedAt)
        #expect(try store.list(scope: "global").isEmpty)
        #expect(try store.list(matching: .global).isEmpty)
    }

    @Test func memoryStoreRecentRejectsNonPositiveLimits() throws {
        let store = AgentMemoryStore(context: try AgentTestSupport.makeContext())

        _ = try store.upsert(scope: "global", key: "a", content: "1")

        #expect(try store.recent(scope: "global", limit: 0).isEmpty)
        #expect(try store.recent(scope: "global", limit: -1).isEmpty)
    }
}
