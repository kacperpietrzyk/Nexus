import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools
@testable import NexusAgentToolsExtras

@Suite("Migration fixture round-trip")
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

    @MainActor
    @Test("reconstructs Todoist hierarchy comments recurrence and reminders without tag flattening")
    func todoistStructuredAcceptanceFixture() async throws {
        let fixture = try await makeStructuredFixture()
        let imported = try await importStructuredFixture(fixture)

        try await assertStructuredImport(imported, fixture: fixture)
        try await rerunStructuredFixture(parentID: imported.parent.task.id, fixture: fixture)
        try await assertStructuredRerun(parentID: imported.parent.task.id, fixture: fixture)
        try await assertRecurringCompletionSpawnsNextOccurrence(dailyID: imported.daily.task.id, fixture: fixture)
    }

    private static func loadFixture() throws -> [TodoistFixtureEntry] {
        let url = try #require(Bundle.module.url(forResource: "todoist-sample", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let entries = try JSONDecoder().decode([TodoistFixtureEntry].self, from: data)
        #expect(entries.count == 50)
        return entries
    }

    @MainActor
    private func upsertTask(
        _ args: [String: JSONValue],
        tool: TasksCreateIdempotentTool,
        context: AgentContext
    ) async throws -> IdempotentResponseDTO {
        let result = try await tool.call(args: .object(args), context: context)
        return try TasksToolJSON.decode(IdempotentResponseDTO.self, from: result)
    }

    @MainActor
    private func listTasks(
        _ filter: [String: JSONValue],
        tool: TasksListTool,
        context: AgentContext
    ) async throws -> TaskListResponseDTO {
        let result = try await tool.call(args: .object(["filter": .object(filter)]), context: context)
        return try TasksToolJSON.decode(TaskListResponseDTO.self, from: result)
    }

    @MainActor
    private func makeStructuredFixture() async throws -> TodoistStructuredFixture {
        let setupTuple = try await InMemoryAgentContextWithExtras.make()
        let setup = AgentFixtureContext(context: setupTuple.context, container: setupTuple.container, repo: setupTuple.repo)
        let project = try await createProject(named: "CyberLab", context: setup.context)
        return TodoistStructuredFixture(
            setup: setup,
            project: project,
            doing: try await createSection(named: "Doing", in: project, context: setup.context),
            later: try await createSection(named: "Later", in: project, context: setup.context)
        )
    }

    @MainActor
    private func createProject(named name: String, context: AgentContext) async throws -> Project {
        let result = try await ProjectsCreateTool().call(args: .object(["name": .string(name)]), context: context)
        let dto = try TasksToolJSON.decode(ProjectDTO.self, from: result)
        let id = try #require(UUID(uuidString: dto.id))
        return try #require(try context.projectRepository.find(id: id))
    }

    @MainActor
    private func createSection(named name: String, in project: Project, context: AgentContext) async throws -> Section {
        let result = try await SectionsCreateTool().call(
            args: .object([
                "project_id": .string(project.id.uuidString),
                "name": .string(name),
            ]),
            context: context
        )
        let dto = try TasksToolJSON.decode(SectionDTO.self, from: result)
        let id = try #require(UUID(uuidString: dto.id))
        return try #require(
            try SectionRepository(context: context.modelContext.context).sections(in: project.id).first {
                $0.id == id
            })
    }

    @MainActor
    private func importStructuredFixture(_ fixture: TodoistStructuredFixture) async throws -> ImportedTodoistFixture {
        let tool = TasksCreateIdempotentTool()
        let parent = try await upsertTask(parentArgs(fixture), tool: tool, context: fixture.context)
        for index in 1...9 {
            _ = try await upsertTask(childArgs(index: index, parentID: parent.task.id, fixture), tool: tool, context: fixture.context)
        }
        let daily = try await upsertTask(dailyArgs(fixture), tool: tool, context: fixture.context)
        let weekly = try await upsertTask(weeklyArgs(fixture), tool: tool, context: fixture.context)
        let reminded = try await addCommentAndReminder(parentID: parent.task.id, context: fixture.context)
        return ImportedTodoistFixture(parent: parent, daily: daily, weekly: weekly, reminded: reminded)
    }

    @MainActor
    private func addCommentAndReminder(parentID: String, context: AgentContext) async throws -> TaskDTO {
        _ = try await CommentsAddTool().call(args: commentArgs(parentID: parentID), context: context)
        let result = try await TasksUpdateTool().call(
            args: .object([
                "task_id": .string(parentID),
                "patch": .object([
                    "reminders": .array([
                        .object(["type": .string("relative"), "offset": .double(-1800), "anchor": .string("due")])
                    ])
                ]),
            ]),
            context: context
        )
        return try TasksToolJSON.decode(TaskDTO.self, from: result)
    }

    @MainActor
    private func assertStructuredImport(_ imported: ImportedTodoistFixture, fixture: TodoistStructuredFixture) async throws {
        let projectList = try await listTasks(
            ["project_id": .string(fixture.project.id.uuidString)],
            tool: .init(),
            context: fixture.context
        )
        let sectionList = try await listTasks(
            ["section_id": .string(fixture.doing.id.uuidString)],
            tool: .init(),
            context: fixture.context
        )
        let comments = try await comments(for: imported.parent.task.id, context: fixture.context)

        #expect(projectList.total == 12)
        #expect(sectionList.total == 10)
        #expect(sectionList.tasks.allSatisfy { $0.sectionID == fixture.doing.id.uuidString })
        #expect(sectionList.tasks.filter { $0.parentID == imported.parent.task.id }.count == 9)
        #expect(imported.daily.task.recurrenceRule == "FREQ=DAILY")
        #expect(imported.daily.task.reminders == [ReminderDTO(type: "relative", offset: -900, anchor: "due", at: nil)])
        #expect(imported.weekly.task.recurrenceRule == "FREQ=WEEKLY;BYDAY=SU")
        #expect(comments.map(\.externalSourceID) == ["todoist-comment:cyberlab-parent-1"])
        #expect(imported.reminded.reminders == [ReminderDTO(type: "relative", offset: -1800, anchor: "due", at: nil)])
    }

    @MainActor
    private func rerunStructuredFixture(parentID: String, fixture: TodoistStructuredFixture) async throws {
        _ = try await upsertTask(rerunParentArgs(fixture), tool: .init(), context: fixture.context)
        _ = try await CommentsAddTool().call(args: commentArgs(parentID: parentID), context: fixture.context)
    }

    @MainActor
    private func assertStructuredRerun(parentID: String, fixture: TodoistStructuredFixture) async throws {
        let afterRerun = try fixture.setup.repo.context.fetch(FetchDescriptor<TaskItem>())
        let parentAfterRerun = try #require(afterRerun.first { $0.externalSourceID == "todoist:cyberlab-parent" })
        #expect(afterRerun.count == 12)
        #expect(try await comments(for: parentID, context: fixture.context).count == 1)
        #expect(parentAfterRerun.sectionID == fixture.doing.id)
    }

    @MainActor
    private func assertRecurringCompletionSpawnsNextOccurrence(dailyID: String, fixture: TodoistStructuredFixture) async throws {
        _ = try await TasksCompleteTool().call(args: .object(["task_id": .string(dailyID)]), context: fixture.context)
        let afterComplete = try fixture.setup.repo.context.fetch(FetchDescriptor<TaskItem>())
        let dailyUUID = try #require(UUID(uuidString: dailyID))
        let spawn = try #require(afterComplete.first { $0.recurrenceParentId == dailyUUID })
        #expect(spawn.projectID == fixture.project.id)
        #expect(spawn.sectionID == fixture.later.id)
        #expect(spawn.recurrenceRule == "FREQ=DAILY")
        #expect(spawn.reminders == [.relative(offset: -900, anchor: .due)])
    }

    @MainActor
    private func comments(for parentID: String, context: AgentContext) async throws -> [CommentDTO] {
        let result = try await CommentsListTool().call(
            args: .object(["item_id": .string(parentID), "item_kind": .string("task")]),
            context: context
        )
        return try TasksToolJSON.decode([CommentDTO].self, from: result)
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

private struct AgentFixtureContext {
    let context: AgentContext
    let container: ModelContainer
    let repo: TaskItemRepository
}

private struct TodoistStructuredFixture {
    let setup: AgentFixtureContext
    let project: Project
    let doing: Section
    let later: Section

    var context: AgentContext {
        setup.context
    }
}

private struct ImportedTodoistFixture {
    let parent: IdempotentResponseDTO
    let daily: IdempotentResponseDTO
    let weekly: IdempotentResponseDTO
    let reminded: TaskDTO
}

private func parentArgs(_ fixture: TodoistStructuredFixture) -> [String: JSONValue] {
    [
        "external_source_id": .string("todoist:cyberlab-parent"),
        "title": .string("CyberLab parent"),
        "project_id": .string(fixture.project.id.uuidString),
        "section_id": .string(fixture.doing.id.uuidString),
        "tags": .array([.string("cyberlab")]),
    ]
}

private func childArgs(index: Int, parentID: String, _ fixture: TodoistStructuredFixture) -> [String: JSONValue] {
    [
        "external_source_id": .string("todoist:cyberlab-child-\(index)"),
        "title": .string("CyberLab child \(index)"),
        "project_id": .string(fixture.project.id.uuidString),
        "section_id": .string(fixture.doing.id.uuidString),
        "parent_id": .string(parentID),
        "tags": .array([.string("cyberlab")]),
    ]
}

private func dailyArgs(_ fixture: TodoistStructuredFixture) -> [String: JSONValue] {
    [
        "external_source_id": .string("todoist:morning-brief"),
        "title": .string("Morning Brief"),
        "due_date": .string("2026-06-09T08:00:00Z"),
        "project_id": .string(fixture.project.id.uuidString),
        "section_id": .string(fixture.later.id.uuidString),
        "recurrence_rule": .string("FREQ=DAILY"),
        "reminders": .array([
            .object(["type": .string("relative"), "offset": .double(-900), "anchor": .string("due")])
        ]),
    ]
}

private func weeklyArgs(_ fixture: TodoistStructuredFixture) -> [String: JSONValue] {
    [
        "external_source_id": .string("todoist:weekly-review"),
        "title": .string("Weekly Review"),
        "due_date": .string("2026-06-14T16:00:00Z"),
        "project_id": .string(fixture.project.id.uuidString),
        "section_id": .string(fixture.later.id.uuidString),
        "recurrence_rule": .string("FREQ=WEEKLY;BYDAY=SU"),
    ]
}

private func rerunParentArgs(_ fixture: TodoistStructuredFixture) -> [String: JSONValue] {
    [
        "external_source_id": .string("todoist:cyberlab-parent"),
        "title": .string("CyberLab parent"),
        "project_id": .string(fixture.project.id.uuidString),
    ]
}

private func commentArgs(parentID: String) -> JSONValue {
    .object([
        "item_id": .string(parentID),
        "item_kind": .string("task"),
        "body": .string("Imported Todoist comment"),
        "external_source_id": .string("todoist-comment:cyberlab-parent-1"),
    ])
}
