import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("TasksCreateTool")
struct TasksCreateToolTests {
    @MainActor
    @Test("creates title only and persists one row")
    func createsTitleOnly() async throws {
        let fixture = try await InMemoryAgentContext.make()

        let dto = try await callCreate(
            args: .object(["title": .string("Write weekly review")]),
            context: fixture.context
        )

        let rows = try fixture.repo.context.fetch(FetchDescriptor<TaskItem>())
        #expect(rows.count == 1)
        #expect(dto.title == "Write weekly review")
        #expect(rows.first?.title == "Write weekly review")
        #expect(dto.priority == 4)
    }

    @MainActor
    @Test("creates structured fields")
    func createsStructuredFields() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let projectID = UUID()

        let dto = try await callCreate(
            args: .object([
                "title": .string("Prepare deck"),
                "notes": .string("Use latest metrics"),
                "due_string": .string("tomorrow morning"),
                "due_date": .string("2026-05-07T10:30:00Z"),
                "deadline_date": .string("2026-05-10"),
                "priority": .int(1),
                "tags": .array([.string(" Work "), .string("Q2"), .string("work")]),
                "project_id": .string(projectID.uuidString),
            ]),
            context: fixture.context
        )

        #expect(dto.title == "Prepare deck")
        #expect(dto.notes == "Use latest metrics")
        #expect(dto.dueDate == "2026-05-07T10:30:00.000Z")
        #expect(dto.deadlineDate == "2026-05-10")
        #expect(dto.priority == 1)
        #expect(dto.tags == ["work", "q2"])
    }

    @MainActor
    @Test("persists deadline_date to deadlineAt")
    func persistsDeadlineDate() async throws {
        let fixture = try await InMemoryAgentContext.make()

        let dto = try await callCreate(
            args: .object([
                "title": .string("Submit taxes"),
                "deadline_date": .string("2026-06-15"),
            ]),
            context: fixture.context
        )

        let rows = try fixture.repo.context.fetch(FetchDescriptor<TaskItem>())
        #expect(rows.count == 1)
        #expect(rows.first?.deadlineAt != nil)
        #expect(dto.deadlineDate == "2026-06-15")
    }

    @MainActor
    @Test("create updates search index immediately")
    func createUpdatesSearchIndexImmediately() async throws {
        let fixture = try await InMemoryAgentContext.make()

        _ = try await callCreate(
            args: .object([
                "title": .string("Searchable imported task"),
                "notes": .string("needle-token"),
            ]),
            context: fixture.context
        )

        let result = try await TasksSearchTool().call(
            args: .object(["query": .string("needle-token")]),
            context: fixture.context
        )
        let data = try JSONEncoder().encode(result)
        let tasks = try JSONDecoder().decode([TaskDTO].self, from: data)
        #expect(tasks.map(\.title) == ["Searchable imported task"])
    }

    @MainActor
    @Test("accepts opaque project_id without persisting it")
    func acceptsOpaqueProjectIDWithoutPersistingIt() async throws {
        let fixture = try await InMemoryAgentContext.make()

        let dto = try await callCreate(
            args: .object([
                "title": .string("Future linked task"),
                "project_id": .string(UUID().uuidString),
            ]),
            context: fixture.context
        )

        #expect(dto.title == "Future linked task")
        #expect(dto.projectID == nil)
    }

    @MainActor
    @Test("missing title throws validation")
    func missingTitleThrows() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("Missing required string field: title")) {
            _ = try await TasksCreateTool().call(args: .object([:]), context: fixture.context)
        }
    }

    @MainActor
    @Test("empty title throws validation")
    func emptyTitleThrows() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("title cannot be empty")) {
            _ = try await TasksCreateTool().call(
                args: .object(["title": .string("  \n")]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("bad priority throws validation")
    func badPriorityThrows() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("priority must be an integer from 1 to 4")) {
            _ = try await TasksCreateTool().call(
                args: .object(["title": .string("Task"), "priority": .int(5)]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("priority must be an integer from 1 to 4")) {
            _ = try await TasksCreateTool().call(
                args: .object(["title": .string("Task"), "priority": .string("high")]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("invalid due_date throws validation")
    func invalidDueDateThrows() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("Invalid ISO8601 timestamp for field: due_date")) {
            _ = try await TasksCreateTool().call(
                args: .object(["title": .string("Task"), "due_date": .string("tomorrow")]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("wrong optional field types throw validation")
    func wrongOptionalTypesThrow() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("notes must be a string")) {
            _ = try await TasksCreateTool().call(
                args: .object(["title": .string("Task"), "notes": .int(1)]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("due_date must be an ISO8601 string")) {
            _ = try await TasksCreateTool().call(
                args: .object(["title": .string("Task"), "due_date": .int(1)]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("due_string must be a string")) {
            _ = try await TasksCreateTool().call(
                args: .object(["title": .string("Task"), "due_string": .array([])]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("deadline_date must be a YYYY-MM-DD string")) {
            _ = try await TasksCreateTool().call(
                args: .object(["title": .string("Task"), "deadline_date": .int(1)]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("deadline_date must be a valid YYYY-MM-DD date")) {
            _ = try await TasksCreateTool().call(
                args: .object(["title": .string("Task"), "deadline_date": .string("2026-02-31")]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("project_id must be a UUID string")) {
            _ = try await TasksCreateTool().call(
                args: .object(["title": .string("Task"), "project_id": .bool(false)]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("project_id must be a valid UUID")) {
            _ = try await TasksCreateTool().call(
                args: .object(["title": .string("Task"), "project_id": .string("project-1")]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("tags must be an array of strings")) {
            _ = try await TasksCreateTool().call(
                args: .object(["title": .string("Task"), "tags": .string("work")]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("non-string tag throws validation")
    func nonStringTagThrows() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("tags[1] must be a string")) {
            _ = try await TasksCreateTool().call(
                args: .object([
                    "title": .string("Task"),
                    "tags": .array([.string("work"), .int(7)]),
                ]),
                context: fixture.context
            )
        }
    }

    private func callCreate(args: JSONValue, context: AgentContext) async throws -> TaskDTO {
        let result = try await TasksCreateTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(TaskDTO.self, from: data)
    }
}
