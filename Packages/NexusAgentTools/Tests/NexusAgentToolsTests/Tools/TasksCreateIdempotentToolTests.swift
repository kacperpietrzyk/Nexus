import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("TasksCreateIdempotentTool")
struct TasksCreateIdempotentToolTests {
    @MainActor
    @Test("first call creates with externalSourceID")
    func firstCallCreates() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = Project(name: "Import Project")
        fixture.repo.context.insert(project)
        try fixture.repo.context.save()
        let response = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:1"),
                "title": .string("Imported task"),
                "due_string": .string("next week"),
                "deadline_date": .string("2026-05-10"),
                "project_id": .string(project.id.uuidString),
            ]),
            context: fixture.context
        )

        let rows = try fixture.repo.context.fetch(FetchDescriptor<TaskItem>())
        #expect(rows.count == 1)
        #expect(response.wasCreated)
        #expect(response.task.title == "Imported task")
        #expect(response.task.externalSourceID == "todoist:1")
        #expect(rows.first?.externalSourceID == "todoist:1")
    }

    @MainActor
    @Test("persists deadline_date on first create")
    func persistsDeadlineDateOnFirstCreate() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let response = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:deadline-create"),
                "title": .string("Imported task"),
                "deadline_date": .string("2026-05-10"),
            ]),
            context: fixture.context
        )

        let rows = try fixture.repo.context.fetch(FetchDescriptor<TaskItem>())
        #expect(response.wasCreated)
        #expect(response.task.deadlineDate == "2026-05-10")
        #expect(rows.first?.deadlineAt != nil)
    }

    @MainActor
    @Test("rejects unknown project_id")
    func rejectsUnknownProjectID() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.self) {
            _ = try await TasksCreateIdempotentTool().call(
                args: .object([
                    "external_source_id": .string("todoist:orphan"),
                    "title": .string("orphan"),
                    "project_id": .string(UUID().uuidString),
                ]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("persists project, section, parent, recurrence, and reminders on create")
    func idempotentCreatePersistsAllFields() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = Project(name: "Import Project")
        let section = Section(projectID: project.id, name: "Backlog")
        fixture.repo.context.insert(project)
        fixture.repo.context.insert(section)
        try fixture.repo.context.save()
        let parent = TaskItem(title: "parent task")
        try fixture.repo.insert(parent)

        let response = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:full-fields"),
                "title": .string("child task"),
                "project_id": .string(project.id.uuidString),
                "section_id": .string(section.id.uuidString),
                "parent_id": .string(parent.id.uuidString),
                "recurrence_rule": .string("FREQ=WEEKLY"),
                "reminders": .array([
                    .object([
                        "type": .string("relative"),
                        "offset": .double(-3600),
                        "anchor": .string("due"),
                    ])
                ]),
            ]),
            context: fixture.context
        )

        #expect(response.wasCreated)
        #expect(response.task.projectID == project.id.uuidString)
        #expect(response.task.sectionID == section.id.uuidString)
        #expect(response.task.parentID == parent.id.uuidString)
        #expect(response.task.recurrenceRule == "FREQ=WEEKLY")
        #expect(response.task.reminders?.count == 1)
    }

    @MainActor
    @Test("idempotent update propagates project, recurrence, and reminders")
    func idempotentUpdatePropagatesAllFields() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = Project(name: "Update Project")
        fixture.repo.context.insert(project)
        try fixture.repo.context.save()

        _ = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:update-fields"),
                "title": .string("original"),
            ]),
            context: fixture.context
        )

        let response = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:update-fields"),
                "title": .string("updated"),
                "project_id": .string(project.id.uuidString),
                "recurrence_rule": .string("FREQ=DAILY"),
                "reminders": .array([
                    .object([
                        "type": .string("relative"),
                        "offset": .double(-900),
                        "anchor": .string("due"),
                    ])
                ]),
            ]),
            context: fixture.context
        )

        #expect(!response.wasCreated)
        #expect(response.task.title == "updated")
        #expect(response.task.projectID == project.id.uuidString)
        #expect(response.task.recurrenceRule == "FREQ=DAILY")
        #expect(response.task.reminders?.count == 1)
    }

    @MainActor
    @Test("rerun preserves deadlineAt when deadline_date is omitted")
    func rerunPreservesDeadlineWhenOmitted() async throws {
        let fixture = try await InMemoryAgentContext.make()

        _ = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:keep-deadline"),
                "title": .string("Original"),
                "deadline_date": .string("2026-06-15"),
            ]),
            context: fixture.context
        )
        let response = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:keep-deadline"),
                "title": .string("Renamed"),
            ]),
            context: fixture.context
        )

        #expect(!response.wasCreated)
        #expect(response.task.title == "Renamed")
        #expect(response.task.deadlineDate == "2026-06-15")
    }

    @MainActor
    @Test("rerun updates without duplicate")
    func rerunUpdatesWithoutDuplicate() async throws {
        let fixture = try await InMemoryAgentContext.make()

        _ = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:1"),
                "title": .string("Original title"),
                "priority": .int(3),
            ]),
            context: fixture.context
        )
        let response = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:1"),
                "title": .string("Updated title"),
                "notes": .string("Updated notes"),
                "due_date": .string("2026-05-07T10:30:00.123Z"),
                "priority": .int(1),
                "tags": .array([.string("Import")]),
            ]),
            context: fixture.context
        )

        let rows = try fixture.repo.context.fetch(FetchDescriptor<TaskItem>())
        #expect(rows.count == 1)
        #expect(!response.wasCreated)
        #expect(response.task.title == "Updated title")
        #expect(response.task.notes == "Updated notes")
        #expect(response.task.dueDate == "2026-05-07T10:30:00.123Z")
        #expect(response.task.priority == 1)
        #expect(response.task.tags == ["import"])
    }

    @MainActor
    @Test("rerun updates search index")
    func rerunUpdatesSearchIndex() async throws {
        let fixture = try await InMemoryAgentContext.make()

        _ = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:1"),
                "title": .string("Original title"),
                "notes": .string("oldalpha"),
            ]),
            context: fixture.context
        )
        _ = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:1"),
                "title": .string("Updated title"),
                "notes": .string("newbeta"),
            ]),
            context: fixture.context
        )

        let oldMatches = try await searchTasks(query: "oldalpha", context: fixture.context)
        let newMatches = try await searchTasks(query: "newbeta", context: fixture.context)
        #expect(oldMatches.isEmpty)
        #expect(newMatches.map(\.title) == ["Updated title"])
    }

    @MainActor
    @Test("soft-deleted external source rerun creates a fresh task, leaving the tombstone intact")
    func softDeletedExternalSourceRerunCreatesFresh() async throws {
        let fixture = try await InMemoryAgentContext.make()

        _ = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:deleted"),
                "title": .string("Original title"),
                "notes": .string("old-token"),
            ]),
            context: fixture.context
        )
        let rows = try fixture.repo.context.fetch(FetchDescriptor<TaskItem>())
        let task = try #require(rows.first)
        try fixture.repo.softDelete(task)

        let response = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:deleted"),
                "title": .string("Updated deleted title"),
                "notes": .string("new-token"),
            ]),
            context: fixture.context
        )

        // "Create fresh" semantics: the dedup lookup ignores the soft-deleted tombstone, so a
        // re-import after delete yields a new LIVE task instead of silently mutating the dead row
        // (which previously left the task permanently invisible).
        let allRows = try fixture.repo.context.fetch(FetchDescriptor<TaskItem>())
        let live = allRows.filter { $0.deletedAt == nil }
        let tombstones = allRows.filter { $0.deletedAt != nil }
        #expect(allRows.count == 2)
        #expect(response.wasCreated)
        #expect(response.task.state == "open")
        #expect(live.map(\.title) == ["Updated deleted title"])
        #expect(tombstones.map(\.title) == ["Original title"])
    }

    @MainActor
    @Test("omitted optional fields do not clear existing values")
    func omittedOptionalFieldsDoNotClearExistingValues() async throws {
        let fixture = try await InMemoryAgentContext.make()

        _ = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:1"),
                "title": .string("Original title"),
                "notes": .string("Keep notes"),
                "due_date": .string("2026-05-07T10:30:00Z"),
                "priority": .int(2),
                "tags": .array([.string("keep")]),
            ]),
            context: fixture.context
        )
        let response = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:1"),
                "title": .string("Title only update"),
            ]),
            context: fixture.context
        )

        #expect(!response.wasCreated)
        #expect(response.task.title == "Title only update")
        #expect(response.task.notes == "Keep notes")
        #expect(response.task.dueDate == "2026-05-07T10:30:00.000Z")
        #expect(response.task.priority == 2)
        #expect(response.task.tags == ["keep"])
    }

    @MainActor
    @Test("metadata mismatch raises conflict")
    func metadataMismatchRaisesConflict() async throws {
        let fixture = try await InMemoryAgentContext.make()

        _ = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:1"),
                "external_source_metadata": .string(Data("old".utf8).base64EncodedString()),
                "title": .string("Task"),
            ]),
            context: fixture.context
        )

        await #expect(throws: AgentError.conflict("external_source_metadata mismatch for todoist:1")) {
            _ = try await TasksCreateIdempotentTool().call(
                args: .object([
                    "external_source_id": .string("todoist:1"),
                    "external_source_metadata": .string(Data("new".utf8).base64EncodedString()),
                    "title": .string("Task"),
                ]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("missing external_source_id throws validation")
    func missingExternalSourceIDThrows() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("Missing required string field: external_source_id")) {
            _ = try await TasksCreateIdempotentTool().call(
                args: .object(["title": .string("Task")]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("invalid metadata Base64 throws validation")
    func invalidMetadataThrows() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("external_source_metadata must be valid Base64")) {
            _ = try await TasksCreateIdempotentTool().call(
                args: .object([
                    "external_source_id": .string("todoist:1"),
                    "external_source_metadata": .string("not base64 !"),
                    "title": .string("Task"),
                ]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("invalid existing update priority and date throw validation")
    func invalidExistingUpdateFieldsThrow() async throws {
        let fixture = try await InMemoryAgentContext.make()

        _ = try await callIdempotent(
            args: .object([
                "external_source_id": .string("todoist:1"),
                "title": .string("Task"),
            ]),
            context: fixture.context
        )

        await #expect(throws: AgentError.validation("priority must be an integer from 1 to 4")) {
            _ = try await TasksCreateIdempotentTool().call(
                args: .object([
                    "external_source_id": .string("todoist:1"),
                    "title": .string("Task"),
                    "priority": .int(0),
                ]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("Invalid ISO8601 timestamp for field: due_date")) {
            _ = try await TasksCreateIdempotentTool().call(
                args: .object([
                    "external_source_id": .string("todoist:1"),
                    "title": .string("Task"),
                    "due_date": .string("next monday"),
                ]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("due_string must be a string")) {
            _ = try await TasksCreateIdempotentTool().call(
                args: .object([
                    "external_source_id": .string("todoist:1"),
                    "title": .string("Task"),
                    "due_string": .bool(true),
                ]),
                context: fixture.context
            )
        }
    }

    private func callIdempotent(args: JSONValue, context: AgentContext) async throws -> IdempotentResponseDTO {
        let result = try await TasksCreateIdempotentTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(IdempotentResponseDTO.self, from: data)
    }

    private func searchTasks(query: String, context: AgentContext) async throws -> [TaskDTO] {
        let result = try await TasksSearchTool().call(
            args: .object(["query": .string(query)]),
            context: context
        )
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode([TaskDTO].self, from: data)
    }
}
