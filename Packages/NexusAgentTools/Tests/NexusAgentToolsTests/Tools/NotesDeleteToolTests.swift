import Foundation
import SwiftData
import Testing

@testable import NexusAgentTools
@testable import NexusCore

@Suite("note.delete")
struct NotesDeleteToolTests {
    @Test("deletes a live note, reports its id, and removes it from the search index")
    @MainActor
    func deletesNote() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let note = try context.noteRepository.create(title: "Scratch", blocks: [])
        // Mirror the real lifecycle: a live note is indexed (as NotesCreateTool does)
        // so the delete tool's index teardown has something to remove.
        await context.searchIndex.upsert(IndexedDocument(note))
        let beforeCount = await context.searchIndex.documentCount
        #expect(beforeCount == 1)

        let out = try await NotesDeleteTool().call(
            args: .object(["note_id": .string(note.id.uuidString)]), context: context
        )
        #expect(out["id"]?.stringValue == note.id.uuidString)
        #expect(out["deleted"]?.boolValue == true)
        #expect(try context.noteRepository.find(id: note.id) == nil)
        // The index entry is gone — note.search bypasses the index, so this must
        // assert against the index directly to catch a missing teardown.
        let afterCount = await context.searchIndex.documentCount
        #expect(afterCount == 0)
    }

    @Test("throws notFound for an unknown note id")
    @MainActor
    func unknownNote() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let id = UUID()
        await #expect(throws: AgentError.notFound("Note not found: \(id.uuidString)")) {
            _ = try await NotesDeleteTool().call(
                args: .object(["note_id": .string(id.uuidString)]), context: context
            )
        }
    }
}
