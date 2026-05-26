import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentToolsExtras

@Suite("TasksCreateFromTextTool")
struct TasksCreateFromTextToolTests {
    @MainActor
    @Test("creates task with parsed English title")
    func english() async throws {
        let fixture = try await InMemoryAgentContextWithExtras.make()

        let dto = try await callCreateFromText(
            args: .object([
                "text": .string("Buy milk tomorrow at 5pm"),
                "locale": .string("en"),
            ]),
            context: fixture.context
        )

        let rows = try fixture.repo.context.fetch(FetchDescriptor<TaskItem>())
        #expect(dto.title.lowercased().contains("milk"))
        #expect(dto.dueDate != nil)
        #expect(rows.count == 1)
    }

    @MainActor
    @Test("creates task with parsed Polish title")
    func polish() async throws {
        let fixture = try await InMemoryAgentContextWithExtras.make()

        let dto = try await callCreateFromText(
            args: .object([
                "text": .string("kup mleko jutro o 17"),
                "locale": .string("pl"),
            ]),
            context: fixture.context
        )

        #expect(dto.title.lowercased().contains("mleko"))
        #expect(dto.dueDate != nil)
    }

    @MainActor
    @Test("persists parsed deadline")
    func persistsDeadline() async throws {
        let fixture = try await InMemoryAgentContextWithExtras.make()

        let raw = try await TasksCreateFromTextTool().call(
            args: .object([
                "text": .string("Submit report deadline tomorrow"),
                "locale": .string("en"),
            ]),
            context: fixture.context
        )
        let dtoData = try JSONEncoder().encode(raw)
        let dto = try JSONDecoder().decode(TaskDTO.self, from: dtoData)

        let rows = try fixture.repo.context.fetch(FetchDescriptor<TaskItem>())
        let rawDeadline = try #require(raw["deadline_date"]?.stringValue)
        let dtoDeadline = try #require(dto.deadlineDate)
        #expect(isDateOnly(rawDeadline))
        #expect(isDateOnly(dtoDeadline))
        #expect(rows.count == 1)
        #expect(rows.first?.title == "Submit report")
        #expect(rows.first?.dueAt == nil)
        #expect(rows.first?.deadlineAt != nil)
    }

    @MainActor
    @Test("created task is searchable immediately")
    func updatesSearchIndex() async throws {
        let fixture = try await InMemoryAgentContextWithExtras.make()

        _ = try await callCreateFromText(
            args: .object(["text": .string("answer email #email"), "locale": .string("en")]),
            context: fixture.context
        )
        let result = try await TasksSearchTool().call(
            args: .object(["query": .string("email")]),
            context: fixture.context
        )
        let data = try JSONEncoder().encode(result)
        let matches = try JSONDecoder().decode([TaskDTO].self, from: data)

        #expect(matches.map(\.title) == ["answer email"])
    }

    @MainActor
    @Test("throws validation when text empty")
    func emptyText() async throws {
        let fixture = try await InMemoryAgentContextWithExtras.make()

        await #expect(throws: AgentError.validation("text cannot be empty")) {
            _ = try await TasksCreateFromTextTool().call(
                args: .object(["text": .string("  \n")]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("throws validation for invalid locale")
    func invalidLocale() async throws {
        let fixture = try await InMemoryAgentContextWithExtras.make()

        await #expect(throws: AgentError.validation("locale must be one of: pl, en, auto")) {
            _ = try await TasksCreateFromTextTool().call(
                args: .object([
                    "text": .string("Buy milk"),
                    "locale": .string("de"),
                ]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("throws internal error when parser is not wired")
    func missingParser() async throws {
        let base = try await InMemoryAgentContextWithExtras.make()
        let context = AgentContext(
            modelContext: base.context.modelContext,
            taskRepository: base.context.taskRepository,
            searchIndex: base.context.searchIndex,
            now: base.context.now
        )

        await #expect(throws: AgentError.internalError("tasks.create_from_text requires an NL parser")) {
            _ = try await TasksCreateFromTextTool().call(
                args: .object(["text": .string("Buy milk")]),
                context: context
            )
        }
    }

    private func callCreateFromText(args: JSONValue, context: AgentContext) async throws -> TaskDTO {
        let result = try await TasksCreateFromTextTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(TaskDTO.self, from: data)
    }

    private func isDateOnly(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }
}
