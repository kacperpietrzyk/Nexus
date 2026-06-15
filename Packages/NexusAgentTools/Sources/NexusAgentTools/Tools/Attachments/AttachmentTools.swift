import Foundation
import NexusCore
import SwiftData

// TODO: hoist this shared attachment-root computation into NexusCore so the editor and
// the agent tools share one source of truth instead of duplicating the path.
//
/// Canonical on-disk root the app copies attachment bytes into. MUST match
/// `NotesFeature.NoteAttachmentRoot` (`<applicationSupport>/Nexus/Attachments`) so a
/// note image block written by `attachments.add_to_note` resolves to the same file the
/// in-app editor renders. `NotesFeature` is a sibling feature module the agent-tools
/// layer cannot import, so the computation is replicated here.
enum AttachmentStorageRoot {
    static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("Nexus/Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

/// `attachments.add_to_note` — ingest a local image file (path / `file://` URL) and
/// append it to a note as an image block. The bytes are read and copied by the app
/// (path handoff, no base64). The security boundary lives in `AttachmentIngestPolicy`:
/// the source must be an absolute, in-allow-root path; size + image-only type are then
/// enforced by `AttachmentImportService`.
public struct AttachmentsAddToNoteTool: AgentTool {
    public let name = "attachments.add_to_note"
    public let description =
        "Attach a local image file (absolute path / file:// URL) to a note as an image block."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "note_id": .string(description: "Note UUID."),
            "source_path": .string(description: "Absolute path or file:// URL to the image on disk."),
            "after_block_id": .string(description: "Optional block UUID to insert the image after."),
        ],
        required: ["note_id", "source_path"]
    )

    private let allowedRoot: URL
    private let storageRoot: URL?

    /// - Parameters:
    ///   - allowedRoot: ingest allow-list root the `source_path` must live under
    ///     (defaults to the user's home directory for v1).
    ///   - storageRoot: where copied bytes are written. `nil` resolves to the
    ///     production app-support attachment root at call time (matches the editor).
    public init(
        allowedRoot: URL = Self.defaultAllowedRoot,
        storageRoot: URL? = nil
    ) {
        self.allowedRoot = allowedRoot
        self.storageRoot = storageRoot
    }

    /// `homeDirectoryForCurrentUser` is macOS-only; on iOS the sandbox home
    /// (`NSHomeDirectory()`) is the equivalent ingest allow-list root for v1.
    public static var defaultAllowedRoot: URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
        #else
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #endif
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let noteID = try TasksToolArguments.requiredUUID(args["note_id"], field: "note_id")
        let sourcePath = try TasksToolArguments.requiredString(args["source_path"], field: "source_path")

        let source = try AttachmentIngestPolicy.resolve(source: sourcePath, allowedRoot: allowedRoot)
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        try AttachmentIngestPolicy.validateSize((attributes[.size] as? Int) ?? 0)

        let ctx = context.modelContext.context
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == noteID })
        guard let note = try ctx.fetch(descriptor).first, note.deletedAt == nil else {
            throw AgentError.notFound("Note not found: \(noteID.uuidString)")
        }

        let root = try storageRoot ?? AttachmentStorageRoot.defaultURL()
        let storage = AttachmentImportService(root: root)
        let imported = try storage.importImage(from: source)

        let afterID = args["after_block_id"]?.stringValue.flatMap(UUID.init(uuidString:))
        do {
            let asset = try context.noteRepository.insertImageAttachment(imported, into: note, after: afterID)
            return try TasksToolJSON.encode(AttachmentDTO(from: asset))
        } catch {
            // Roll back the copied file if the metadata insert fails (mirrors the
            // editor's `NoteImageImporter` cleanup).
            storage.removeImportedFile(at: imported.storagePath)
            throw error
        }
    }
}

/// `attachments.list` — non-deleted attachment assets, newest first.
public struct AttachmentsListTool: AgentTool {
    public let name = "attachments.list"
    public let description = "List attachment assets (id, filename, content type, size), newest first."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "limit": .integer(minimum: 1, maximum: 500, description: "Max assets to return (default 100).")
        ],
        required: []
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let limit = try TasksToolArguments.boundedInt(
            args["limit"],
            field: "limit",
            default: 100,
            range: 1...500
        )
        let ctx = context.modelContext.context
        let assets = try ctx.fetch(FetchDescriptor<AttachmentAsset>())
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
        return try .object(["attachments": TasksToolJSON.encode(assets.map(AttachmentDTO.init(from:)))])
    }
}

/// `attachments.remove` — soft-delete an attachment asset by UUID.
public struct AttachmentsRemoveTool: AgentTool {
    public let name = "attachments.remove"
    public let description =
        "Soft-delete an attachment asset by UUID. Hides the asset record only; "
        + "the on-disk file and any note image block remain."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "attachment_id": .string(description: "AttachmentAsset UUID.")
        ],
        required: ["attachment_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["attachment_id"], field: "attachment_id")
        let repository = AttachmentAssetRepository(context: context.modelContext.context, now: context.now)
        guard let asset = try repository.find(id: id) else {
            throw AgentError.notFound("Attachment not found: \(id.uuidString)")
        }
        try repository.softDelete(asset)
        return .object(["success": .bool(true)])
    }
}
