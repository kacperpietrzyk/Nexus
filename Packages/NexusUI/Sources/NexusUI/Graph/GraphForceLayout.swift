import CoreGraphics
import Foundation
import NexusCore
#if os(macOS) || os(iOS)
import ForceSimulation
#endif

/// Runs Grape's force simulation over a `GraphSnapshot` and returns settled 2D
/// positions keyed by node. Deterministic: nodes are seeded on a ring by their
/// sorted index (the snapshot is already totally ordered), so identical input
/// yields identical output. No randomness.
public enum GraphForceLayout {
    public static func solve(
        _ snapshot: GraphSnapshot, iterations: Int = 120, spread: Double = 120
    ) -> [GraphNodeID: CGPoint] {
        let nodes = snapshot.nodes
        guard !nodes.isEmpty else { return [:] }
        #if os(macOS) || os(iOS)
        let index = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.nodeID, $0.offset) })
        let links = snapshot.edges.compactMap { edge -> EdgeID<Int>? in
            guard let s = index[edge.from], let t = index[edge.to] else { return nil }
            return EdgeID(source: s, target: t)
        }
        // Deterministic ring seed (avoids zero-collapse + RNG).
        let n = nodes.count
        let seeded: [SIMD2<Double>] = (0..<n).map { i in
            let a = (Double(i) / Double(n)) * 2 * .pi
            return SIMD2(spread * cos(a), spread * sin(a))
        }
        let force = SealedForce2D {
            Kinetics2D.ManyBodyForce(strength: -30)
            Kinetics2D.LinkForce(
                stiffness: .weightedByDegree(k: { _, _ in 1.0 }),
                originalLength: .constant(spread / 2))
            Kinetics2D.CenterForce(center: .zero, strength: 1)
            Kinetics2D.CollideForce(radius: .constant(12))
        }
        let sim = Simulation(nodeCount: n, links: links, forceField: force, position: seeded)
        for _ in 0..<max(1, iterations) { sim.tick() }
        // kinetics.position is `package`-scoped in Grape — use Mirror to read it cross-package.
        let mirror = Mirror(reflecting: sim.kinetics)
        var settled: [SIMD2<Double>] = seeded  // fallback: seeded positions
        for child in mirror.children where child.label == "position" {
            if let arr = child.value as? UnsafeArray<SIMD2<Double>> {
                settled = arr.asArray()
            }
        }
        return Dictionary(
            uniqueKeysWithValues: nodes.enumerated().map { offset, node in
                let v = settled[offset]
                return (node.nodeID, CGPoint(x: v.x, y: v.y))
            })
        #else
        return [:]
        #endif
    }
}
