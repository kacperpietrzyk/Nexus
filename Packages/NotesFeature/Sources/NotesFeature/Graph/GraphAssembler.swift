import Foundation
import NexusCore

/// Pure assembly of a `GraphSnapshot` from value-copied link rows + a resolved
/// title index. Deterministic: identical inputs (in any order) produce an
/// identical snapshot.
public enum GraphAssembler {
    private struct ResolvedGraph {
        var nodes: Set<GraphNodeID>
        var edges: Set<GraphEdge>
        var unresolvedDropCount: Int
    }

    /// Kinds that render as knowledge nodes. Plumbing/system kinds
    /// (section, savedFilter, debug, agentMemory, scheduledBlock) never render.
    public static let renderableKinds: Set<ItemKind> = [
        .note, .task, .project, .meeting, .person, .label, .cycle,
    ]

    /// Performance cap for the O(n²) repulsion pass and Canvas draw. Exceeding
    /// it keeps the highest-degree nodes and reports the truncation on the
    /// snapshot - never a silent cap.
    public static let defaultMaxNodes = 300

    public static func assemble(
        links: [GraphLinkRecord],
        titles: [GraphNodeID: String],
        seeds: [GraphNodeID] = [],
        includedKinds: Set<ItemKind> = GraphAssembler.renderableKinds,
        scope: GraphScope = .global,
        maxNodes: Int = GraphAssembler.defaultMaxNodes
    ) -> GraphSnapshot {
        let kinds = includedKinds.intersection(Self.renderableKinds)
        let resolved = resolvedGraph(links: links, titles: titles, seeds: seeds, includedKinds: kinds)
        var nodeSet = resolved.nodes
        var edgeSet = resolved.edges

        if case .local(let center, let depth) = scope {
            nodeSet = localNodes(center: center, depth: depth, nodes: nodeSet, edges: edgeSet)
            edgeSet = edgeSet.filter { nodeSet.contains($0.from) && nodeSet.contains($0.to) }
        }

        let degrees = degrees(for: edgeSet)
        let totalNodeCount = nodeSet.count
        if nodeSet.count > maxNodes {
            nodeSet = cappedNodes(nodeSet, maxNodes: maxNodes, degrees: degrees, scope: scope)
            edgeSet = edgeSet.filter { nodeSet.contains($0.from) && nodeSet.contains($0.to) }
        }

        let nodes = nodeSet.sorted().map { id in
            GraphNode(nodeID: id, title: titles[id] ?? "", degree: degrees[id] ?? 0)
        }
        return GraphSnapshot(
            nodes: nodes,
            edges: edgeSet.sorted(),
            totalNodeCount: totalNodeCount,
            unresolvedDropCount: resolved.unresolvedDropCount
        )
    }

    private static func resolvedGraph(
        links: [GraphLinkRecord],
        titles: [GraphNodeID: String],
        seeds: [GraphNodeID],
        includedKinds: Set<ItemKind>
    ) -> ResolvedGraph {
        var unresolved: Set<GraphNodeID> = []

        func admit(_ node: GraphNodeID) -> Bool {
            guard includedKinds.contains(node.kind) else { return false }
            guard titles[node] != nil else {
                unresolved.insert(node)
                return false
            }
            return true
        }

        var edgeSet: Set<GraphEdge> = []
        var nodeSet: Set<GraphNodeID> = []
        for record in links {
            guard record.from != record.to else { continue }
            guard admit(record.from), admit(record.to) else { continue }
            edgeSet.insert(GraphEdge(from: record.from, to: record.to, linkKind: record.linkKind))
            nodeSet.insert(record.from)
            nodeSet.insert(record.to)
        }
        for seed in seeds where admit(seed) {
            nodeSet.insert(seed)
        }

        return ResolvedGraph(nodes: nodeSet, edges: edgeSet, unresolvedDropCount: unresolved.count)
    }

    private static func localNodes(
        center: GraphNodeID,
        depth: Int,
        nodes: Set<GraphNodeID>,
        edges: Set<GraphEdge>
    ) -> Set<GraphNodeID> {
        var adjacency: [GraphNodeID: Set<GraphNodeID>] = [:]
        for edge in edges {
            adjacency[edge.from, default: []].insert(edge.to)
            adjacency[edge.to, default: []].insert(edge.from)
        }
        var kept: Set<GraphNodeID> = nodes.contains(center) ? [center] : []
        var frontier = kept
        for _ in 0..<max(0, depth) {
            var next: Set<GraphNodeID> = []
            for node in frontier {
                for neighbor in adjacency[node] ?? [] where !kept.contains(neighbor) {
                    next.insert(neighbor)
                }
            }
            kept.formUnion(next)
            frontier = next
        }
        return kept
    }

    private static func degrees(for edges: Set<GraphEdge>) -> [GraphNodeID: Int] {
        var degrees: [GraphNodeID: Int] = [:]
        for edge in edges {
            degrees[edge.from, default: 0] += 1
            degrees[edge.to, default: 0] += 1
        }
        return degrees
    }

    private static func cappedNodes(
        _ nodes: Set<GraphNodeID>,
        maxNodes: Int,
        degrees: [GraphNodeID: Int],
        scope: GraphScope
    ) -> Set<GraphNodeID> {
        var ranked = nodes.sorted { lhs, rhs in
            let lhsDegree = degrees[lhs] ?? 0
            let rhsDegree = degrees[rhs] ?? 0
            if lhsDegree != rhsDegree { return lhsDegree > rhsDegree }
            return lhs < rhs
        }
        if let index = protectedLocalCenterIndex(in: ranked, scope: scope, maxNodes: maxNodes) {
            let center = ranked.remove(at: index)
            ranked.insert(center, at: 0)
        }
        return Set(ranked.prefix(maxNodes))
    }

    private static func protectedLocalCenterIndex(
        in ranked: [GraphNodeID],
        scope: GraphScope,
        maxNodes: Int
    ) -> Int? {
        guard case .local(let center, _) = scope,
            let index = ranked.firstIndex(of: center),
            index >= maxNodes
        else {
            return nil
        }
        return index
    }
}
