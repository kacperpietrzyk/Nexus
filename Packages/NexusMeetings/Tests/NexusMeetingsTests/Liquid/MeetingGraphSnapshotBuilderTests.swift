import Foundation
import NexusCore
import Testing
@testable import NexusMeetings

@Suite struct MeetingGraphSnapshotBuilderTests {
    private let mtg = GraphNodeID(.meeting, UUID())
    private let task = GraphNodeID(.task, UUID())
    private let realPerson = GraphNodeID(.person, UUID())
    private let junkPerson = GraphNodeID(.person, UUID())

    private func titles(_ id: GraphNodeID) -> String? {
        switch id {
        case mtg: return "Standup"
        case task: return "Write doc"
        case realPerson: return "Ada Lovelace"
        case junkPerson: return "Participant 3"
        default: return nil
        }
    }
    private func isPlaceholder(_ id: GraphNodeID, _ name: String) -> Bool {
        id.kind == .person && name.hasPrefix("Participant ")
    }

    @Test func dropsPlaceholderPersonButKeepsRealOnes() {
        let edges = [
            GraphLinkRecord(from: mtg, to: task, linkKind: .mentions),
            GraphLinkRecord(from: mtg, to: realPerson, linkKind: .mentions),
            GraphLinkRecord(from: mtg, to: junkPerson, linkKind: .mentions),
        ]
        let snap = MeetingGraphSnapshotBuilder.build(
            root: mtg, depth: 1, edges: edges, title: titles, isPlaceholder: isPlaceholder)
        let ids = Set(snap.nodes.map(\.nodeID))
        #expect(ids.contains(mtg))
        #expect(ids.contains(task))
        #expect(ids.contains(realPerson))
        #expect(!ids.contains(junkPerson))  // placeholder filtered
    }

    @Test func rootIsAlwaysPresentEvenWithNoEdges() {
        let snap = MeetingGraphSnapshotBuilder.build(
            root: mtg, depth: 1, edges: [], title: titles, isPlaceholder: isPlaceholder)
        #expect(snap.nodes.map(\.nodeID) == [mtg])
    }
}
