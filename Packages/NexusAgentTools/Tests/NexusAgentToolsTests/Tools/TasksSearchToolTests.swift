import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@Suite("TasksSearchTool")
struct TasksSearchToolTests {
    @MainActor
    @Test("query matches title and body")
    func queryMatchesTitleAndBody() async throws {
        let tasks = [
            TaskItem(title: "Plan workshop"),
            TaskItem(title: "Send notes", body: "Workshop follow-up"),
            TaskItem(title: "Buy milk"),
        ]
        let fixture = try await InMemoryAgentContext.make(tasks: tasks)

        let response = try await callSearch(
            args: .object(["query": .string("workshop")]),
            context: fixture.context
        )

        #expect(response.count == 2)
        #expect(Set(response.map(\.title)) == ["Plan workshop", "Send notes"])
    }

    @MainActor
    @Test("no match returns empty array")
    func noMatch() async throws {
        let fixture = try await InMemoryAgentContext.make(tasks: [TaskItem(title: "Buy milk")])

        let response = try await callSearch(
            args: .object(["query": .string("workshop")]),
            context: fixture.context
        )

        #expect(response.isEmpty)
    }

    @MainActor
    @Test("limit is respected")
    func limitRespected() async throws {
        let tasks = (0..<5).map { index in
            TaskItem(title: "Workshop task \(index)")
        }
        let fixture = try await InMemoryAgentContext.make(tasks: tasks)

        let response = try await callSearch(
            args: .object([
                "query": .string("workshop"),
                "limit": .int(2),
            ]),
            context: fixture.context
        )

        #expect(response.count == 2)
    }

    @MainActor
    @Test("limit backfills after stale deleted hits")
    func limitBackfillsAfterStaleDeletedHits() async throws {
        let live = TaskItem(title: "Workshop live")
        live.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let staleDeleted = TaskItem(title: "Workshop deleted")
        staleDeleted.updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try await InMemoryAgentContext.make(tasks: [live, staleDeleted])
        staleDeleted.deletedAt = Date(timeIntervalSince1970: 1_900_000_000)
        try fixture.context.modelContext.context.save()

        let response = try await callSearch(
            args: .object([
                "query": .string("workshop"),
                "limit": .int(1),
            ]),
            context: fixture.context
        )

        #expect(response.map(\.title) == ["Workshop live"])
    }

    @MainActor
    @Test("missing query throws validation")
    func missingQueryThrowsValidation() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("Missing required string field: query")) {
            _ = try await TasksSearchTool().call(args: .object([:]), context: fixture.context)
        }
    }

    private func callSearch(args: JSONValue, context: AgentContext) async throws -> [TaskDTO] {
        let result = try await TasksSearchTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode([TaskDTO].self, from: data)
    }
}
