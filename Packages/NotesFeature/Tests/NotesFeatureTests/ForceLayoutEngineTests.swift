import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@Suite("ForceLayoutEngine - deterministic force simulation")
struct ForceLayoutEngineTests {
    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    /// Chain graph of `count` notes: n1 - n2 - ... - nN (+ optional extra component).
    private func snapshot(count: Int, secondComponent: Int = 0) -> GraphSnapshot {
        var titles: [GraphNodeID: String] = [:]
        var links: [GraphLinkRecord] = []
        let nodes = (1...count).map { GraphNodeID(.note, uuid($0)) }
        for (offset, node) in nodes.enumerated() {
            titles[node] = "n\(offset)"
            if offset > 0 {
                links.append(GraphLinkRecord(from: nodes[offset - 1], to: node, linkKind: .mentions))
            }
        }
        if secondComponent > 0 {
            let others = (1...secondComponent).map { GraphNodeID(.task, uuid(1000 + $0)) }
            for (offset, node) in others.enumerated() {
                titles[node] = "t\(offset)"
                if offset > 0 {
                    links.append(
                        GraphLinkRecord(from: others[offset - 1], to: node, linkKind: .blocks)
                    )
                }
            }
            return GraphAssembler.assemble(links: links, titles: titles, seeds: nodes + others)
        }
        return GraphAssembler.assemble(links: links, titles: titles, seeds: nodes)
    }

    @Test("same seed + same snapshot = identical positions after full run")
    func determinism() {
        var first = ForceLayoutEngine(snapshot: snapshot(count: 12), seed: 42)
        var second = ForceLayoutEngine(snapshot: snapshot(count: 12), seed: 42)
        first.run()
        second.run()
        #expect(first.positions == second.positions)
        #expect(first.stepCount == second.stepCount)
    }

    @Test("different seeds produce different layouts")
    func seedMatters() {
        var first = ForceLayoutEngine(snapshot: snapshot(count: 12), seed: 1)
        var second = ForceLayoutEngine(snapshot: snapshot(count: 12), seed: 2)
        first.run()
        second.run()
        #expect(first.positions != second.positions)
    }

    @Test("a small graph genuinely settles before the step budget")
    func convergence() {
        var engine = ForceLayoutEngine(snapshot: snapshot(count: 6), seed: 7)
        engine.run()
        #expect(engine.isSettled)
        #expect(engine.stepCount < ForceLayoutEngine.Parameters().maxSteps)
    }

    @Test("no NaN/infinite positions, even from fully coincident starts")
    func coincidentStartsStayFinite() {
        var engine = ForceLayoutEngine(snapshot: snapshot(count: 5), seed: 3)
        for index in 0..<engine.positions.count {
            engine.setPosition(SIMD2(0, 0), at: index)
        }
        engine.run()
        for position in engine.positions {
            #expect(position.x.isFinite && position.y.isFinite)
        }
        // Coincident nodes must actually separate.
        for first in 0..<(engine.positions.count - 1) {
            for second in (first + 1)..<engine.positions.count {
                let delta = engine.positions[first] - engine.positions[second]
                #expect((delta.x * delta.x + delta.y * delta.y).squareRoot() > 0.1)
            }
        }
    }

    @Test("disconnected components stay bounded (gravity holds them)")
    func disconnectedComponentsBounded() {
        var engine = ForceLayoutEngine(snapshot: snapshot(count: 5, secondComponent: 5), seed: 9)
        engine.run()
        for position in engine.positions {
            let distance = (position.x * position.x + position.y * position.y).squareRoot()
            #expect(distance < 1000)
        }
    }

    @Test("the engine always terminates: maxSteps forces settle")
    func maxStepsForcesSettle() {
        var parameters = ForceLayoutEngine.Parameters()
        parameters.maxSteps = 5
        parameters.settleSpeed = 0
        var engine = ForceLayoutEngine(snapshot: snapshot(count: 8), parameters: parameters, seed: 11)
        engine.run()
        #expect(engine.isSettled)
        #expect(engine.stepCount == 5)
    }

    @Test("empty and single-node snapshots settle immediately")
    func trivialSnapshots() {
        var empty = ForceLayoutEngine(snapshot: .empty, seed: 1)
        #expect(empty.isSettled)
        #expect(empty.run() == 0)

        let single = ForceLayoutEngine(snapshot: snapshot(count: 1), seed: 1)
        #expect(single.isSettled)
        #expect(single.positions.count == 1)
    }

    @Test("nodeIDs follow the snapshot's deterministic node order")
    func nodeOrderMatchesSnapshot() {
        let graph = snapshot(count: 4)
        let engine = ForceLayoutEngine(snapshot: graph, seed: 1)
        #expect(engine.nodeIDs == graph.nodes.map(\.nodeID))
        #expect(engine.positions.count == 4)
    }
}
