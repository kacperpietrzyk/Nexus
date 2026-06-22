import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("project_overview tool")
struct ProjectOverviewToolTests {

    // MARK: - Happy path

    @MainActor
    @Test("returns project metadata, tasks, notes, meetings and sections with correct counts")
    func returnsFullProjectState() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let ctx = fixture.context

        // Seed a project.
        let project = try ctx.projectRepository.create(name: "Alpha Project")

        // Seed a task in the project.
        let task = TaskItem(title: "Write spec")
        task.projectID = project.id
        ctx.modelContext.context.insert(task)
        try ctx.modelContext.context.save()

        // Seed a linked note inserted directly into the context, then link it.
        let note = Note(title: "Alpha spec note")
        ctx.modelContext.context.insert(note)
        try ctx.modelContext.context.save()
        // Link: note → project (backlink direction checked by the tool)
        try ctx.linkRepository.findOrCreate(
            from: (.note, note.id),
            to: (.project, project.id),
            linkKind: .mentions
        )

        // Seed a section.
        let sectionRepo = SectionRepository(context: ctx.modelContext.context, now: ctx.now)
        _ = try sectionRepo.create(projectID: project.id, name: "Backlog")

        // Seed a meeting link — fake UUID (Meeting lives in NexusMeetings, not in schema).
        let meetingID = UUID()
        try ctx.linkRepository.findOrCreate(
            from: (.meeting, meetingID),
            to: (.project, project.id),
            linkKind: .mentions
        )

        // Invoke the tool.
        let result = try await ProjectOverviewTool().call(
            args: .object(["project_id": .string(project.id.uuidString)]),
            context: ctx
        )

        // --- Project metadata ---
        let projectNode = try #require(result["project"])
        #expect(projectNode["name"]?.stringValue == "Alpha Project")
        #expect(projectNode["id"]?.stringValue == project.id.uuidString)

        // --- Tasks ---
        let tasksNode = try #require(result["tasks"])
        #expect(tasksNode["count"]?.intValue == 1)
        let taskItems = try #require(tasksNode["items"]?.arrayValue)
        #expect(taskItems.count == 1)
        #expect(taskItems.first?["title"]?.stringValue == "Write spec")

        // --- Notes ---
        let notesNode = try #require(result["notes"])
        #expect(notesNode["count"]?.intValue == 1)
        let noteItems = try #require(notesNode["items"]?.arrayValue)
        #expect(noteItems.count == 1)
        #expect(noteItems.first?["id"]?.stringValue == note.id.uuidString)
        #expect(noteItems.first?["title"]?.stringValue == "Alpha spec note")

        // --- Meetings (IDs only) ---
        let meetingsNode = try #require(result["meetings"])
        #expect(meetingsNode["count"]?.intValue == 1)
        let meetingItems = try #require(meetingsNode["items"]?.arrayValue)
        #expect(meetingItems.count == 1)
        #expect(meetingItems.first?["id"]?.stringValue == meetingID.uuidString)

        // --- Sections ---
        let sectionsNode = try #require(result["sections"])
        #expect(sectionsNode["count"]?.intValue == 1)
        let sectionItems = try #require(sectionsNode["items"]?.arrayValue)
        #expect(sectionItems.count == 1)
        #expect(sectionItems.first?["name"]?.stringValue == "Backlog")
    }

    // MARK: - notFound

    @MainActor
    @Test("throws notFound for unknown project_id")
    func throwsNotFoundForUnknownProject() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.self) {
            _ = try await ProjectOverviewTool().call(
                args: .object(["project_id": .string(UUID().uuidString)]),
                context: fixture.context
            )
        }
    }

    // MARK: - Canonical note ref appears as is_canonical

    @MainActor
    @Test("canonical note ref is flagged with is_canonical = true")
    func canonicalNoteFlagged() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let ctx = fixture.context

        let project = try ctx.projectRepository.create(name: "Canon Project")

        // Set a canonical note directly on the project model.
        let canonicalNote = Note(title: "Project page")
        ctx.modelContext.context.insert(canonicalNote)
        try ctx.modelContext.context.save()
        project.canonicalNoteRef = canonicalNote.id
        try ctx.modelContext.context.save()

        let result = try await ProjectOverviewTool().call(
            args: .object(["project_id": .string(project.id.uuidString)]),
            context: ctx
        )

        let noteItems = try #require(result["notes"]?["items"]?.arrayValue)
        let canonItem = try #require(noteItems.first { $0["id"]?.stringValue == canonicalNote.id.uuidString })
        #expect(canonItem["is_canonical"]?.boolValue ?? false)
    }

    // MARK: - Empty project returns zeros

    @MainActor
    @Test("empty project returns zero counts on all collections")
    func emptyProjectReturnsZeroCounts() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = try fixture.context.projectRepository.create(name: "Empty")

        let result = try await ProjectOverviewTool().call(
            args: .object(["project_id": .string(project.id.uuidString)]),
            context: fixture.context
        )

        #expect(result["tasks"]?["count"]?.intValue ?? -1 == 0)
        #expect(result["notes"]?["count"]?.intValue ?? -1 == 0)
        #expect(result["meetings"]?["count"]?.intValue ?? -1 == 0)
        #expect(result["sections"]?["count"]?.intValue ?? -1 == 0)
    }
}
