import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("PeopleTools")
struct PeopleToolsTests {
    // MARK: - people.create / get

    @MainActor
    @Test("create returns a person with the given fields")
    func createReturnsPerson() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object([
            "display_name": .string("Alice Example"),
            "aliases": .array([.string("Alice"), .string("A. Example")]),
            "email": .string("alice@example.com"),
            "company": .string("Acme"),
        ])

        let result = try await PeopleCreateTool().call(args: args, context: fixture.context)
        let dto = try TasksToolJSON.decode(PersonDTO.self, from: result)

        #expect(dto.displayName == "Alice Example")
        #expect(dto.aliases == ["Alice", "A. Example"])
        #expect(dto.email == "alice@example.com")
        #expect(dto.company == "Acme")
        #expect(dto.phone == nil)
        #expect(UUID(uuidString: dto.id) != nil)
    }

    @MainActor
    @Test("create requires display_name")
    func createRequiresDisplayName() async throws {
        let fixture = try await InMemoryAgentContext.make()
        await #expect(throws: AgentError.self) {
            _ = try await PeopleCreateTool().call(args: .object([:]), context: fixture.context)
        }
    }

    @MainActor
    @Test("get fetches a created person and 404s on unknown id")
    func getFetchesAndMisses() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let created = try await PeopleCreateTool().call(
            args: .object(["display_name": .string("Bob")]), context: fixture.context
        )
        let dto = try TasksToolJSON.decode(PersonDTO.self, from: created)

        let fetched = try await PeopleGetTool().call(
            args: .object(["id": .string(dto.id)]), context: fixture.context
        )
        #expect(try TasksToolJSON.decode(PersonDTO.self, from: fetched).displayName == "Bob")

        await #expect(throws: AgentError.self) {
            _ = try await PeopleGetTool().call(
                args: .object(["id": .string(UUID().uuidString)]), context: fixture.context
            )
        }
    }

    // MARK: - people.update (omit ≠ clear; null clears)

    @MainActor
    @Test("update leaves omitted fields untouched and clears on explicit null")
    func updateOmitVsClear() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let created = try await PeopleCreateTool().call(
            args: .object([
                "display_name": .string("Carol"),
                "email": .string("carol@example.com"),
                "phone": .string("555-0100"),
            ]),
            context: fixture.context
        )
        let id = try TasksToolJSON.decode(PersonDTO.self, from: created).id

        // Update only the company; email/phone must survive (omit ≠ clear).
        let updated = try await PeopleUpdateTool().call(
            args: .object(["id": .string(id), "company": .string("Globex")]),
            context: fixture.context
        )
        let afterFirst = try TasksToolJSON.decode(PersonDTO.self, from: updated)
        #expect(afterFirst.company == "Globex")
        #expect(afterFirst.email == "carol@example.com")
        #expect(afterFirst.phone == "555-0100")

        // Explicit null clears email; phone (omitted) stays.
        let cleared = try await PeopleUpdateTool().call(
            args: .object(["id": .string(id), "email": .null]),
            context: fixture.context
        )
        let afterClear = try TasksToolJSON.decode(PersonDTO.self, from: cleared)
        #expect(afterClear.email == nil)
        #expect(afterClear.phone == "555-0100")
    }

    // MARK: - people.create_idempotent

    @MainActor
    @Test("create_idempotent does not duplicate on the same external_source_id")
    func idempotentUpsert() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let key = "calendar-attendee:dave@example.com"

        let first = try await PeopleCreateIdempotentTool().call(
            args: .object([
                "external_source_id": .string(key),
                "display_name": .string("Dave"),
            ]),
            context: fixture.context
        )
        let firstDTO = try TasksToolJSON.decode(PersonUpsertResponseDTO.self, from: first)
        #expect(firstDTO.wasCreated)

        let second = try await PeopleCreateIdempotentTool().call(
            args: .object([
                "external_source_id": .string(key),
                "display_name": .string("Dave"),
                "company": .string("Initech"),
            ]),
            context: fixture.context
        )
        let secondDTO = try TasksToolJSON.decode(PersonUpsertResponseDTO.self, from: second)
        #expect(!secondDTO.wasCreated)
        #expect(secondDTO.person.id == firstDTO.person.id)
        #expect(secondDTO.person.company == "Initech")

        // Exactly one live person exists for the key.
        let all = try fixture.context.personRepository.allActive()
        #expect(all.filter { $0.externalSourceID == key }.count == 1)
    }

    // MARK: - people.list / search

    @MainActor
    @Test("list returns all live people; search filters by substring over name/alias/company")
    func listAndSearch() async throws {
        let fixture = try await InMemoryAgentContext.make()
        for name in ["Alice", "Bob", "Charlie"] {
            _ = try await PeopleCreateTool().call(
                args: .object(["display_name": .string(name)]), context: fixture.context
            )
        }
        _ = try await PeopleCreateTool().call(
            args: .object([
                "display_name": .string("Zoe"),
                "company": .string("Alicorn Labs"),
            ]),
            context: fixture.context
        )

        let listed = try await PeopleListTool().call(args: .object([:]), context: fixture.context)
        #expect(try TasksToolJSON.decode([PersonDTO].self, from: listed).count == 4)

        // "alic" matches Alice (name) and Zoe (company "Alicorn"), case-insensitively.
        let searched = try await PeopleSearchTool().call(
            args: .object(["query": .string("alic")]), context: fixture.context
        )
        let names = try TasksToolJSON.decode([PersonDTO].self, from: searched).map(\.displayName)
        #expect(Set(names) == ["Alice", "Zoe"])
    }

    @MainActor
    @Test("list limit is clamped into [1, max]; negative never traps prefix (A5)")
    func listLimitIsClamped() async throws {
        let fixture = try await InMemoryAgentContext.make()
        for name in ["Alice", "Bob", "Charlie"] {
            _ = try await PeopleCreateTool().call(
                args: .object(["display_name": .string(name)]), context: fixture.context
            )
        }

        // Zero clamps up to the schema minimum (1), never 0 or "all".
        let zero = try await PeopleListTool().call(
            args: .object(["limit": .int(0)]), context: fixture.context
        )
        #expect(try TasksToolJSON.decode([PersonDTO].self, from: zero).count == 1)

        // Negative must not trap `prefix(_:)`; it clamps to 1.
        let negative = try await PeopleListTool().call(
            args: .object(["limit": .int(-5)]), context: fixture.context
        )
        #expect(try TasksToolJSON.decode([PersonDTO].self, from: negative).count == 1)

        // An over-large value clamps to max and still returns everything available.
        let huge = try await PeopleListTool().call(
            args: .object(["limit": .int(9_999_999)]), context: fixture.context
        )
        #expect(try TasksToolJSON.decode([PersonDTO].self, from: huge).count == 3)
    }

    // MARK: - people.link — single-user boundary (invariant I1)

    @MainActor
    @Test("link to a meeting creates an attendee edge")
    func linkMeetingAttendee() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let person = try fixture.context.personRepository.create(displayName: "Erin")
        let meetingID = UUID()

        let result = try await PeopleLinkTool().call(
            args: .object([
                "person_id": .string(person.id.uuidString),
                "object_id": .string(meetingID.uuidString),
                "object_kind": .string("meeting"),
            ]),
            context: fixture.context
        )
        #expect(result["link_kind"]?.stringValue == LinkKind.attendee.rawValue)

        let links = try fixture.context.linkRepository.backlinks(to: (.person, person.id))
        #expect(links.count == 1)
        #expect(links.first?.linkKind == .attendee)
        #expect(links.first?.fromKind == .meeting)
    }

    @MainActor
    @Test("I1: linking a task to a person yields ONLY a mentions edge and never an assignee")
    func linkTaskIsMentionNeverAssignee() async throws {
        // A real task in the store, with no agent assignee.
        let task = TaskItem(title: "Follow up")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])
        let person = try fixture.context.personRepository.create(displayName: "Frank")

        let result = try await PeopleLinkTool().call(
            args: .object([
                "person_id": .string(person.id.uuidString),
                "object_id": .string(task.id.uuidString),
                "object_kind": .string("task"),
            ]),
            context: fixture.context
        )

        // The derived edge is a mention, never an ownership/assignee edge.
        #expect(result["link_kind"]?.stringValue == LinkKind.mentions.rawValue)
        let links = try fixture.context.linkRepository.backlinks(to: (.person, person.id))
        #expect(links.count == 1)
        #expect(links.first?.linkKind == .mentions)
        #expect(links.first?.fromKind == .task)

        // The task's agent-assignee state is completely untouched (orthogonal to Person).
        // `task` is the live persisted model instance, so reading it reflects the store.
        #expect(task.assignedAgent == nil)
        #expect(task.workflowState == nil)
    }

    @MainActor
    @Test("I1: there is no object_kind / arg that links a person as an assignee")
    func linkRejectsNonMentionableKinds() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let person = try fixture.context.personRepository.create(displayName: "Grace")

        // No "assignee", "project", or arbitrary kind is accepted — only meeting/task/note.
        for kind in ["assignee", "project", "owner", "label"] {
            await #expect(throws: AgentError.self) {
                _ = try await PeopleLinkTool().call(
                    args: .object([
                        "person_id": .string(person.id.uuidString),
                        "object_id": .string(UUID().uuidString),
                        "object_kind": .string(kind),
                    ]),
                    context: fixture.context
                )
            }
        }
    }

    @MainActor
    @Test("link is idempotent (re-linking the same pair makes no second edge)")
    func linkIsIdempotent() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let person = try fixture.context.personRepository.create(displayName: "Heidi")
        let noteID = UUID()
        let args = JSONValue.object([
            "person_id": .string(person.id.uuidString),
            "object_id": .string(noteID.uuidString),
            "object_kind": .string("note"),
        ])

        _ = try await PeopleLinkTool().call(args: args, context: fixture.context)
        _ = try await PeopleLinkTool().call(args: args, context: fixture.context)

        let links = try fixture.context.linkRepository.backlinks(to: (.person, person.id))
        #expect(links.count == 1)
        #expect(links.first?.linkKind == .mentions)
    }

    // MARK: - people.aggregate

    @MainActor
    @Test("aggregate groups meetings (attendee) and tasks/notes (mentions) by kind")
    func aggregateGroupsByKind() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let person = try fixture.context.personRepository.create(displayName: "Ivan")
        let meetingID = UUID()
        let taskID = UUID()
        let noteID = UUID()

        try fixture.context.personRepository.linkAttendee(meetingID: meetingID, personID: person.id)
        try fixture.context.personRepository.linkMention(
            source: .task, sourceID: taskID, personID: person.id
        )
        try fixture.context.personRepository.linkMention(
            source: .note, sourceID: noteID, personID: person.id
        )

        let result = try await PeopleAggregateTool().call(
            args: .object(["id": .string(person.id.uuidString)]), context: fixture.context
        )
        let dto = try TasksToolJSON.decode(PersonAggregateDTO.self, from: result)
        #expect(dto.personID == person.id.uuidString)
        #expect(dto.meetings == [meetingID.uuidString])
        #expect(dto.tasks == [taskID.uuidString])
        #expect(dto.notes == [noteID.uuidString])
    }

    // MARK: - people.merge

    @MainActor
    @Test("merge repoints edges, unions aliases, and soft-deletes the duplicate")
    func mergeRepointsAndSoftDeletes() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let canonical = try fixture.context.personRepository.create(
            displayName: "Judy", aliases: ["J."]
        )
        let duplicate = try fixture.context.personRepository.create(
            displayName: "Judy Q.", email: "judy@example.com"
        )
        let meetingID = UUID()
        try fixture.context.personRepository.linkAttendee(
            meetingID: meetingID, personID: duplicate.id
        )

        let result = try await PeopleMergeTool().call(
            args: .object([
                "into_id": .string(canonical.id.uuidString),
                "from_id": .string(duplicate.id.uuidString),
            ]),
            context: fixture.context
        )
        let dto = try TasksToolJSON.decode(PersonDTO.self, from: result)
        #expect(dto.id == canonical.id.uuidString)
        #expect(dto.email == "judy@example.com")
        #expect(dto.aliases.contains("Judy Q."))

        // The duplicate's attendee edge now points at the canonical person.
        let canonLinks = try fixture.context.linkRepository.backlinks(to: (.person, canonical.id))
        #expect(canonLinks.count == 1)
        #expect(canonLinks.first?.fromID == meetingID)

        // The duplicate is gone from the live set.
        let live = try fixture.context.personRepository.allActive()
        #expect(!live.contains { $0.id == duplicate.id })
    }

    @MainActor
    @Test("merge rejects merging a person into itself")
    func mergeRejectsSelf() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let person = try fixture.context.personRepository.create(displayName: "Karl")
        await #expect(throws: AgentError.self) {
            _ = try await PeopleMergeTool().call(
                args: .object([
                    "into_id": .string(person.id.uuidString),
                    "from_id": .string(person.id.uuidString),
                ]),
                context: fixture.context
            )
        }
    }
}
