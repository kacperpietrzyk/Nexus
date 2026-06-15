import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusMeetings

@MainActor
struct MeetingsWriteToolsTests {
    @Test("create persists a meeting with title and start")
    func creates() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let args = JSONValue.object([
            "title": .string("Kickoff"),
            "started_at": .string("2026-06-15T09:00:00.000Z"),
            "summary": .string("Project kickoff notes."),
        ])
        let result = try await MeetingsCreateTool(repository: repo)
            .call(args: args, context: agentContext(modelContext: context))
        let id = try #require(result["id"]?.stringValue.flatMap(UUID.init(uuidString:)))
        let stored = try #require(try repo.find(id: id))
        #expect(stored.title == "Kickoff")
        #expect(stored.summaryText == "Project kickoff notes.")
        #expect(stored.detectionSource == MeetingDetectionSource.manual.rawValue)
    }

    @Test("create computes duration from ended_at")
    func createsWithEnd() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let args = JSONValue.object([
            "title": .string("Standup"),
            "started_at": .string("2026-06-15T09:00:00.000Z"),
            "ended_at": .string("2026-06-15T09:30:00.000Z"),
        ])
        let result = try await MeetingsCreateTool(repository: repo)
            .call(args: args, context: agentContext(modelContext: context))
        let id = try #require(result["id"]?.stringValue.flatMap(UUID.init(uuidString:)))
        let stored = try #require(try repo.find(id: id))
        #expect(stored.durationSec == 1800)
    }

    @Test("create rejects ended_at before started_at")
    func createRejectsEndedBeforeStarted() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let args = JSONValue.object([
            "title": .string("Backwards"),
            "started_at": .string("2026-06-15T09:00:00.000Z"),
            "ended_at": .string("2026-06-15T08:30:00.000Z"),
        ])
        await #expect(throws: AgentError.self) {
            _ = try await MeetingsCreateTool(repository: repo)
                .call(args: args, context: agentContext(modelContext: context))
        }
        // Nothing was persisted (no negative-duration row).
        #expect(try repo.recent(limit: 10).isEmpty)
    }

    @Test("update rejects ended_at before started_at")
    func updateRejectsEndedBeforeStarted() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let start = MeetingsToolFormatters.date(from: "2026-06-15T09:00:00.000Z")!
        let m = MeetingsTestSupport.meeting(title: "Keep", startedAt: start)
        try repo.insert(m)
        let args = JSONValue.object([
            "meeting_id": .string(m.id.uuidString),
            "ended_at": .string("2026-06-15T08:30:00.000Z"),
        ])
        await #expect(throws: AgentError.self) {
            _ = try await MeetingsUpdateTool(repository: repo)
                .call(args: args, context: agentContext(modelContext: context))
        }
        let stored = try #require(try repo.find(id: m.id))
        #expect(stored.durationSec >= 0)
    }

    @Test("update patches the title only")
    func updates() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let m = MeetingsTestSupport.meeting(title: "Old", summary: "Keep me")
        try repo.insert(m)
        let args = JSONValue.object(["meeting_id": .string(m.id.uuidString), "title": .string("New")])
        _ = try await MeetingsUpdateTool(repository: repo)
            .call(args: args, context: agentContext(modelContext: context))
        let stored = try #require(try repo.find(id: m.id))
        #expect(stored.title == "New")
        #expect(stored.summaryText == "Keep me")
    }

    @Test("update rejects a blank title")
    func updateRejectsBlankTitle() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let m = MeetingsTestSupport.meeting(title: "Keep", summary: "Keep me")
        try repo.insert(m)
        let args = JSONValue.object(["meeting_id": .string(m.id.uuidString), "title": .string("   ")])
        await #expect(throws: AgentError.self) {
            _ = try await MeetingsUpdateTool(repository: repo)
                .call(args: args, context: agentContext(modelContext: context))
        }
        let stored = try #require(try repo.find(id: m.id))
        #expect(stored.title == "Keep")
    }

    @Test("update of a missing meeting throws notFound")
    func updateMissingThrows() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let args = JSONValue.object([
            "meeting_id": .string(UUID().uuidString),
            "title": .string("Nope"),
        ])
        await #expect(throws: AgentError.self) {
            _ = try await MeetingsUpdateTool(repository: repo)
                .call(args: args, context: agentContext(modelContext: context))
        }
    }

    @Test("delete removes the meeting from normal lookups")
    func deletes() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let m = MeetingsTestSupport.meeting(title: "Bye")
        try repo.insert(m)
        let args = JSONValue.object(["meeting_id": .string(m.id.uuidString)])
        _ = try await MeetingsDeleteTool(repository: repo)
            .call(args: args, context: agentContext(modelContext: context))
        // delete(id:) hard-deletes via context.delete, so find returns nil.
        let after = try repo.find(id: m.id)
        #expect(after == nil || after?.deletedAt != nil)
    }
}

@MainActor
private func agentContext(modelContext: ModelContext) -> AgentContext {
    let taskRepository = TaskItemRepository(context: modelContext, scheduler: RRuleScheduler(), now: { .now })
    return AgentContext(
        modelContext: ModelContextRef(modelContext),
        taskRepository: TaskItemRepositoryRef(taskRepository),
        searchIndex: SearchIndex(),
        now: { .now }
    )
}
