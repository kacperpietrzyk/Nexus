import CoreGraphics
import Foundation
import NexusCore
import Testing

@testable import NexusUI

@Suite struct RadialEgoLayoutTests {
    private func node(_ kind: ItemKind, _ index: Int) -> GraphNodeID {
        GraphNodeID(kind, UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", index))") ?? UUID())
    }

    private func snapshot(nodes: [GraphNodeID], edges: [(GraphNodeID, GraphNodeID)]) -> GraphSnapshot {
        GraphSnapshot(
            nodes: nodes.map { GraphNode(nodeID: $0, title: "n", degree: 1) },
            edges: edges.map { GraphEdge(from: $0.0, to: $0.1, linkKind: .mentions) },
            totalNodeCount: nodes.count, unresolvedDropCount: 0)
    }

    @Test func focusSitsAtOrigin() {
        let root = node(.meeting, 0)
        let snap = snapshot(
            nodes: [root, node(.task, 1), node(.task, 2)],
            edges: [(root, node(.task, 1)), (root, node(.task, 2))])
        let positions = RadialEgoLayout.solve(snap, rootID: root)
        #expect(positions[root] == .zero)
    }

    @Test func oneHopNeighboursShareOneRingRadius() {
        let root = node(.meeting, 0)
        let leaves = [node(.task, 1), node(.task, 2), node(.task, 3), node(.task, 4)]
        let snap = snapshot(nodes: [root] + leaves, edges: leaves.map { (root, $0) })
        let positions = RadialEgoLayout.solve(snap, rootID: root, ringGap: 150)
        for leaf in leaves {
            let p = positions[leaf] ?? .zero
            let radius = (p.x * p.x + p.y * p.y).squareRoot()
            #expect(abs(radius - 150) < 0.001)
        }
    }

    @Test func twoHopNodesRideTheOuterRing() {
        let root = node(.meeting, 0)
        let mid = node(.task, 1)
        let far = node(.note, 2)
        let snap = snapshot(nodes: [root, mid, far], edges: [(root, mid), (mid, far)])
        let positions = RadialEgoLayout.solve(snap, rootID: root, ringGap: 150)
        let farRadius =
            ((positions[far]?.x ?? 0) * (positions[far]?.x ?? 0)
            + (positions[far]?.y ?? 0) * (positions[far]?.y ?? 0)).squareRoot()
        #expect(abs(farRadius - 300) < 0.001)
    }

    @Test func deterministicForFixedInput() {
        let root = node(.meeting, 0)
        let leaves = [node(.task, 1), node(.task, 2), node(.task, 3)]
        let snap = snapshot(nodes: [root] + leaves, edges: leaves.map { (root, $0) })
        let first = RadialEgoLayout.solve(snap, rootID: root)
        let second = RadialEgoLayout.solve(snap, rootID: root)
        #expect(first == second)
    }
}
