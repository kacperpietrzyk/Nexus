import Foundation
import NexusCore
import SwiftData

// MARK: - note.create

/// Create a free-standing note (or a typed note via `role`) from a markdown / html
/// body. All writes go through `MarkdownBlockParser` → `NoteRepository` →
/// `NoteReconciler`, so a `- [ ]` line becomes a real `TaskItem` + `containsTask`
/// Link, a `[[title]]` becomes a wikilink, etc. — identical invariants to UI edits.
public struct NotesCreateTool: AgentTool {
    public let name = "note.create"
    public let description =
        "Creates a note from a markdown (default) or html body. Title, role, and tags are optional. "
        + "Returns the created note. Checkboxes, wikilinks, and embeds in the body are reconciled into "
        + "the graph exactly as in the UI editor."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "title": .string(description: "Note title."),
            "role": .string(
                enumValues: NoteRole.allCases.map(\.rawValue),
                description: "Note role: free (default) | projectPage | dailyNote."
            ),
            "tags": .array(items: .string(description: "Tag"), description: "Optional flat tags."),
        ].merging(NotesToolSupport.bodyProperties) { current, _ in current },
        required: []
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let parsedBody = try NotesToolSupport.parsedBody(fromBodyIn: args)
        let title =
            try NotesToolSupport.optionalString(args["title"], field: "title")
            ?? parsedBody?.frontmatter?.title
            ?? ""
        let role =
            try NotesToolSupport.role(args["role"])
            ?? parsedBody?.frontmatter?.role
            ?? .free
        let tags =
            try NotesToolSupport.tags(args["tags"])
            ?? parsedBody?.frontmatter?.tags
            ?? []
        let blocks = parsedBody?.blocks ?? []

        let repo = context.noteRepository
        let note = try repo.create(title: title, blocks: blocks, role: role, tags: tags)
        try restoreFrontmatterLinks(parsedBody?.frontmatter?.links ?? [], from: note, context: context)
        await context.searchIndex.upsert(IndexedDocument(note))
        return try TasksToolJSON.encode(try NoteDTO(from: note, format: .markdown))
    }

    @MainActor
    private func restoreFrontmatterLinks(
        _ links: [MarkdownDocument.LinkRef],
        from note: Note,
        context: AgentContext
    ) throws {
        guard links.isEmpty == false else { return }
        let repository = LinkRepository(context: context.modelContext.context)
        for link in links where NotesLinkTool.reconcilerOwnedKinds.contains(link.linkKind) == false {
            try repository.findOrCreate(
                from: (.note, note.id),
                to: (link.toKind, link.toID),
                linkKind: link.linkKind
            )
        }
    }
}

// MARK: - note.update

/// Update a note's body, title, and/or tags. Omitted fields are left untouched
/// (omit ≠ clear). A body update replaces the whole content blob and re-reconciles.
public struct NotesUpdateTool: AgentTool {
    public let name = "note.update"
    public let description =
        "Updates a note's body (markdown/html), title, and/or tags by id. Omitted fields are left "
        + "unchanged. Returns the updated note."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "id": .string(description: "Note UUID to update."),
            "title": .string(description: "New title."),
            "tags": .array(items: .string(description: "Tag"), description: "Replacement tags."),
        ].merging(NotesToolSupport.bodyProperties) { current, _ in current },
        required: ["id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try NotesToolSupport.requiredUUID(args["id"], field: "id")
        let repo = context.noteRepository
        guard let note = try repo.find(id: id) else {
            throw AgentError.notFound("Note not found: \(id.uuidString)")
        }

        let title = try NotesToolSupport.optionalString(args["title"], field: "title")
        let tags = try NotesToolSupport.tags(args["tags"])
        if title != nil || tags != nil {
            try repo.updateFields(note, title: title, tags: tags)
        }

        if let blocks = try NotesToolSupport.blocks(fromBodyIn: args) {
            try repo.updateContent(note, blocks: blocks)
        }

        await context.searchIndex.upsert(IndexedDocument(note))
        return try TasksToolJSON.encode(try NoteDTO(from: note, format: .markdown))
    }
}

// MARK: - note.get

/// Fetch one note, rendering its content into the requested format
/// (markdown | html | plain).
public struct NotesGetTool: AgentTool {
    public let name = "note.get"
    public let description = "Fetches one note by id, rendering content as markdown (default), html, or plain."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "id": .string(description: "Note UUID to fetch."),
            "format": .string(
                enumValues: NoteContentFormat.allCases.map(\.rawValue),
                description: "Output content format: markdown (default) | html | plain."
            ),
        ],
        required: ["id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try NotesToolSupport.requiredUUID(args["id"], field: "id")
        let format = try NotesToolSupport.readFormat(args["format"])
        guard let note = try context.noteRepository.find(id: id) else {
            throw AgentError.notFound("Note not found: \(id.uuidString)")
        }
        return try TasksToolJSON.encode(try NoteDTO(from: note, format: format))
    }
}

// MARK: - note.list

/// List notes, optionally filtered by `role` and/or `tags` (ALL of the given tags
/// must be present). Newest-updated first. Bodies are returned as `plain` (the cache)
/// so a list call never decodes every blob.
public struct NotesListTool: AgentTool {
    public let name = "note.list"
    public let description =
        "Lists notes, newest first, optionally filtered by role and/or tags (all given tags must match). "
        + "Bodies are returned as plain text."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "role": .string(
                enumValues: NoteRole.allCases.map(\.rawValue),
                description: "Filter by role: free | projectPage | dailyNote."
            ),
            "tags": .array(items: .string(description: "Tag"), description: "Require ALL of these tags."),
            "limit": .integer(minimum: 1, maximum: 500, description: "Max results (default 50)."),
        ],
        required: []
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let role = try NotesToolSupport.role(args["role"])
        let requiredTags = try NotesToolSupport.tags(args["tags"]) ?? []
        let limit = AgentToolArgs.limit(args, default: 50, max: 500)

        let notes = try NotesQuery.fetch(
            context: context.modelContext.context,
            role: role,
            requiredTags: requiredTags,
            plainTextContains: nil,
            limit: limit
        )
        let dtos = try notes.map { try NoteDTO(from: $0, format: .plain) }
        return try TasksToolJSON.encode(dtos)
    }
}

// MARK: - note.search

/// Full-text search over the denormalized `plainText` cache (+ title), optionally
/// narrowed by role/tags. Matches the search facet without forcing the global
/// `SearchIndex` dependency into the tool layer.
public struct NotesSearchTool: AgentTool {
    public let name = "note.search"
    public let description =
        "Searches notes by text over title + plain content, optionally narrowed by role and tags. "
        + "Bodies are returned as plain text, newest first."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "query": .string(description: "Case-insensitive substring to find in the title or plain content."),
            "role": .string(
                enumValues: NoteRole.allCases.map(\.rawValue),
                description: "Filter by role: free | projectPage | dailyNote."
            ),
            "tags": .array(items: .string(description: "Tag"), description: "Require ALL of these tags."),
            "limit": .integer(minimum: 1, maximum: 500, description: "Max results (default 50)."),
        ],
        required: ["query"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        guard let query = args["query"]?.stringValue else {
            throw AgentError.validation("Missing required string field: query")
        }
        let role = try NotesToolSupport.role(args["role"])
        let requiredTags = try NotesToolSupport.tags(args["tags"]) ?? []
        let limit = AgentToolArgs.limit(args, default: 50, max: 500)

        let notes = try NotesQuery.fetch(
            context: context.modelContext.context,
            role: role,
            requiredTags: requiredTags,
            plainTextContains: query,
            limit: limit
        )
        let dtos = try notes.map { try NoteDTO(from: $0, format: .plain) }
        return try TasksToolJSON.encode(dtos)
    }
}

// MARK: - note.link

/// Create an explicit graph edge from a note to another item.
///
/// ## Why this rejects reconciler-owned kinds
/// `NoteReconciler` derives `containsTask` / `embed` / `mentions` edges from the
/// note's block content and **prunes any of those kinds that the blob does not
/// imply** on every reconcile + recompute-on-load (NoteReconciler `reconcileLinks`).
/// A freestanding `note.link` of one of those kinds would therefore silently vanish
/// on the next load. So those relationships must live in the body (a `- [ ]` todo, an
/// `![[id]]` embed, a `[[title]]` wikilink) — `note.update` is the right path for
/// them. `note.link` covers the kinds the reconciler does not own
/// (`source`, `actionItem`, `blocks`, `child`, `attachment`), which survive reconcile.
public struct NotesLinkTool: AgentTool {
    public let name = "note.link"
    public let description =
        "Creates an explicit graph link from a note to a target item. For checkbox→task, embed, or "
        + "wikilink relationships, put them in the note body via note.update instead (those are derived "
        + "from content). Idempotent."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "note_id": .string(description: "Source note UUID."),
            "target_id": .string(description: "Target item UUID."),
            "target_kind": .string(
                enumValues: ItemKind.allCases.map(\.rawValue),
                description: "Target item kind, e.g. task | project | note | meeting."
            ),
            "kind": .string(
                enumValues: NotesLinkTool.allowedKinds.map(\.rawValue),
                description: "Link relationship kind. Content-derived kinds (containsTask/embed/mentions) "
                    + "are rejected — express those in the note body."
            ),
        ],
        required: ["note_id", "target_id", "target_kind", "kind"]
    )

    /// Kinds the reconciler does NOT own, so a freestanding link survives reconcile.
    static let allowedKinds: [LinkKind] = LinkKind.allCases.filter {
        !reconcilerOwnedKinds.contains($0)
    }
    static let reconcilerOwnedKinds: Set<LinkKind> = [.containsTask, .embed, .mentions]

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let noteID = try NotesToolSupport.requiredUUID(args["note_id"], field: "note_id")
        let targetID = try NotesToolSupport.requiredUUID(args["target_id"], field: "target_id")
        guard let kindText = args["target_kind"]?.stringValue, let targetKind = ItemKind(rawValue: kindText)
        else {
            throw AgentError.validation("target_kind must be a valid ItemKind")
        }
        guard let linkText = args["kind"]?.stringValue, let linkKind = LinkKind(rawValue: linkText) else {
            throw AgentError.validation("kind must be a valid LinkKind")
        }
        guard !Self.reconcilerOwnedKinds.contains(linkKind) else {
            throw AgentError.validation(
                "kind '\(linkKind.rawValue)' is derived from note content (the reconciler manages it and "
                    + "would prune a freestanding link). Express it in the note body via note.update instead."
            )
        }

        let modelContext = context.modelContext.context
        guard try context.noteRepository.find(id: noteID) != nil else {
            throw AgentError.notFound("Note not found: \(noteID.uuidString)")
        }
        try AgentEndpointValidator.validateLive(targetKind, targetID, context: context)

        let repository = LinkRepository(context: modelContext)
        let link = try repository.findOrCreate(
            from: (.note, noteID),
            to: (targetKind, targetID),
            linkKind: linkKind
        )

        return .object([
            "status": .string("ok"),
            "link_id": .string(link.id.uuidString),
            "idempotency_key": .string(link.idempotencyKey),
        ])
    }
}

// MARK: - Query helper

/// In-tool `Note` fetch with role / tag / plain-text filters. Kept dependency-free
/// (a direct `FetchDescriptor<Note>` over the tool's `ModelContext`) rather than
/// routing through the global `SearchIndex`, which is search-foundation wiring, not
/// tool scope. Single-user scale makes the in-memory tag/substring refinement fine.
enum NotesQuery {
    @MainActor
    static func fetch(
        context: ModelContext,
        role: NoteRole?,
        requiredTags: [String],
        plainTextContains: String?,
        limit: Int
    ) throws -> [Note] {
        var descriptor = FetchDescriptor<Note>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        // #Predicate can't capture the enum (`role`) or do case-insensitive contains
        // reliably across stores, so fetch live notes sorted, then refine in-memory.
        descriptor.predicate = #Predicate { $0.deletedAt == nil }

        let needle = plainTextContains?.lowercased()
        var results: [Note] = []
        for note in try context.fetch(descriptor) {
            if let role, note.role != role { continue }
            if !requiredTags.isEmpty {
                let tagSet = Set(note.tags)
                guard requiredTags.allSatisfy(tagSet.contains) else { continue }
            }
            if let needle {
                let haystack = (note.title + "\n" + note.plainText).lowercased()
                guard haystack.contains(needle) else { continue }
            }
            results.append(note)
            if results.count >= limit { break }
        }
        return results
    }
}
