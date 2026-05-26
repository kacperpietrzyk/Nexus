import Foundation
import Testing

@testable import NexusAgent

struct ReciprocalRankFusionTests {
    @Test
    func rrfMergesTwoRankings() {
        let ids = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        ]
        let first = ids
        let second = [ids[2], ids[0], ids[1]]

        let merged = ReciprocalRankFusion.merge(rankings: [first, second], k: 60)

        #expect(merged.map(\.itemID) == [ids[0], ids[2], ids[1]])
    }

    @Test
    func rrfUsesUUIDStringTieBreaker() {
        let later = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let earlier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let merged = ReciprocalRankFusion.merge(rankings: [[later], [earlier]], k: 60)

        #expect(merged.map(\.itemID) == [earlier, later])
    }

    @Test
    func rrfHandlesEmptyRankings() {
        let merged = ReciprocalRankFusion.merge(rankings: [[], []])

        #expect(merged.isEmpty)
    }
}
