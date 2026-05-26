import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
struct AgentActivityLogToolTests {
    @Test
    func activityLogReturnsRecentEntriesForThreadRespectingLimitSinceAndSort() async throws {
        let harness = try ActivityLogToolHarness.make()
        let tool = AgentActivityLogTool(context: harness.modelContext)
        let threadID = UUID()
        let otherThreadID = UUID()
        let base = Date(timeIntervalSince1970: 1_777_000_000)

        try harness.insertLog(
            timestamp: base.addingTimeInterval(1),
            threadID: threadID,
            toolName: "old"
        )
        try harness.insertLog(
            timestamp: base.addingTimeInterval(2),
            threadID: threadID,
            toolName: "middle",
            inverseAction: Data(#"{"toolName":"noop","inputJSON":""}"#.utf8)
        )
        try harness.insertLog(
            timestamp: base.addingTimeInterval(3),
            threadID: otherThreadID,
            toolName: "other"
        )
        try harness.insertLog(
            timestamp: base.addingTimeInterval(4),
            threadID: threadID,
            toolName: "newest",
            undoneAt: base.addingTimeInterval(5)
        )

        let output = try await tool.call(
            args: .object([
                "threadID": .string(threadID.uuidString),
                "since": .string(Self.iso8601String(from: base.addingTimeInterval(2))),
                "limit": .int(2),
            ]),
            context: harness.agentContext
        )

        let entries = try #require(output.objectValue?["entries"]?.arrayValue)
        #expect(entries.count == 2)
        let first = try #require(entries[0].objectValue)
        let second = try #require(entries[1].objectValue)
        #expect(first["toolName"] == .string("newest"))
        #expect(second["toolName"] == .string("middle"))
        #expect(first["threadID"] == .string(threadID.uuidString))
        #expect(first["undoneAt"]?.stringValue != nil)
        #expect(first["hasInverse"] == .bool(false))
        #expect(second["hasInverse"] == .bool(true))
        #expect(UUID(uuidString: try #require(first["id"]?.stringValue)) != nil)
    }

    @Test
    func activityLogAcceptsUnixTimestampSince() async throws {
        let harness = try ActivityLogToolHarness.make()
        let tool = AgentActivityLogTool(context: harness.modelContext)
        let threadID = UUID()
        let base = Date(timeIntervalSince1970: 1_777_000_000)

        try harness.insertLog(
            timestamp: base.addingTimeInterval(1),
            threadID: threadID,
            toolName: "old"
        )
        try harness.insertLog(
            timestamp: base.addingTimeInterval(2),
            threadID: threadID,
            toolName: "new"
        )

        let output = try await tool.call(
            args: .object([
                "since": .double(base.addingTimeInterval(1.5).timeIntervalSince1970),
                "limit": .int(50),
            ]),
            context: harness.agentContext
        )

        let entries = try #require(output.objectValue?["entries"]?.arrayValue)
        #expect(entries.map { $0.objectValue?["toolName"] } == [.string("new")])
    }

    @Test
    func activityLogValidatesBadThreadIDAndLimitAndSince() async throws {
        let harness = try ActivityLogToolHarness.make()
        let tool = AgentActivityLogTool(context: harness.modelContext)

        await #expect(throws: AgentError.validation("threadID must be a UUID string")) {
            try await tool.call(
                args: .object(["threadID": .string("bad")]),
                context: harness.agentContext
            )
        }

        await #expect(throws: AgentError.validation("limit must be between 0 and 500")) {
            try await tool.call(
                args: .object(["limit": .int(501)]),
                context: harness.agentContext
            )
        }

        await #expect(throws: AgentError.validation("since must be an ISO8601 string or Unix timestamp")) {
            try await tool.call(
                args: .object(["since": .string("yesterday")]),
                context: harness.agentContext
            )
        }
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

@MainActor
private struct ActivityLogToolHarness {
    let modelContext: ModelContext
    let agentContext: AgentContext

    static func make() throws -> ActivityLogToolHarness {
        let schema = Schema([
            AgentAuditLog.self,
            AgentMemoryEntry.self,
            AgentMessage.self,
            AgentSchedule.self,
            AgentThread.self,
            DebugItem.self,
            ItemEmbedding.self,
            Link.self,
            QuotaLog.self,
            TaskItem.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let modelContext = ModelContext(container)
        let repository = TaskItemRepository(
            context: modelContext,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        return ActivityLogToolHarness(
            modelContext: modelContext,
            agentContext: AgentContext(
                modelContext: ModelContextRef(modelContext),
                taskRepository: TaskItemRepositoryRef(repository),
                searchIndex: SearchIndex(),
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
        )
    }

    func insertLog(
        timestamp: Date,
        threadID: UUID?,
        toolName: String,
        inverseAction: Data? = nil,
        undoneAt: Date? = nil
    ) throws {
        modelContext.insert(
            AgentAuditLog(
                timestamp: timestamp,
                threadID: threadID,
                toolName: toolName,
                inputJSON: Data(#"{}"#.utf8),
                outputJSON: Data(#"{}"#.utf8),
                inverseAction: inverseAction,
                undoneAt: undoneAt
            )
        )
        try modelContext.save()
    }
}
