import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("TasksUpdateTool")
struct TasksUpdateToolTests {
    @MainActor
    @Test("updates structured fields")
    func updatesStructuredFields() async throws {
        let task = TaskItem(title: "Old", body: "old notes", dueAt: Date(timeIntervalSince1970: 1))
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let dto = try await callUpdate(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object([
                    "title": .string("New"),
                    "notes": .string("new notes"),
                    "due_string": .string("tomorrow"),
                    "due_date": .string("2026-05-07T10:30:00Z"),
                    "deadline_date": .string("2026-05-10"),
                    "priority": .int(1),
                    "tags": .array([.string(" Work "), .string("q2")]),
                ]),
            ]),
            context: fixture.context
        )

        #expect(dto.title == "New")
        #expect(dto.notes == "new notes")
        #expect(dto.dueDate == "2026-05-07T10:30:00.000Z")
        #expect(dto.priority == 1)
        #expect(dto.tags == ["work", "q2"])
        #expect(dto.deadlineDate == "2026-05-10")

        let stored = try TasksMutationToolSupport.liveTask(id: task.id, context: fixture.context)
        #expect(stored.body.isEmpty)
        let noteID = try #require(stored.noteRef)
        let note = try #require(try fixture.repo.context.fetch(FetchDescriptor<Note>()).first { $0.id == noteID })
        #expect(note.plainText == "new notes")
    }

    @MainActor
    @Test("sets deadline_date on existing task")
    func setsDeadlineDate() async throws {
        let task = TaskItem(title: "Plan trip")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let dto = try await callUpdate(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object([
                    "deadline_date": .string("2026-07-01")
                ]),
            ]),
            context: fixture.context
        )

        #expect(dto.deadlineDate == "2026-07-01")
        let stored = try TasksMutationToolSupport.liveTask(id: task.id, context: fixture.context)
        #expect(stored.deadlineAt != nil)
    }

    @MainActor
    @Test("null clears deadline_date")
    func nullClearsDeadlineDate() async throws {
        let deadlineAt = try #require(
            TasksStructuredCreateArguments.parseDeadlineDate("2026-07-01")
        )
        let task = TaskItem(title: "Plan trip", deadlineAt: deadlineAt)
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let dto = try await callUpdate(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object(["deadline_date": .null]),
            ]),
            context: fixture.context
        )

        #expect(dto.deadlineDate == nil)
        let stored = try TasksMutationToolSupport.liveTask(id: task.id, context: fixture.context)
        #expect(stored.deadlineAt == nil)
    }

    @MainActor
    @Test("omitting deadline_date preserves existing value")
    func omittingDeadlineDatePreservesExistingValue() async throws {
        let deadlineAt = try #require(
            TasksStructuredCreateArguments.parseDeadlineDate("2026-07-01")
        )
        let task = TaskItem(title: "Plan trip", deadlineAt: deadlineAt)
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let dto = try await callUpdate(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object(["title": .string("Plan vacation")]),
            ]),
            context: fixture.context
        )

        #expect(dto.title == "Plan vacation")
        #expect(dto.deadlineDate == "2026-07-01")
    }

    @MainActor
    @Test("null clears nullable fields")
    func nullClearsNullableFields() async throws {
        let task = TaskItem(
            title: "Task",
            body: "notes",
            dueAt: Date(timeIntervalSince1970: 1_800_000_000),
            tags: ["work"]
        )
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let dto = try await callUpdate(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object([
                    "notes": .null,
                    "due_date": .null,
                    "tags": .null,
                ]),
            ]),
            context: fixture.context
        )

        #expect(dto.notes == nil)
        #expect(dto.dueDate == nil)
        #expect(dto.tags.isEmpty)
        let stored = try TasksMutationToolSupport.liveTask(id: task.id, context: fixture.context)
        #expect(stored.body.isEmpty)
        #expect(stored.noteRef == nil)
    }

    @MainActor
    @Test("schema advertises nullable patch fields")
    func schemaAdvertisesNullablePatchFields() throws {
        let data = try JSONEncoder().encode(TasksUpdateTool().inputSchema)
        let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        let patch = try #require(properties["patch"] as? [String: Any])
        let patchProperties = try #require(patch["properties"] as? [String: Any])

        for field in ["notes", "due_date", "deadline_date", "project_id", "section_id", "parent_id", "recurrence_rule"] {
            try expectAnyOfTypes(["string", "null"], for: field, in: patchProperties)
        }
        try expectAnyOfTypes(["array", "null"], for: "tags", in: patchProperties)
    }

    @MainActor
    @Test("not found for soft-deleted task")
    func softDeletedNotFound() async throws {
        let task = TaskItem(title: "Deleted")
        task.deletedAt = Date()
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.notFound("Task not found: \(task.id.uuidString)")) {
            _ = try await TasksUpdateTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "patch": .object(["title": .string("New")]),
                ]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("rejects invalid patch values")
    func invalidPatchValuesThrow() async throws {
        let task = TaskItem(title: "Task")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.validation("patch must be an object")) {
            _ = try await TasksUpdateTool().call(
                args: .object(["task_id": .string(task.id.uuidString), "patch": .string("title")]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("title cannot be null")) {
            _ = try await TasksUpdateTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "patch": .object(["title": .null]),
                ]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("priority must be an integer from 1 to 4")) {
            _ = try await TasksUpdateTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "patch": .object(["priority": .int(5)]),
                ]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("due_date must be an ISO8601 string")) {
            _ = try await TasksUpdateTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "patch": .object(["due_date": .bool(false)]),
                ]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("deadline_date must be a valid YYYY-MM-DD date")) {
            _ = try await TasksUpdateTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "patch": .object(["deadline_date": .string("2026-02-31")]),
                ]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("project_id must be a valid UUID")) {
            _ = try await TasksUpdateTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "patch": .object(["project_id": .string("project-1")]),
                ]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("updates search index immediately")
    func updatesSearchIndexImmediately() async throws {
        // Task content (notes/body) is no longer indexed — it lives in a `Note`
        // (spec §4.2/§13). This test pins that a TITLE change re-indexes immediately.
        let task = TaskItem(title: "oldtitletoken", body: "irrelevant")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        _ = try await callUpdate(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object(["title": .string("newtitletoken")]),
            ]),
            context: fixture.context
        )

        #expect(try await searchTitles("oldtitletoken", context: fixture.context).isEmpty)
        #expect(try await searchTitles("newtitletoken", context: fixture.context) == ["newtitletoken"])
    }

    @MainActor
    @Test("update assigns project, recurrence, and reminders")
    func updateAssignsProjectAndSetsRecurrenceAndReminders() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = Project(name: "Target Project")
        fixture.repo.context.insert(project)
        try fixture.repo.context.save()
        let task = TaskItem(title: "movable")
        try fixture.repo.insert(task)

        let dto = try await callUpdate(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object([
                    "project_id": .string(project.id.uuidString),
                    "recurrence_rule": .string("FREQ=WEEKLY"),
                    "reminders": .array([
                        .object([
                            "type": .string("absolute"), "at": .string("2026-07-01T09:00:00Z"),
                        ])
                    ]),
                ]),
            ]),
            context: fixture.context
        )

        #expect(dto.projectID == project.id.uuidString)
        #expect(dto.recurrenceRule == "FREQ=WEEKLY")
        #expect(dto.reminders?.count == 1)
    }

    @MainActor
    @Test("update with project_id only preserves existing section")
    func updateWithProjectOnlyPreservesExistingSection() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = Project(name: "Section Project")
        let section = Section(projectID: project.id, name: "Doing")
        fixture.repo.context.insert(project)
        fixture.repo.context.insert(section)
        try fixture.repo.context.save()
        let task = TaskItem(title: "sectioned")
        try fixture.repo.insert(task)
        // Pre-assign task to both project and section.
        try fixture.repo.assign(task, toProject: project.id, section: section.id)

        // Patch with project_id only — section must be preserved, not clobbered.
        let dto = try await callUpdate(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object([
                    "project_id": .string(project.id.uuidString)
                ]),
            ]),
            context: fixture.context
        )

        #expect(dto.projectID == project.id.uuidString)
        #expect(dto.sectionID == section.id.uuidString)
    }

    @MainActor
    @Test("project_id null clears project and section")
    func projectIDNullClearsProjectAndSection() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = Project(name: "Section Project")
        let section = Section(projectID: project.id, name: "Doing")
        fixture.repo.context.insert(project)
        fixture.repo.context.insert(section)
        try fixture.repo.context.save()
        let task = TaskItem(title: "sectioned")
        try fixture.repo.insert(task)
        try fixture.repo.assign(task, toProject: project.id, section: section.id)

        let dto = try await callUpdate(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object(["project_id": .null]),
            ]),
            context: fixture.context
        )

        #expect(dto.projectID == nil)
        #expect(dto.sectionID == nil)
        #expect(task.projectID == nil)
        #expect(task.sectionID == nil)
    }

    @MainActor
    @Test("moving to another project without section_id clears old section")
    func movingToAnotherProjectWithoutSectionClearsOldSection() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let oldProject = Project(name: "Old Project")
        let oldSection = Section(projectID: oldProject.id, name: "Doing")
        let newProject = Project(name: "New Project")
        fixture.repo.context.insert(oldProject)
        fixture.repo.context.insert(oldSection)
        fixture.repo.context.insert(newProject)
        try fixture.repo.context.save()
        let task = TaskItem(title: "sectioned")
        try fixture.repo.insert(task)
        try fixture.repo.assign(task, toProject: oldProject.id, section: oldSection.id)

        let dto = try await callUpdate(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object(["project_id": .string(newProject.id.uuidString)]),
            ]),
            context: fixture.context
        )

        #expect(dto.projectID == newProject.id.uuidString)
        #expect(dto.sectionID == nil)
        #expect(task.projectID == newProject.id)
        #expect(task.sectionID == nil)
    }

    @MainActor
    @Test("unknown project_id on update throws validation")
    func unknownProjectIDOnUpdateThrows() async throws {
        let task = TaskItem(title: "Task")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.self) {
            _ = try await TasksUpdateTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "patch": .object(["project_id": .string(UUID().uuidString)]),
                ]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("unknown project_id on update does not persist earlier patch fields")
    func unknownProjectIDOnUpdateDoesNotPersistEarlierPatchFields() async throws {
        let task = TaskItem(title: "Original", recurrenceRule: "FREQ=WEEKLY")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.self) {
            _ = try await TasksUpdateTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "patch": .object([
                        "title": .string("Changed"),
                        "recurrence_rule": .string("FREQ=DAILY"),
                        "reminders": .array([
                            .object([
                                "type": .string("relative"),
                                "offset": .double(-900),
                                "anchor": .string("due"),
                            ])
                        ]),
                        "project_id": .string(UUID().uuidString),
                    ]),
                ]),
                context: fixture.context
            )
        }

        let stored = try TasksMutationToolSupport.liveTask(id: task.id, context: fixture.context)
        #expect(stored.title == "Original")
        #expect(stored.recurrenceRule == "FREQ=WEEKLY")
        #expect(stored.reminders.isEmpty)
        #expect(stored.projectID == nil)
    }

    private func callUpdate(args: JSONValue, context: AgentContext) async throws -> TaskDTO {
        let result = try await TasksUpdateTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(TaskDTO.self, from: data)
    }

    private func searchTitles(_ query: String, context: AgentContext) async throws -> [String] {
        let result = try await TasksSearchTool().call(
            args: .object(["query": .string(query)]),
            context: context
        )
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode([TaskDTO].self, from: data).map(\.title)
    }

    private func expectAnyOfTypes(
        _ expectedTypes: [String],
        for field: String,
        in properties: [String: Any]
    ) throws {
        let fieldSchema = try #require(properties[field] as? [String: Any])
        let alternatives = try #require(fieldSchema["anyOf"] as? [[String: Any]])
        #expect(alternatives.compactMap { $0["type"] as? String } == expectedTypes)
        #expect(fieldSchema["description"] != nil)
    }
}

/// Cycle patch coverage (Tranche 2 Plan C), a separate suite to keep the main
/// `TasksUpdateToolTests` struct inside the type-body lint budget.
@Suite("TasksUpdateTool cycle patch")
struct TasksUpdateToolCycleTests {
    @Test("patch cycle_id assigns through assignCycle, null clears, unknown cycle rejected")
    @MainActor
    func cyclePatch() async throws {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let task = TaskItem(title: "Cycle me")
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        _ = container
        let cycles = CycleRepository(context: context.modelContext.context, now: { stamp })
        let cycle = try cycles.create(
            name: "Sprint", startAt: stamp, endAt: stamp.addingTimeInterval(86_400)
        )

        let updated = try await TasksUpdateTool().call(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object(["cycle_id": .string(cycle.id.uuidString)]),
            ]),
            context: context
        )
        #expect(task.cycleID == cycle.id)
        #expect(updated["cycle_id"]?.stringValue == cycle.id.uuidString)

        _ = try await TasksUpdateTool().call(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object(["cycle_id": .null]),
            ]),
            context: context
        )
        #expect(task.cycleID == nil)

        await #expect(throws: AgentError.self) {
            _ = try await TasksUpdateTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "patch": .object(["cycle_id": .string(UUID().uuidString)]),
                ]),
                context: context
            )
        }
    }
}
