import Foundation

public enum ReciprocalRankFusion {
    public struct Hit: Equatable, Sendable {
        public let itemID: UUID
        public let score: Double

        public init(itemID: UUID, score: Double) {
            self.itemID = itemID
            self.score = score
        }
    }

    /// Merges ranked result lists using Reciprocal Rank Fusion.
    ///
    /// `k` controls the smoothing constant. Microsoft's original RRF uses `k = 60`.
    public static func merge(rankings: [[UUID]], k: Double = 60) -> [Hit] {
        var scores = [UUID: Double]()
        for ranking in rankings {
            for (rank, id) in ranking.enumerated() {
                scores[id, default: 0] += 1 / (k + Double(rank + 1))
            }
        }

        return
            scores
            .map { Hit(itemID: $0.key, score: $0.value) }
            .sorted {
                if $0.score == $1.score {
                    return $0.itemID.uuidString < $1.itemID.uuidString
                }
                return $0.score > $1.score
            }
    }
}
