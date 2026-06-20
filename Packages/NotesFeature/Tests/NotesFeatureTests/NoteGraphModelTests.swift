import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@MainActor
@Suite("NoteGraphModel - graph orchestration")
struct NoteGraphModelTests {
    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private func makeModel(scope: GraphScope = .global) -> NoteGraphModel {
        let note1 = GraphNodeID(.note, uuid(1))
        let note2 = GraphNodeID(.note, uuid(2))
        let note3 = GraphNodeID(.note, uuid(3))
        let task1 = GraphNodeID(.task, uuid(4))
        let titles = [note1: "n1", note2: "n2", note3: "n3", task1: "t1"]
        let links = [
            GraphLinkRecord(from: note1, to: task1, linkKind: .containsTask),
            GraphLinkRecord(from: note1, to: note2, linkKind: .mentions),
        ]
        return NoteGraphModel(
            providers: NoteGraphModel.Providers(
                links: { links },
                titles: { titles },
                noteSeeds: { [note1, note2, note3] }
            ),
            scope: scope
        )
    }

    @Test("init loads the snapshot")
    func initialLoad() {
        let model = makeModel()
        #expect(model.snapshot.nodes.count == 4)
        #expect(model.snapshot.edges.count == 2)
    }

    @Test("toggling a kind off removes its nodes and rebuilds the snapshot")
    func toggleKind() {
        let model = makeModel()
        model.toggle(.task)
        #expect(!model.includedKinds.contains(.task))
        #expect(model.snapshot.nodes.allSatisfy { $0.nodeID.kind == .note })
        #expect(model.snapshot.nodes.count == 3)

        model.toggle(.task)
        #expect(model.snapshot.nodes.count == 4)
    }

    @Test("local scope narrows to the center's neighborhood")
    func localScope() {
        let model = makeModel(scope: .local(center: GraphNodeID(.note, uuid(1)), depth: 1))
        #expect(model.snapshot.nodes.count == 3)
        model.setScope(.global)
        #expect(model.snapshot.nodes.count == 4)
    }

    @Test("selection resolves a node and survives only while the node exists")
    func selection() {
        let model = makeModel()
        let task = model.snapshot.nodes.first { $0.nodeID.kind == .task }!
        model.select(task.nodeID)
        #expect(model.selectedNode?.title == "t1")

        model.toggle(.task)
        #expect(model.selectedNode == nil)
    }
}
