import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("CommentsTools")
struct CommentsToolsTests {
    // MARK: - comments.list + comments.add round-trip

    @MainActor
    @Test("add then list returns comment")
    func addThenListReturnsComment() async throws {
        let task = TaskItem(title: "commented")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let addArgs = JSONValue.object([
            "item_id": .string(task.id.uuidString),
            "item_kind": .string("task"),
            "body": .string("hello"),
        ])
        _ = try await CommentsAddTool().call(args: addArgs, context: fixture.context)

        let listArgs = JSONValue.object([
            "item_id": .string(task.id.uuidString),
            "item_kind": .string("task"),
        ])
        let result = try await CommentsListTool().call(args: listArgs, context: fixture.context)
        let dtos = try TasksToolJSON.decode([CommentDTO].self, from: result)
        #expect(dtos.map(\.body) == ["hello"])
    }

    // MARK: - edit changes body and is reflected by list

    @MainActor
    @Test("edit changes body and list reflects it")
    func editChangesBody() async throws {
        let task = TaskItem(title: "edit-me task")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        // Add a comment
        let addResult = try await CommentsAddTool().call(
            args: .object([
                "item_id": .string(task.id.uuidString),
                "item_kind": .string("task"),
                "body": .string("original body"),
            ]),
            context: fixture.context
        )
        let added = try TasksToolJSON.decode(CommentDTO.self, from: addResult)

        // Edit it
        _ = try await CommentsEditTool().call(
            args: .object([
                "id": .string(added.id),
                "body": .string("updated body"),
            ]),
            context: fixture.context
        )

        // List should show updated body
        let listResult = try await CommentsListTool().call(
            args: .object([
                "item_id": .string(task.id.uuidString),
                "item_kind": .string("task"),
            ]),
            context: fixture.context
        )
        let dtos = try TasksToolJSON.decode([CommentDTO].self, from: listResult)
        #expect(dtos.map(\.body) == ["updated body"])
    }

    // MARK: - delete hides from list

    @MainActor
    @Test("delete hides comment from list")
    func deleteHidesFromList() async throws {
        let task = TaskItem(title: "delete-me task")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        // Add two comments
        let addResult = try await CommentsAddTool().call(
            args: .object([
                "item_id": .string(task.id.uuidString),
                "item_kind": .string("task"),
                "body": .string("keep me"),
            ]),
            context: fixture.context
        )
        let toKeep = try TasksToolJSON.decode(CommentDTO.self, from: addResult)

        let addResult2 = try await CommentsAddTool().call(
            args: .object([
                "item_id": .string(task.id.uuidString),
                "item_kind": .string("task"),
                "body": .string("delete me"),
            ]),
            context: fixture.context
        )
        let toDelete = try TasksToolJSON.decode(CommentDTO.self, from: addResult2)

        // Delete the second
        let deleteResult = try await CommentsDeleteTool().call(
            args: .object(["id": .string(toDelete.id)]),
            context: fixture.context
        )
        #expect(deleteResult == .object(["deleted": .bool(true)]))

        // List should only contain the first
        let listResult = try await CommentsListTool().call(
            args: .object([
                "item_id": .string(task.id.uuidString),
                "item_kind": .string("task"),
            ]),
            context: fixture.context
        )
        let dtos = try TasksToolJSON.decode([CommentDTO].self, from: listResult)
        #expect(dtos.map(\.id) == [toKeep.id])
        #expect(dtos.map(\.body) == ["keep me"])
    }

    // MARK: - external_source_id round-trips in DTO

    @MainActor
    @Test("add with external_source_id round-trips it in DTO")
    func externalSourceIDRoundTrip() async throws {
        let task = TaskItem(title: "ext-source task")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let addResult = try await CommentsAddTool().call(
            args: .object([
                "item_id": .string(task.id.uuidString),
                "item_kind": .string("task"),
                "body": .string("imported comment"),
                "external_source_id": .string("todoist-comment:abc123"),
            ]),
            context: fixture.context
        )
        let dto = try TasksToolJSON.decode(CommentDTO.self, from: addResult)
        #expect(dto.externalSourceID == "todoist-comment:abc123")
        #expect(dto.body == "imported comment")
    }

    // MARK: - item_kind=project also works

    @MainActor
    @Test("item_kind project also works")
    func projectKindWorks() async throws {
        let project = Project(name: "My Project")
        let fixture = try await InMemoryAgentContext.make()
        fixture.repo.context.insert(project)
        try fixture.repo.context.save()

        let addResult = try await CommentsAddTool().call(
            args: .object([
                "item_id": .string(project.id.uuidString),
                "item_kind": .string("project"),
                "body": .string("project comment"),
            ]),
            context: fixture.context
        )
        let dto = try TasksToolJSON.decode(CommentDTO.self, from: addResult)
        #expect(dto.itemKind == "project")
        #expect(dto.body == "project comment")
        #expect(dto.itemID == project.id.uuidString)

        let listResult = try await CommentsListTool().call(
            args: .object([
                "item_id": .string(project.id.uuidString),
                "item_kind": .string("project"),
            ]),
            context: fixture.context
        )
        let dtos = try TasksToolJSON.decode([CommentDTO].self, from: listResult)
        #expect(dtos.count == 1)
        #expect(dtos[0].body == "project comment")
    }

    // MARK: - validation errors

    @MainActor
    @Test("add rejects empty body")
    func addRejectsEmptyBody() async throws {
        let task = TaskItem(title: "body test")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.validation("body cannot be empty")) {
            _ = try await CommentsAddTool().call(
                args: .object([
                    "item_id": .string(task.id.uuidString),
                    "item_kind": .string("task"),
                    "body": .string("   "),
                ]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("add rejects invalid item_kind")
    func addRejectsInvalidItemKind() async throws {
        let task = TaskItem(title: "kind test")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.validation("item_kind must be 'task' or 'project'")) {
            _ = try await CommentsAddTool().call(
                args: .object([
                    "item_id": .string(task.id.uuidString),
                    "item_kind": .string("meeting"),
                    "body": .string("nope"),
                ]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("edit not found throws notFound error")
    func editNotFoundThrows() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let missingID = UUID().uuidString

        await #expect(throws: AgentError.notFound("comment not found: \(missingID)")) {
            _ = try await CommentsEditTool().call(
                args: .object([
                    "id": .string(missingID),
                    "body": .string("irrelevant"),
                ]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("delete not found throws notFound error")
    func deleteNotFoundThrows() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let missingID = UUID().uuidString

        await #expect(throws: AgentError.notFound("comment not found: \(missingID)")) {
            _ = try await CommentsDeleteTool().call(
                args: .object(["id": .string(missingID)]),
                context: fixture.context
            )
        }
    }
}
