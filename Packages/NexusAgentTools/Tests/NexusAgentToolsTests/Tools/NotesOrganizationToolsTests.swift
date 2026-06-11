import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("NotesTools properties + folders (Tranche 2 Plan E)")
struct NotesOrganizationToolsTests {
    @MainActor
    @Test("create persists folder (normalized) and ordered properties, echoed in the DTO")
    func createWithFolderAndProperties() async throws {
        let fixture = try await InMemoryAgentContext.make()

        let result = try await NotesCreateTool().call(
            args: .object([
                "title": .string("Organized"),
                "folder": .string("/projects//nexus/"),
                "properties": .array([
                    .object(["key": .string("status"), "value": .string("active")]),
                    .object(["key": .string("priority"), "value": .int(2)]),
                    .object(["key": .string("pinned"), "value": .bool(true)]),
                    .object(["key": .string("colors"), "value": .array([.string("red"), .string("blue")])]),
                ]),
            ]),
            context: fixture.context
        )
        let dto = try TasksToolJSON.decode(NoteDTO.self, from: result)

        #expect(dto.folder == "projects/nexus")
        #expect(dto.properties.map(\.key) == ["status", "priority", "pinned", "colors"])
        #expect(dto.properties[0].value == .string("active"))
        // Integral numbers ride the wire as .int (deterministic JSON round-trip).
        #expect(dto.properties[1].value == .int(2))
        #expect(dto.properties[2].value == .bool(true))
        #expect(dto.properties[3].value == .array([.string("red"), .string("blue")]))

        let id = try #require(UUID(uuidString: dto.id))
        let note = try #require(try fixture.context.noteRepository.find(id: id))
        #expect(note.folderPath == "projects/nexus")
        #expect(note.properties.map(\.key) == ["status", "priority", "pinned", "colors"])
    }

    @MainActor
    @Test("update sets folder, replaces properties; null folder clears to root; omit leaves untouched")
    func updateFolderAndProperties() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let created = try await NotesCreateTool().call(
            args: .object(["title": .string("n")]),
            context: fixture.context
        )
        let id = try TasksToolJSON.decode(NoteDTO.self, from: created).id

        // Set both.
        var updated = try await NotesUpdateTool().call(
            args: .object([
                "id": .string(id),
                "folder": .string("area/sub"),
                "properties": .array([
                    .object(["key": .string("k"), "value": .string("v")])
                ]),
            ]),
            context: fixture.context
        )
        var dto = try TasksToolJSON.decode(NoteDTO.self, from: updated)
        #expect(dto.folder == "area/sub")
        #expect(dto.properties.map(\.key) == ["k"])

        // Omit both → untouched.
        updated = try await NotesUpdateTool().call(
            args: .object(["id": .string(id), "title": .string("renamed")]),
            context: fixture.context
        )
        dto = try TasksToolJSON.decode(NoteDTO.self, from: updated)
        #expect(dto.folder == "area/sub")
        #expect(dto.properties.map(\.key) == ["k"])

        // null folder → root; empty properties → cleared.
        updated = try await NotesUpdateTool().call(
            args: .object([
                "id": .string(id),
                "folder": .null,
                "properties": .array([]),
            ]),
            context: fixture.context
        )
        dto = try TasksToolJSON.decode(NoteDTO.self, from: updated)
        #expect(dto.folder == nil)
        #expect(dto.properties.isEmpty)
    }

    @MainActor
    @Test("invalid property values are rejected with a validation error")
    func invalidPropertyValue() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.self) {
            _ = try await NotesCreateTool().call(
                args: .object([
                    "properties": .array([
                        .object(["key": .string("bad"), "value": .object([:])])
                    ])
                ]),
                context: fixture.context
            )
        }
        await #expect(throws: AgentError.self) {
            _ = try await NotesCreateTool().call(
                args: .object([
                    "properties": .array([.object(["value": .string("missing key")])])
                ]),
                context: fixture.context
            )
        }
    }
}
