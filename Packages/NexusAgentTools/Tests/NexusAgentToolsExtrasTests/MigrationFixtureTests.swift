import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools
@testable import NexusAgentToolsExtras

@Suite("Migration fixture round-trip", .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION"] == "1"))
struct MigrationFixtureTests {
    @MainActor
    @Test("imports 50 todoist tasks without duplicates on re-run")
    func todoistFixture() async throws {
        let entries = try Self.loadFixture()
        let setup = try await InMemoryAgentContextWithExtras.make()
        let tool = TasksCreateIdempotentTool()

        for entry in entries {
            _ = try await tool.call(args: entry.createArguments(), context: setup.context)
        }

        let allFirst = try setup.context.modelContext.context.fetch(FetchDescriptor<TaskItem>())
        let firstCount = allFirst.count
        #expect(firstCount == entries.count)

        for entry in entries {
            _ = try await tool.call(args: entry.rerunArguments(), context: setup.context)
        }

        let allSecond = try setup.context.modelContext.context.fetch(FetchDescriptor<TaskItem>())
        #expect(allSecond.count == firstCount, "re-run created duplicates")
    }

    private static func loadFixture() throws -> [TodoistFixtureEntry] {
        let url = try #require(Bundle.module.url(forResource: "todoist-sample", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let entries = try JSONDecoder().decode([TodoistFixtureEntry].self, from: data)
        #expect(entries.count == 50)
        return entries
    }
}

private struct TodoistFixtureEntry: Decodable {
    let id: String
    let content: String
    let dueDate: String?
    let priority: Int
    let labels: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case content
        case dueDate = "due_date"
        case priority
        case labels
    }

    func createArguments() -> JSONValue {
        var args: [String: JSONValue] = [
            "external_source_id": .string("todoist:\(id)"),
            "title": .string(content),
            "priority": .int(priority),
            "tags": .array(labels.map { .string($0) }),
        ]
        if let dueDate {
            args["due_date"] = .string(dueDate)
        }
        return .object(args)
    }

    func rerunArguments() -> JSONValue {
        .object([
            "external_source_id": .string("todoist:\(id)"),
            "title": .string(content),
        ])
    }
}
