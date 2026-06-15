import Foundation
import NexusCore
import SwiftData

/// Shared helpers for the `export.*` anti-lock-in tools (spec: Markdown export
/// must always be possible). Both tools walk live (non-soft-deleted) NexusCore
/// entities; `export.bundle` additionally needs the whole-vault `ModelContainer`.
private enum ExportSupport {
    /// The `ModelContainer` for whole-vault export, or a throwing failure when
    /// the composition root did not inject one.
    @MainActor
    static func container(_ context: AgentContext) throws -> ModelContainer {
        guard let ref = context.modelContainer else {
            throw AgentError.internalError("export unavailable: no model container")
        }
        return ref.container
    }

    /// Resolves a live `Linkable` for `export.item` and renders it to Markdown.
    /// Only NexusCore-resident kinds are reachable here: `Meeting` lives in
    /// NexusMeetings, which this NexusCore-only package cannot import, so it is
    /// not an `export.item` kind (it IS still exported by the app's own vault
    /// export, which links NexusMeetings).
    @MainActor
    static func renderMarkdown(kind: String, id: UUID, context: AgentContext) throws -> String {
        let ctx = context.modelContext.context
        switch kind {
        case "task":
            guard let item = try live(TaskItem.self, id: id, context: ctx) else {
                throw AgentError.notFound("Task not found: \(id.uuidString)")
            }
            return try MarkdownExporter.renderItem(item, context: ctx)
        case "note":
            guard let item = try context.noteRepository.find(id: id) else {
                throw AgentError.notFound("Note not found: \(id.uuidString)")
            }
            return try MarkdownExporter.renderItem(item, context: ctx)
        case "project":
            let item = try ProjectsToolSupport.liveProject(id: id, context: context)
            return try MarkdownExporter.renderItem(item, context: ctx)
        case "person":
            guard let item = try live(Person.self, id: id, context: ctx) else {
                throw AgentError.notFound("Person not found: \(id.uuidString)")
            }
            return try MarkdownExporter.renderItem(item, context: ctx)
        case "cycle":
            let item = try CyclesToolSupport.liveCycle(id: id, context: context)
            return try MarkdownExporter.renderItem(item, context: ctx)
        default:
            throw AgentError.validation("Unsupported kind '\(kind)'")
        }
    }

    @MainActor
    private static func live<L: PersistentModel & Linkable>(
        _ type: L.Type,
        id: UUID,
        context: ModelContext
    ) throws -> L? {
        try context.fetch(FetchDescriptor<L>())
            .first { $0.id == id && $0.deletedAt == nil }
    }
}

/// `export.item` — renders one NexusCore entity to Markdown text (frontmatter +
/// body + outgoing links), the single-item half of the anti-lock-in export.
public struct ExportItemTool: AgentTool {
    public let name = "export.item"
    public let description = "Exports a single entity (task, note, project, person, cycle) to Markdown text."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "kind": .string(
                enumValues: ["task", "note", "project", "person", "cycle"],
                description: "Entity kind."
            ),
            "id": .string(description: "Entity UUID."),
        ],
        required: ["kind", "id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let kind = try TasksToolArguments.requiredString(args["kind"], field: "kind")
        let id = try TasksToolArguments.requiredUUID(args["id"], field: "id")
        let markdown = try ExportSupport.renderMarkdown(kind: kind, id: id, context: context)
        return .object(["markdown": .string(markdown)])
    }
}

/// `export.bundle` — exports the vault to a Markdown bundle folder (one `.md`
/// per item) and returns the folder path plus item/link counts. The canonical
/// anti-lock-in safety valve.
public struct ExportBundleTool: AgentTool {
    public let name = "export.bundle"
    public let description = """
        Exports the vault (or selected kinds) to a Markdown bundle folder — one \
        .md per item — and returns the folder path and item count. Anti-lock-in export. \
        (v1: the kinds filter is descriptive; the canonical NexusCore type set — \
        tasks, notes, projects, people, cycles — is exported. Meeting export ships \
        through the app's own vault export.)
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "kinds": .array(
                items: .string(
                    enumValues: ["task", "note", "project", "person", "cycle"],
                    description: "Kind."
                ),
                description: """
                    Currently informational only — the full canonical set \
                    (task, note, project, person, cycle) is always exported; \
                    this filter is not yet applied.
                    """
            )
        ],
        required: []
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let container = try ExportSupport.container(context)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-export-\(UUID().uuidString)", isDirectory: true)
        let result = try await MarkdownExporter.export(
            container: container,
            types: TaskItem.self, Note.self, Project.self, Person.self, Cycle.self,
            to: folder
        )
        return .object([
            "path": .string(result.folder.path),
            "items_exported": .int(result.itemsExported),
            "links_attached": .int(result.linksAttached),
        ])
    }
}
