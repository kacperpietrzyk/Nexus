import Foundation
import SwiftData
import Testing

@testable import NexusAgentTools
@testable import NexusCore

@Suite("export tools")
struct ExportToolsTests {
    @Test("export.item returns markdown for a task")
    @MainActor
    func exportItem() async throws {
        let task = TaskItem(title: "Write the report")
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        let out = try await ExportItemTool().call(
            args: .object(["kind": .string("task"), "id": .string(task.id.uuidString)]),
            context: context
        )
        #expect(out["markdown"]?.stringValue?.contains("Write the report") == true)
        _ = container
    }

    /// `export.item` covers every reachable kind, each going through a different
    /// lookup helper (direct fetch / NoteRepository / ProjectsToolSupport /
    /// CyclesToolSupport). One insert per kind, asserting the rendered Markdown
    /// carries that item's identifying title.
    @Test(
        "export.item renders each kind via its lookup helper",
        arguments: ["note", "project", "person", "cycle"]
    )
    @MainActor
    func exportItemPerKind(kind: String) async throws {
        let (context, _, _) = try await InMemoryAgentContext.make()
        let modelContext = context.modelContext.context

        let id: UUID
        let marker: String
        switch kind {
        case "note":
            let note = Note(title: "Exported note marker")
            modelContext.insert(note)
            id = note.id
            marker = "Exported note marker"
        case "project":
            let project = Project(name: "Exported project marker")
            modelContext.insert(project)
            id = project.id
            marker = "Exported project marker"
        case "person":
            let person = Person(displayName: "Exported person marker")
            modelContext.insert(person)
            id = person.id
            marker = "Exported person marker"
        case "cycle":
            let cycle = Cycle(
                name: "Exported cycle marker",
                startAt: Date(timeIntervalSince1970: 1_700_000_000),
                endAt: Date(timeIntervalSince1970: 1_700_600_000)
            )
            modelContext.insert(cycle)
            id = cycle.id
            marker = "Exported cycle marker"
        default:
            Issue.record("unhandled kind \(kind)")
            return
        }
        try modelContext.save()

        let out = try await ExportItemTool().call(
            args: .object(["kind": .string(kind), "id": .string(id.uuidString)]),
            context: context
        )
        #expect(out["markdown"]?.stringValue?.contains(marker) == true)
    }

    @Test("export.item rejects an unknown id")
    @MainActor
    func exportItemNotFound() async throws {
        let (context, _, _) = try await InMemoryAgentContext.make()
        await #expect(throws: AgentError.self) {
            _ = try await ExportItemTool().call(
                args: .object(["kind": .string("task"), "id": .string(UUID().uuidString)]),
                context: context
            )
        }
    }

    @Test("export.bundle writes a folder and reports a count")
    @MainActor
    func exportBundle() async throws {
        let task = TaskItem(title: "Bundled task")
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        _ = container
        let out = try await ExportBundleTool().call(args: .object([:]), context: context)
        #expect((out["items_exported"]?.intValue ?? 0) >= 1)
        // No links were inserted, so the bundle reports zero attached edges —
        // assert the key is present and accurate, not merely non-nil.
        #expect(out["links_attached"]?.intValue == 0)
        #expect(out["path"]?.stringValue != nil)
        if let path = out["path"]?.stringValue {
            #expect(FileManager.default.fileExists(atPath: path))
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    @Test("export.bundle throws when no container is wired")
    @MainActor
    func exportBundleNoContainer() async throws {
        let (base, _, _) = try await InMemoryAgentContext.make()
        let context = AgentContext(
            modelContext: base.modelContext,
            taskRepository: base.taskRepository,
            searchIndex: base.searchIndex,
            now: base.now,
            modelContainer: nil
        )
        await #expect(throws: AgentError.self) {
            _ = try await ExportBundleTool().call(args: .object([:]), context: context)
        }
    }
}
