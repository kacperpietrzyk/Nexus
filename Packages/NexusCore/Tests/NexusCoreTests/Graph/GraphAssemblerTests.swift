import Foundation
import NexusCore
import Testing

@Suite("GraphAssembler - pure snapshot assembly")
struct GraphAssemblerTests {
    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private func node(_ kind: ItemKind, _ n: Int) -> GraphNodeID {
        GraphNodeID(kind, uuid(n))
    }

    private func link(
        _ from: GraphNodeID, _ to: GraphNodeID, _ kind: LinkKind = .mentions
    ) -> GraphLinkRecord {
        GraphLinkRecord(from: from, to: to, linkKind: kind)
    }

    @Test("links become nodes + edges with resolved titles and degrees")
    func basicAssembly() {
        let note = node(.note, 1)
        let task = node(.task, 2)
        let titles = [note: "My note", task: "My task"]

        let snapshot = GraphAssembler.assemble(links: [link(note, task)], titles: titles)

        #expect(snapshot.nodes.count == 2)
        #expect(snapshot.edges == [GraphEdge(from: note, to: task, linkKind: .mentions)])
        #expect(snapshot.nodes.map(\.title).sorted() == ["My note", "My task"])
        #expect(snapshot.nodes.allSatisfy { $0.degree == 1 })
        #expect(snapshot.totalNodeCount == 2)
        #expect(snapshot.unresolvedDropCount == 0)
        #expect(!snapshot.isTruncated)
    }

    @Test("duplicate links collapse into one edge; self-loops are dropped")
    func dedupeAndSelfLoops() {
        let a = node(.note, 1)
        let b = node(.note, 2)
        let titles = [a: "A", b: "B"]
        let links = [link(a, b), link(a, b), link(a, a)]

        let snapshot = GraphAssembler.assemble(links: links, titles: titles)

        #expect(snapshot.edges.count == 1)
        #expect(snapshot.nodes.count == 2)
    }

    @Test("distinct linkKinds between the same endpoints stay distinct edges")
    func distinctKindsKept() {
        let a = node(.note, 1)
        let b = node(.task, 2)
        let titles = [a: "A", b: "B"]
        let links = [link(a, b, .mentions), link(a, b, .containsTask)]

        let snapshot = GraphAssembler.assemble(links: links, titles: titles)
        #expect(snapshot.edges.count == 2)
    }

    @Test("unresolvable endpoints drop the link and are counted, not silent")
    func unresolvedDrop() {
        let note = node(.note, 1)
        let ghost = node(.task, 9)
        let titles = [note: "A"]

        let bare = GraphAssembler.assemble(links: [link(note, ghost)], titles: titles)
        #expect(bare.nodes.isEmpty)
        #expect(bare.edges.isEmpty)
        #expect(bare.unresolvedDropCount == 1)

        let seeded = GraphAssembler.assemble(
            links: [link(note, ghost)], titles: titles, seeds: [note]
        )
        #expect(seeded.nodes.map(\.nodeID) == [note])
        #expect(seeded.edges.isEmpty)
    }

    @Test("orphan note seeds render as degree-0 nodes")
    func orphanSeeds() {
        let orphan = node(.note, 1)
        let snapshot = GraphAssembler.assemble(
            links: [], titles: [orphan: "Lonely"], seeds: [orphan]
        )
        #expect(snapshot.nodes == [GraphNode(nodeID: orphan, title: "Lonely", degree: 0)])
    }

    @Test("kind filter removes nodes and their incident edges")
    func kindFilter() {
        let note = node(.note, 1)
        let task = node(.task, 2)
        let titles = [note: "A", task: "B"]

        let snapshot = GraphAssembler.assemble(
            links: [link(note, task)],
            titles: titles,
            seeds: [note],
            includedKinds: [.note]
        )
        #expect(snapshot.nodes.map(\.nodeID) == [note])
        #expect(snapshot.edges.isEmpty)
    }

    @Test("plumbing kinds are never renderable even when explicitly included")
    func plumbingKindsExcluded() {
        let note = node(.note, 1)
        let block = node(.scheduledBlock, 2)
        let titles = [note: "A", block: "B"]

        let snapshot = GraphAssembler.assemble(
            links: [link(note, block, .scheduledAs)],
            titles: titles,
            includedKinds: Set(ItemKind.allCases)
        )
        #expect(snapshot.edges.isEmpty)
        #expect(!snapshot.nodes.contains { $0.nodeID == block })
    }

    @Test("local scope keeps the BFS neighborhood at the requested depth")
    func localScope() {
        // Chain: n1 - n2 - n3 - n4
        let n1 = node(.note, 1)
        let n2 = node(.note, 2)
        let n3 = node(.note, 3)
        let n4 = node(.note, 4)
        let titles = [n1: "1", n2: "2", n3: "3", n4: "4"]
        let links = [link(n1, n2), link(n2, n3), link(n3, n4)]

        let depth1 = GraphAssembler.assemble(
            links: links, titles: titles, scope: .local(center: n2, depth: 1)
        )
        #expect(Set(depth1.nodes.map(\.nodeID)) == [n1, n2, n3])
        #expect(depth1.edges.count == 2)

        let depth2 = GraphAssembler.assemble(
            links: links, titles: titles, scope: .local(center: n2, depth: 2)
        )
        #expect(depth2.nodes.count == 4)
        #expect(depth2.edges.count == 3)
    }

    @Test("local scope around an orphan seed shows just the center")
    func localScopeOrphanCenter() {
        let orphan = node(.note, 7)
        let snapshot = GraphAssembler.assemble(
            links: [],
            titles: [orphan: "Solo"],
            seeds: [orphan],
            scope: .local(center: orphan, depth: 2)
        )
        #expect(snapshot.nodes.map(\.nodeID) == [orphan])
    }

    @Test("node cap keeps highest-degree nodes and reports the truncation")
    func nodeCap() {
        // Star: hub linked to 5 leaves; cap at 3.
        let hub = node(.note, 100)
        let leaves = (1...5).map { node(.task, $0) }
        var titles = [hub: "hub"]
        for (offset, leaf) in leaves.enumerated() { titles[leaf] = "leaf\(offset)" }
        let links = leaves.map { link(hub, $0) }

        let snapshot = GraphAssembler.assemble(links: links, titles: titles, maxNodes: 3)

        #expect(snapshot.nodes.count == 3)
        #expect(snapshot.totalNodeCount == 6)
        #expect(snapshot.isTruncated)
        #expect(snapshot.nodes.contains { $0.nodeID == hub })
        // The hub's degree reflects TRUE connectivity, not the post-cap edge count.
        #expect(snapshot.nodes.first { $0.nodeID == hub }?.degree == 5)
        // Every surviving edge connects two surviving nodes.
        let kept = Set(snapshot.nodes.map(\.nodeID))
        #expect(snapshot.edges.allSatisfy { kept.contains($0.from) && kept.contains($0.to) })
    }

    @Test("assembly output is deterministic - identical inputs, identical snapshot")
    func deterministicOutput() {
        let nodes = (1...20).map { node($0 % 2 == 0 ? .note : .task, $0) }
        var titles: [GraphNodeID: String] = [:]
        for (offset, id) in nodes.enumerated() { titles[id] = "t\(offset)" }
        var links: [GraphLinkRecord] = []
        for index in 0..<(nodes.count - 1) {
            links.append(link(nodes[index], nodes[index + 1]))
        }

        let first = GraphAssembler.assemble(links: links, titles: titles, seeds: nodes)
        let second = GraphAssembler.assemble(links: links.shuffled(), titles: titles, seeds: nodes.shuffled())
        #expect(first == second)
    }
}
