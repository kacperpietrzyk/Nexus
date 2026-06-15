import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@Suite("TasksSearchTool")
struct TasksSearchToolTests {
    @MainActor
    @Test("query matches title and tags")
    func queryMatchesTitleAndTags() async throws {
        // Task content (body) is no longer indexed — it lives in a `Note`
        // (spec §4.2/§13). Search now spans title + tags only: one task matches by
        // title, another by tag.
        let tasks = [
            TaskItem(title: "Plan workshop"),
            TaskItem(title: "Send notes", tags: ["workshop"]),
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

    @MainActor
    @Test("search excludes templates by default and includes them on request")
    func searchTemplateExclusion() async throws {
        let live = TaskItem(title: "Quarterly report")
        let template = TaskItem(title: "Quarterly report template", isTemplate: true)
        let fixture = try await InMemoryAgentContext.make(tasks: [live, template])

        let defaultResult = try await callSearch(
            args: .object(["query": .string("Quarterly")]),
            context: fixture.context
        )
        #expect(defaultResult.map(\.title) == ["Quarterly report"])

        let optIn = try await callSearch(
            args: .object(["query": .string("Quarterly"), "include_templates": .bool(true)]),
            context: fixture.context
        )
        #expect(Set(optIn.map(\.title)) == ["Quarterly report", "Quarterly report template"])
    }

    private func callSearch(args: JSONValue, context: AgentContext) async throws -> [TaskDTO] {
        let result = try await TasksSearchTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode([TaskDTO].self, from: data)
    }
}
