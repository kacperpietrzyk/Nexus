import CoreGraphics
import Foundation
import NexusCore
import Testing
@testable import NexusUI

@Suite struct GraphForceLayoutTests {
    private func snapshot() -> GraphSnapshot {
        let a = GraphNodeID(.meeting, UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let b = GraphNodeID(.task, UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let c = GraphNodeID(.note, UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
        return GraphSnapshot(
            nodes: [
                GraphNode(nodeID: a, title: "M", degree: 2),
                GraphNode(nodeID: b, title: "T", degree: 1),
                GraphNode(nodeID: c, title: "N", degree: 1),
            ],
            edges: [
                GraphEdge(from: a, to: b, linkKind: .mentions),
                GraphEdge(from: a, to: c, linkKind: .mentions),
            ],
            totalNodeCount: 3, unresolvedDropCount: 0)
    }

    @Test func everyNodeGetsAFinitePosition() {
        let positions = GraphForceLayout.solve(snapshot(), iterations: 60)
        #expect(positions.count == 3)
        for (_, p) in positions { #expect(p.x.isFinite && p.y.isFinite) }
    }

    @Test func deterministicForFixedInput() {
        let p1 = GraphForceLayout.solve(snapshot(), iterations: 60)
        let p2 = GraphForceLayout.solve(snapshot(), iterations: 60)
        for id in p1.keys { #expect(p1[id] == p2[id]) }
    }

    @Test func emptySnapshotYieldsEmpty() {
        #expect(GraphForceLayout.solve(.empty).isEmpty)
    }
}
