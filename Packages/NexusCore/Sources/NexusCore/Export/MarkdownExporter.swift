import Foundation
import SwiftData

/// Result summary returned to UI for "Exported N items" toast.
public struct MarkdownExportResult: Sendable {
    public let itemsExported: Int
    public let linksAttached: Int
    public let folder: URL
}

/// Walks a `ModelContainer`, emits one `.md` per non-deleted Linkable for each
/// concrete type the caller passes. D3 mitigation: this is the lock-in safety valve.
public enum MarkdownExporter {
    public static func export<each L: Linkable>(
        container: ModelContainer,
        types: repeat (each L).Type,
        to folder: URL
    ) async throws -> MarkdownExportResult {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try await MainActor.run {
            let context = ModelContext(container)
            let allLinks = try context.fetch(FetchDescriptor<Link>())
            let linksByFromID = Dictionary(grouping: allLinks, by: \.fromID)

            var counters = ExportCounters()

            repeat
                try Self.exportSingleType(
                    (each L).self,
                    in: context,
                    linksByFromID: linksByFromID,
                    folder: folder,
                    counters: &counters
                )

            return MarkdownExportResult(
                itemsExported: counters.itemsExported,
                linksAttached: counters.linksAttached,
                folder: folder
            )
        }
    }

    @MainActor
    private static func exportSingleType<L: Linkable>(
        _ type: L.Type,
        in context: ModelContext,
        linksByFromID: [UUID: [Link]],
        folder: URL,
        counters: inout ExportCounters
    ) throws {
        // Cache of Note id → serialized Markdown body so each note is decoded at
        // most once even if several items reference it (e.g. transcluded task).
        var noteBodyCache: [UUID: String] = [:]
        // Fetch every row and filter `deletedAt == nil` in Swift rather than via a
        // `#Predicate<L>`. A predicate built over the generic protocol type `L` synthesizes a
        // keypath through the `Linkable` witness that SwiftData cannot match against the
        // concrete model's registered schema keypath in optimized (Release) builds — it traps
        // in `DataUtilities` with "Couldn't find \Model.<computed …>". Fetching all and
        // filtering in memory avoids keypath translation entirely; tombstone volume is bounded
        // by `TombstonePurger`, so the cost is negligible at single-user scale.
        let items = try context.fetch(FetchDescriptor<L>())
            .filter { $0.deletedAt == nil }
        for item in items {
            let outgoing = (linksByFromID[item.id] ?? []).map { link in
                MarkdownDocument.LinkRef(
                    toKind: link.toKind,
                    toID: link.toID,
                    linkKind: link.linkKind
                )
            }
            // Feature-module Linkables (e.g. `Meeting`) own their export via
            // `MarkdownExportRenderable`; NexusCore's built-in note-body
            // resolution covers everything else.
            let extras: [(String, FrontmatterValue)]
            let bodyText: String
            if let renderable = item as? any MarkdownExportRenderable {
                extras = renderable.exportFrontmatterExtras()
                bodyText = renderable.exportMarkdownBody(in: context)
            } else {
                // Tranche 2 Plan E: a Note carries organization frontmatter
                // (folder + custom properties); every other built-in type has none.
                extras = (item as? Note).map(Self.noteFrontmatterExtras) ?? []
                bodyText = body(for: item, in: context, noteBodyCache: &noteBodyCache)
            }
            let doc = MarkdownDocument(
                id: item.id,
                kind: item.kind,
                title: item.title,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                deletedAt: item.deletedAt,
                extraFrontmatter: extras,
                outgoingLinks: outgoing,
                body: bodyText
            )
            let relativeDirectory = Self.relativeDirectory(for: item)
            let targetFolder =
                relativeDirectory.isEmpty
                ? folder
                : folder.appendingPathComponent(relativeDirectory, isDirectory: true)
            if !relativeDirectory.isEmpty {
                try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)
            }
            let path = targetFolder.appendingPathComponent(
                uniqueFilename(for: doc, inDirectory: relativeDirectory, used: &counters.usedFilenames)
            )
            try doc.render().write(to: path, atomically: true, encoding: .utf8)
            counters.itemsExported += 1
            counters.linksAttached += outgoing.count
        }
    }

    /// `MarkdownDocument.filename` is `<id>.md`. Synced entities cannot enforce id uniqueness
    /// (CloudKit forbids `@Attribute(.unique)`), so two non-deleted Linkables can share a UUID;
    /// a plain `<id>.md` write would atomically overwrite the first with the second, silently
    /// losing data from the anti-lock-in export. Disambiguate on collision so every item lands
    /// in its own file. The first item with a given id keeps the plain `<id>.md` name.
    /// Tranche 2 Plan E: notes export into `folderPath` subdirectories, so the collision set is
    /// keyed on the RELATIVE PATH (`"<dir>/<file>"`) — the guarantee holds per directory, and
    /// the same id in two different folders keeps the plain name in both.
    private static func uniqueFilename(
        for doc: MarkdownDocument,
        inDirectory relativeDirectory: String,
        used: inout Set<String>
    ) -> String {
        func key(_ name: String) -> String {
            relativeDirectory.isEmpty ? name : "\(relativeDirectory)/\(name)"
        }
        var candidate = doc.filename
        if used.contains(key(candidate)) {
            let base = "\(doc.id.uuidString)-\(doc.kind.rawValue)"
            candidate = "\(base).md"
            var suffix = 2
            while used.contains(key(candidate)) {
                candidate = "\(base)-\(suffix).md"
                suffix += 1
            }
        }
        used.insert(key(candidate))
        return candidate
    }

    /// Resolve a Linkable's Markdown body. Task content moved off `TaskItem.body`
    /// into a `Note` (`TaskItem.noteRef`), and a `Project` gains an optional
    /// canonical page (`Project.canonicalNoteRef`) — per the Notes content layer
    /// (spec §4.2). Only those two types carry a note ref, so only they are
    /// special-cased; every other Linkable has no inline body to export here.
    ///
    /// The note's canonical `[Block]` content is decoded from `contentData` and
    /// serialized via `BlockMarkdownSerializer`. A `Note` exported as its own
    /// Linkable also emits its body the same way.
    @MainActor
    private static func body<L: Linkable>(
        for item: L,
        in context: ModelContext,
        noteBodyCache: inout [UUID: String]
    ) -> String {
        let noteRef: UUID?
        switch item {
        case let task as TaskItem: noteRef = task.noteRef
        case let project as Project: noteRef = project.canonicalNoteRef
        case let note as Note: return markdownBody(of: note)
        default: noteRef = nil
        }
        guard let noteRef else { return "" }
        if let cached = noteBodyCache[noteRef] { return cached }
        let body = resolveNoteBody(id: noteRef, in: context)
        noteBodyCache[noteRef] = body
        return body
    }

    @MainActor
    private static func resolveNoteBody(id: UUID, in context: ModelContext) -> String {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let note = try? context.fetch(descriptor).first, note.deletedAt == nil else {
            return ""
        }
        return markdownBody(of: note)
    }

    private static func markdownBody(of note: Note) -> String {
        guard let blocks = try? NoteContentCoder.decode(note.contentData) else { return "" }
        return BlockMarkdownSerializer.markdown(for: blocks)
    }

    // MARK: - Note organization frontmatter (Tranche 2 Plan E)

    /// `folder:` (when set) then one flat `prop.<key>:` per custom property.
    /// Decision (plan E, spec §6.1): flat prefixed TOP-LEVEL keys — the only
    /// shape the FROZEN coder round-trips for all five `NotePropertyValue`
    /// cases (`inlineValue` cannot nest a list inside a `properties:` list item,
    /// and a top-level dict does not decode). The uniform prefix is
    /// collision-proof against every reserved key. Caller order is preserved
    /// (determinism guarantee #1 of the coder).
    static func noteFrontmatterExtras(_ note: Note) -> [(String, FrontmatterValue)] {
        var extras: [(String, FrontmatterValue)] = []
        if let folderPath = note.folderPath {
            extras.append(("folder", .string(folderPath)))
        }
        for property in note.properties {
            extras.append(("prop.\(sanitizedPropertyKey(property.key))", frontmatterValue(for: property.value)))
        }
        return extras
    }

    /// Map a `NotePropertyValue` into the frozen `FrontmatterValue` (spec §2.4):
    /// number/bool collapse to `.string` (the coder has no such cases — do NOT
    /// extend it this tranche).
    static func frontmatterValue(for value: NotePropertyValue) -> FrontmatterValue {
        switch value {
        case .string(let text): return .string(text)
        case .date(let date): return .date(date)
        case .list(let items): return .list(items.map { .string($0) })
        case .number(let number): return .string(numberString(number))
        case .bool(let flag): return .string(flag ? "true" : "false")
        }
    }

    /// Deterministic number formatting: integral doubles collapse ("2", not
    /// "2.0"); everything else uses Swift's shortest round-trip description.
    static func numberString(_ value: Double) -> String {
        if let integer = Int(exactly: value) { return String(integer) }
        return String(value)
    }

    /// Frontmatter keys are emitted unquoted on a `key: value` line; a `:` or
    /// newline inside a user key would break the line-oriented decoder. Replace
    /// them so every export round-trips. Never drops a property.
    static func sanitizedPropertyKey(_ key: String) -> String {
        key
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    /// Relative export directory for an item: a `Note`'s sanitized `folderPath`
    /// components; empty (= export root) for every other type and for root notes.
    /// Components are sanitized DEFENSIVELY even though write paths normalize
    /// (`NoteFolderPath.normalize`) — a synced path from a newer build must
    /// never break the export. Sanitization can only redirect, never drop:
    /// worst case the note lands at the root.
    static func relativeDirectory<L: Linkable>(for item: L) -> String {
        guard let note = item as? Note, let folderPath = note.folderPath else { return "" }
        return
            folderPath
            .split(separator: "/")
            .map { sanitizedPathComponent(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    /// Filesystem-safe folder component: `:` → `-` (HFS/APFS separator legacy),
    /// `.`/`..` → `_` (no directory traversal), trimmed.
    static func sanitizedPathComponent(_ component: String) -> String {
        let cleaned =
            component
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        if cleaned == "." || cleaned == ".." { return "_" }
        return cleaned
    }

    private struct ExportCounters {
        var itemsExported = 0
        var linksAttached = 0
        var usedFilenames: Set<String> = []
    }
}
