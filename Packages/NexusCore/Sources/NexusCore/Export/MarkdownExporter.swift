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
            let doc = MarkdownDocument(
                id: item.id,
                kind: item.kind,
                title: item.title,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                deletedAt: item.deletedAt,
                outgoingLinks: outgoing,
                body: body(for: item)
            )
            let path = folder.appendingPathComponent(
                uniqueFilename(for: doc, used: &counters.usedFilenames)
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
    private static func uniqueFilename(for doc: MarkdownDocument, used: inout Set<String>) -> String {
        var candidate = doc.filename
        if used.contains(candidate) {
            let base = "\(doc.id.uuidString)-\(doc.kind.rawValue)"
            candidate = "\(base).md"
            var suffix = 2
            while used.contains(candidate) {
                candidate = "\(base)-\(suffix).md"
                suffix += 1
            }
        }
        used.insert(candidate)
        return candidate
    }

    private static func body<L: Linkable>(for item: L) -> String {
        if let task = item as? TaskItem {
            return task.body
        }
        return ""
    }

    private struct ExportCounters {
        var itemsExported = 0
        var linksAttached = 0
        var usedFilenames: Set<String> = []
    }
}
