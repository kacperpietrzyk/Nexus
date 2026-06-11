import Foundation
import NexusCore
import SwiftData

/// Builds the `(kind, id) -> display title` index the assembler resolves nodes
/// against. Covers every NexusCore renderable kind generically; kinds whose
/// models live outside NexusCore come in through `external`.
///
/// Fetch-all + in-memory filter is deliberate: generic `Linkable` predicates
/// can trap in optimized SwiftData builds, as documented by
/// `LinkableRepository.fetchAll`.
@MainActor
public enum GraphTitleIndex {
    public static func build(
        context: ModelContext,
        external: [ItemKind: [UUID: String]] = [:]
    ) throws -> [GraphNodeID: String] {
        var titles: [GraphNodeID: String] = [:]

        func index<Model: PersistentModel & Linkable>(_ type: Model.Type, as kind: ItemKind) throws {
            for item in try context.fetch(FetchDescriptor<Model>()) where item.deletedAt == nil {
                titles[GraphNodeID(kind, item.id)] = item.title
            }
        }

        try index(Note.self, as: .note)
        try index(TaskItem.self, as: .task)
        try index(Project.self, as: .project)
        try index(Person.self, as: .person)
        try index(Label.self, as: .label)
        try index(Cycle.self, as: .cycle)

        for (kind, byID) in external {
            for (id, title) in byID {
                titles[GraphNodeID(kind, id)] = title
            }
        }
        return titles
    }
}

extension GraphLinkRecord {
    /// Value copy of a SwiftData `Link` row.
    @MainActor
    public init(_ link: Link) {
        self.init(
            from: GraphNodeID(link.fromKind, link.fromID),
            to: GraphNodeID(link.toKind, link.toID),
            linkKind: link.linkKind
        )
    }
}
