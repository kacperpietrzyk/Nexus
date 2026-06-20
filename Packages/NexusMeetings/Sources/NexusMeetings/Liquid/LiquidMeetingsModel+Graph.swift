import Foundation
import NexusCore

extension LiquidMeetingsModel {
    /// Uncapped knowledge-graph snapshot for the graph sheet. BFS-walks the `Link`
    /// graph from the meeting root out to `depth` hops — independent of the 8-capped
    /// `graphItems` panel list. Title resolution uses `displayTitle`; `isPlaceholder`
    /// (host-supplied) drops junk persons. The assembler applies its own 300-node cap
    /// and reports honest `totalNodeCount`.
    func knowledgeGraphSnapshot(
        composition: MeetingsComposition,
        depth: Int,
        isPlaceholder: (GraphNodeID, String) -> Bool
    ) -> GraphSnapshot {
        guard let meeting else { return .empty }
        let root = GraphNodeID(.meeting, meeting.id)
        let context = composition.meetingRepository.context

        var records: [GraphLinkRecord] = []
        var visited: Set<GraphNodeID> = [root]
        var frontier: [GraphNodeID] = [root]
        for _ in 0..<max(1, depth) {
            var next: [GraphNodeID] = []
            for node in frontier {
                let endpoint: (ItemKind, UUID) = (node.kind, node.id)
                let edges =
                    ((try? composition.linkRepository.outgoing(from: endpoint)) ?? [])
                    + ((try? composition.linkRepository.backlinks(to: endpoint)) ?? [])
                for link in edges {
                    let from = GraphNodeID(link.fromKind, link.fromID)
                    let to = GraphNodeID(link.toKind, link.toID)
                    records.append(GraphLinkRecord(from: from, to: to, linkKind: link.linkKind))
                    for end in [from, to] where !visited.contains(end) {
                        visited.insert(end)
                        next.append(end)
                    }
                }
            }
            frontier = next
        }

        return MeetingGraphSnapshotBuilder.build(
            root: root, depth: depth, edges: records,
            title: { id in
                if id == root {
                    meeting.title
                } else {
                    LiquidMeetingsModel.displayTitle(
                        kind: id.kind, id: id.id, context: context)
                }
            },
            isPlaceholder: isPlaceholder)
    }
}
