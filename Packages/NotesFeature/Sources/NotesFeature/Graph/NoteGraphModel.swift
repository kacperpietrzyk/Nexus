import Foundation
import NexusCore
import Observation
import SwiftData

/// Orchestrates the graph surface: pulls links/titles/seeds through injected
/// providers, assembles the deterministic snapshot, and owns the scope/filter/
/// selection state. Layout + rendering live in the shared `KnowledgeGraphView`.
@MainActor
@Observable
public final class NoteGraphModel {
    public struct Providers {
        public var links: @MainActor () -> [GraphLinkRecord]
        public var titles: @MainActor () -> [GraphNodeID: String]
        public var noteSeeds: @MainActor () -> [GraphNodeID]

        public init(
            links: @escaping @MainActor () -> [GraphLinkRecord],
            titles: @escaping @MainActor () -> [GraphNodeID: String],
            noteSeeds: @escaping @MainActor () -> [GraphNodeID]
        ) {
            self.links = links
            self.titles = titles
            self.noteSeeds = noteSeeds
        }
    }

    public private(set) var snapshot: GraphSnapshot = .empty
    public private(set) var includedKinds: Set<ItemKind> = GraphAssembler.renderableKinds
    public private(set) var scope: GraphScope
    public private(set) var selectedNodeID: GraphNodeID?

    public var selectedNode: GraphNode? {
        snapshot.nodes.first { $0.nodeID == selectedNodeID }
    }

    @ObservationIgnored private let providers: Providers

    public init(
        providers: Providers,
        scope: GraphScope = .global
    ) {
        self.providers = providers
        self.scope = scope
        reload()
    }

    /// Production wiring: whole `Link` table + core title index plus live-note
    /// seeds so orphan notes render.
    public static func live(
        context: ModelContext,
        externalTitles: @escaping @MainActor () -> [ItemKind: [UUID: String]] = { [:] },
        scope: GraphScope = .global
    ) -> NoteGraphModel {
        NoteGraphModel(
            providers: Providers(
                links: {
                    let rows = (try? LinkRepository(context: context).allLinks()) ?? []
                    return rows.map(GraphLinkRecord.init)
                },
                titles: {
                    (try? GraphTitleIndex.build(context: context, external: externalTitles()))
                        ?? [:]
                },
                noteSeeds: {
                    let descriptor = FetchDescriptor<Note>(
                        predicate: #Predicate { $0.deletedAt == nil }
                    )
                    let notes = (try? context.fetch(descriptor)) ?? []
                    return notes.map { GraphNodeID(.note, $0.id) }
                }
            ),
            scope: scope
        )
    }

    public func reload() {
        snapshot = GraphAssembler.assemble(
            links: providers.links(),
            titles: providers.titles(),
            seeds: providers.noteSeeds(),
            includedKinds: includedKinds,
            scope: scope
        )
        if let selectedNodeID, !snapshot.nodes.contains(where: { $0.nodeID == selectedNodeID }) {
            self.selectedNodeID = nil
        }
    }

    public func toggle(_ kind: ItemKind) {
        if includedKinds.contains(kind) {
            includedKinds.remove(kind)
        } else {
            includedKinds.insert(kind)
        }
        reload()
    }

    public func setScope(_ scope: GraphScope) {
        self.scope = scope
        reload()
    }

    public func select(_ nodeID: GraphNodeID?) {
        selectedNodeID = nodeID
    }
}
