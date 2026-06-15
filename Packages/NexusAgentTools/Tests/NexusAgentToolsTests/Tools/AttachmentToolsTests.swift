import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@MainActor
struct AttachmentToolsTests {
    /// Writes a real 1x1 PNG into `dir` and returns its URL.
    private func makePNG(in dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("pixel.png")
        let bytes = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        )!
        try bytes.write(to: url)
        return url
    }

    // Both roots point at the same temp dir so the source file is in-bounds and the
    // copied bytes never touch the real app-support attachment directory.
    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test("add_to_note inserts an attachment and returns its DTO")
    func addToNote() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let note = try fixture.context.noteRepository.create(title: "Doc")
        let root = makeRoot()
        let png = try makePNG(in: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let args = JSONValue.object([
            "note_id": .string(note.id.uuidString),
            "source_path": .string(png.path),
        ])
        let result = try await AttachmentsAddToNoteTool(allowedRoot: root, storageRoot: root)
            .call(args: args, context: fixture.context)
        let dto = try TasksToolJSON.decode(AttachmentDTO.self, from: result)

        #expect(dto.contentType.hasPrefix("image/"))
        #expect(dto.byteSize > 0)
        #expect(dto.filename == "pixel.png")
    }

    @Test("add_to_note rejects a path outside the allowed root")
    func rejectsOutside() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let note = try fixture.context.noteRepository.create(title: "Doc")
        let root = makeRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let args = JSONValue.object([
            "note_id": .string(note.id.uuidString),
            "source_path": .string("/etc/hosts"),
        ])
        await #expect(throws: AgentError.self) {
            _ = try await AttachmentsAddToNoteTool(allowedRoot: root, storageRoot: root)
                .call(args: args, context: fixture.context)
        }
    }

    @Test("list then remove an attachment")
    func listAndRemove() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let note = try fixture.context.noteRepository.create(title: "Doc")
        let root = makeRoot()
        let png = try makePNG(in: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let added = try await AttachmentsAddToNoteTool(allowedRoot: root, storageRoot: root).call(
            args: .object([
                "note_id": .string(note.id.uuidString),
                "source_path": .string(png.path),
            ]),
            context: fixture.context
        )
        let dto = try TasksToolJSON.decode(AttachmentDTO.self, from: added)

        let listed = try await AttachmentsListTool().call(args: .object([:]), context: fixture.context)
        #expect((listed["attachments"]?.arrayValue ?? []).count == 1)

        _ = try await AttachmentsRemoveTool().call(
            args: .object(["attachment_id": .string(dto.id)]),
            context: fixture.context
        )

        let after = try await AttachmentsListTool().call(args: .object([:]), context: fixture.context)
        #expect((after["attachments"]?.arrayValue ?? []).isEmpty)
    }
}
