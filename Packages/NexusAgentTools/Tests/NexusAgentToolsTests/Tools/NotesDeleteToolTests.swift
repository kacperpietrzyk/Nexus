import Foundation
import SwiftData
import Testing

@testable import NexusAgentTools
@testable import NexusCore

@Suite("note.delete")
struct NotesDeleteToolTests {
    @Test("deletes a live note and reports its id")
    @MainActor
    func deletesNote() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let note = try context.noteRepository.create(title: "Scratch", blocks: [])
        let out = try await NotesDeleteTool().call(
            args: .object(["note_id": .string(note.id.uuidString)]), context: context
        )
        #expect(out["id"]?.stringValue == note.id.uuidString)
        #expect(out["deleted"]?.boolValue == true)
        #expect(try context.noteRepository.find(id: note.id) == nil)
    }

    @Test("throws notFound for an unknown note id")
    @MainActor
    func unknownNote() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        await #expect(throws: AgentError.self) {
            _ = try await NotesDeleteTool().call(
                args: .object(["note_id": .string(UUID().uuidString)]), context: context
            )
        }
    }
}
