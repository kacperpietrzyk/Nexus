import CoreGraphics
import NexusCore

/// Deterministic concentric-ring layout for an ego/local graph: the focus node
/// sits at the origin and its neighbours fan out on clean orbital rings by hop
/// distance. A force sim reads as arbitrary for a handful of nodes — an orbital
/// ring reads as *intentional*, which is what makes a small graph look designed
/// rather than dumped. (Global maps keep `GraphForceLayout`; organic is correct
/// there.)
public enum RadialEgoLayout {
    public static func solve(
        _ snapshot: GraphSnapshot, rootID: GraphNodeID, ringGap: CGFloat = 150
    ) -> [GraphNodeID: CGPoint] {
        let nodeIDs = snapshot.nodes.map(\.nodeID)
        guard nodeIDs.contains(rootID) else { return [:] }

        var adjacency: [GraphNodeID: Set<GraphNodeID>] = [:]
        for edge in snapshot.edges {
            adjacency[edge.from, default: []].insert(edge.to)
            adjacency[edge.to, default: []].insert(edge.from)
        }

        // BFS hop distance from the focus.
        var hop: [GraphNodeID: Int] = [rootID: 0]
        var queue = [rootID]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            let nextHop = (hop[current] ?? 0) + 1
            for neighbor in (adjacency[current] ?? []).sorted() where hop[neighbor] == nil {
                hop[neighbor] = nextHop
                queue.append(neighbor)
            }
        }

        // Group by ring; disconnected nodes ride one ring past the farthest reached.
        let maxHop = hop.values.max() ?? 0
        var rings: [Int: [GraphNodeID]] = [:]
        for id in nodeIDs where id != rootID {
            rings[hop[id] ?? (maxHop + 1), default: []].append(id)
        }

        var positions: [GraphNodeID: CGPoint] = [rootID: .zero]
        for (ring, unsorted) in rings {
            let ids = unsorted.sorted()
            let count = max(1, ids.count)
            let radius = CGFloat(ring) * ringGap
            // Stagger odd rings so spokes don't line up between rings.
            let phase = ring.isMultiple(of: 2) ? 0 : CGFloat.pi / CGFloat(count)
            for (index, id) in ids.enumerated() {
                let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(count) + phase
                positions[id] = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            }
        }
        return positions
    }
}
