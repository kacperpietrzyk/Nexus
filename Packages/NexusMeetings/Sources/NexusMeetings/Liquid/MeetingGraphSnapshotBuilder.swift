import Foundation
import NexusCore

/// Builds a `GraphSnapshot` for the meeting knowledge graph from pre-gathered
/// link records. Pure: no SwiftData. Placeholder-named persons are dropped so
/// junk ("Participant N") never reaches the graph; real persons stay.
enum MeetingGraphSnapshotBuilder {
    static func build(
        root: GraphNodeID,
        depth: Int,
        edges: [GraphLinkRecord],
        title: (GraphNodeID) -> String?,
        isPlaceholder: (GraphNodeID, String) -> Bool
    ) -> GraphSnapshot {
        var titles: [GraphNodeID: String] = [:]
        func admit(_ id: GraphNodeID) -> Bool {
            if let cached = titles[id] { return !cached.isEmpty }
            guard let t = title(id), !t.isEmpty, !isPlaceholder(id, t) else { return false }
            titles[id] = t
            return true
        }
        _ = admit(root)
        let kept = edges.filter { admit($0.from) && admit($0.to) }
        return GraphAssembler.assemble(
            links: kept, titles: titles, seeds: [root],
            scope: .local(center: root, depth: max(1, depth)))
    }
}
