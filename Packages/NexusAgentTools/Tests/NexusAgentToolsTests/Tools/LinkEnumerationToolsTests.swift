import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@MainActor
struct LinkEnumerationToolsTests {
    @Test("backlinks returns incoming edges to the endpoint")
    func backlinks() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let note = UUID()
        let task = UUID()
        _ = try fixture.context.linkRepository.findOrCreate(
            from: (.task, task),
            to: (.note, note),
            linkKind: .mentions
        )
        let args = JSONValue.object([
            "endpoint_id": .string(note.uuidString),
            "endpoint_kind": .string("note"),
        ])
        let result = try await LinksBacklinksTool().call(args: args, context: fixture.context)
        let dtos = try TasksToolJSON.decode([LinkDTO].self, from: result["links"]!)
        #expect(dtos.count == 1)
        #expect(dtos.first?.fromID == task.uuidString)
        #expect(dtos.first?.toID == note.uuidString)
    }

    @Test("invalid endpoint_kind is a validation error")
    func invalidKind() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object([
            "endpoint_id": .string(UUID().uuidString),
            "endpoint_kind": .string("banana"),
        ])
        await #expect(throws: AgentError.self) {
            _ = try await LinksBacklinksTool().call(args: args, context: fixture.context)
        }
    }

    @Test("list truncates to the given limit")
    func listTruncates() async throws {
        let fixture = try await InMemoryAgentContext.make()
        for _ in 0..<3 {
            _ = try fixture.context.linkRepository.findOrCreate(
                from: (.task, UUID()), to: (.note, UUID()), linkKind: .mentions
            )
        }
        let args = JSONValue.object(["limit": .int(2)])
        let result = try await LinksListTool().call(args: args, context: fixture.context)
        let dtos = try TasksToolJSON.decode([LinkDTO].self, from: result["links"]!)
        #expect(dtos.count == 2)
    }

    // MARK: - links.reclassify_project_membership backfill tests

    @Test("reclassify converts note→project and meeting→project child edges to relatedProject")
    func reclassifyNoteAndMeetingChildEdges() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let modelContext = fixture.context.modelContext.context
        let projectID = UUID()

        // Insert a note→project child edge (wrong kind — should be relatedProject).
        let noteLink = Link(from: (.note, UUID()), to: (.project, projectID), linkKind: .child)
        // Insert a meeting→project child edge (wrong kind — should be relatedProject).
        let meetingLink = Link(from: (.meeting, UUID()), to: (.project, projectID), linkKind: .child)
        modelContext.insert(noteLink)
        modelContext.insert(meetingLink)
        try modelContext.save()

        let result = try await LinksReclassifyProjectMembershipTool().call(
            args: .object([:]),
            context: fixture.context
        )
        #expect(result["reclassified_count"] == .int(2))

        // Both edges are now relatedProject.
        #expect(noteLink.linkKind == .relatedProject)
        #expect(meetingLink.linkKind == .relatedProject)
    }

    @Test("reclassify leaves task→task child edges untouched")
    func reclassifyLeavesTaskChildUntouched() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let modelContext = fixture.context.modelContext.context

        // A task→task child edge — must NEVER be touched.
        let taskLink = Link(from: (.task, UUID()), to: (.task, UUID()), linkKind: .child)
        modelContext.insert(taskLink)
        try modelContext.save()

        let result = try await LinksReclassifyProjectMembershipTool().call(
            args: .object([:]),
            context: fixture.context
        )
        #expect(result["reclassified_count"] == .int(0))
        #expect(taskLink.linkKind == .child)
    }

    @Test("reclassify leaves existing relatedProject edges untouched")
    func reclassifyLeavesAlreadyCorrectEdgeUntouched() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let modelContext = fixture.context.modelContext.context

        // Already correctly classified — must not be counted.
        let correctLink = Link(from: (.note, UUID()), to: (.project, UUID()), linkKind: .relatedProject)
        modelContext.insert(correctLink)
        try modelContext.save()

        let result = try await LinksReclassifyProjectMembershipTool().call(
            args: .object([:]),
            context: fixture.context
        )
        #expect(result["reclassified_count"] == .int(0))
        #expect(correctLink.linkKind == .relatedProject)
    }

    @Test("reclassify is idempotent — second run returns reclassified_count 0")
    func reclassifyIsIdempotent() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let modelContext = fixture.context.modelContext.context

        let noteLink = Link(from: (.note, UUID()), to: (.project, UUID()), linkKind: .child)
        modelContext.insert(noteLink)
        try modelContext.save()

        let first = try await LinksReclassifyProjectMembershipTool().call(
            args: .object([:]),
            context: fixture.context
        )
        #expect(first["reclassified_count"] == .int(1))

        // Second run — no wrongly-classified edges remain.
        let second = try await LinksReclassifyProjectMembershipTool().call(
            args: .object([:]),
            context: fixture.context
        )
        #expect(second["reclassified_count"] == .int(0))
    }

    @Test("reclassify respects project_id scope — only reclassifies edges to that project")
    func reclassifyRespectsProjectIDScope() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let modelContext = fixture.context.modelContext.context
        let targetProjectID = UUID()
        let otherProjectID = UUID()

        // Two wrong edges: one to targetProject, one to otherProject.
        let targetLink = Link(from: (.note, UUID()), to: (.project, targetProjectID), linkKind: .child)
        let otherLink = Link(from: (.note, UUID()), to: (.project, otherProjectID), linkKind: .child)
        modelContext.insert(targetLink)
        modelContext.insert(otherLink)
        try modelContext.save()

        // Scope to targetProject only.
        let result = try await LinksReclassifyProjectMembershipTool().call(
            args: .object(["project_id": .string(targetProjectID.uuidString)]),
            context: fixture.context
        )
        #expect(result["reclassified_count"] == .int(1))
        #expect(targetLink.linkKind == .relatedProject)
        // The other project's edge is untouched.
        #expect(otherLink.linkKind == .child)
    }
}
