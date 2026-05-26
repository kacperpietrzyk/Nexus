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
        let items = try context.fetch(
            FetchDescriptor<L>(
                predicate: #Predicate { $0.deletedAt == nil }
            )
        )
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
            let path = folder.appendingPathComponent(doc.filename)
            try doc.render().write(to: path, atomically: true, encoding: .utf8)
            counters.itemsExported += 1
            counters.linksAttached += outgoing.count
        }
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
    }
}
