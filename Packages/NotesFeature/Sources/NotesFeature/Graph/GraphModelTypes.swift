import Foundation
import NexusCore

/// Stable identity of a graph node: the `(kind, id)` endpoint pair stored on
/// `Link` rows. `Comparable` gives the assembler and the layout engine a total
/// order, which is what makes the whole pipeline deterministic.
public struct GraphNodeID: Hashable, Sendable, Comparable {
    public let kind: ItemKind
    public let id: UUID

    public init(_ kind: ItemKind, _ id: UUID) {
        self.kind = kind
        self.id = id
    }

    public static func < (lhs: GraphNodeID, rhs: GraphNodeID) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// A renderable node: identity + resolved display title + TRUE degree
/// (incident edges before any cap - the cap must not lie about connectivity).
public struct GraphNode: Hashable, Sendable {
    public let nodeID: GraphNodeID
    public let title: String
    public let degree: Int

    public init(nodeID: GraphNodeID, title: String, degree: Int) {
        self.nodeID = nodeID
        self.title = title
        self.degree = degree
    }
}

/// A deduplicated directed edge. Multiple identical `Link` rows collapse into
/// one; distinct `linkKind`s between the same endpoints stay distinct.
public struct GraphEdge: Hashable, Sendable, Comparable {
    public let from: GraphNodeID
    public let to: GraphNodeID
    public let linkKind: LinkKind

    public init(from: GraphNodeID, to: GraphNodeID, linkKind: LinkKind) {
        self.from = from
        self.to = to
        self.linkKind = linkKind
    }

    public static func < (lhs: GraphEdge, rhs: GraphEdge) -> Bool {
        if lhs.from != rhs.from { return lhs.from < rhs.from }
        if lhs.to != rhs.to { return lhs.to < rhs.to }
        return lhs.linkKind.rawValue < rhs.linkKind.rawValue
    }
}

/// Value copy of a `Link` row. The assembler is pure - it never touches
/// SwiftData models, so it can be exercised without a store.
/// (`GraphLink` is already taken: `NoteListGrouping.GraphLink` aliases the model.)
public struct GraphLinkRecord: Hashable, Sendable {
    public let from: GraphNodeID
    public let to: GraphNodeID
    public let linkKind: LinkKind

    public init(from: GraphNodeID, to: GraphNodeID, linkKind: LinkKind) {
        self.from = from
        self.to = to
        self.linkKind = linkKind
    }
}

/// Which slice of the graph to assemble.
public enum GraphScope: Hashable, Sendable {
    case global
    /// BFS neighborhood of `center` out to `depth` hops (1-2 in the UI).
    case local(center: GraphNodeID, depth: Int)
}

/// Deterministic, render-ready graph: nodes and edges are totally ordered.
/// Truncation/unresolved counts surface in the UI (no-silent-caps convention).
public struct GraphSnapshot: Equatable, Sendable {
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]
    /// Node count BEFORE the cap - `isTruncated` derives from it.
    public var totalNodeCount: Int
    /// Unique endpoints dropped because no live item resolved a title
    /// (tombstoned or unknown to the host).
    public var unresolvedDropCount: Int

    public var isTruncated: Bool { nodes.count < totalNodeCount }

    public init(
        nodes: [GraphNode],
        edges: [GraphEdge],
        totalNodeCount: Int,
        unresolvedDropCount: Int
    ) {
        self.nodes = nodes
        self.edges = edges
        self.totalNodeCount = totalNodeCount
        self.unresolvedDropCount = unresolvedDropCount
    }

    public static let empty = GraphSnapshot(
        nodes: [], edges: [], totalNodeCount: 0, unresolvedDropCount: 0
    )
}
