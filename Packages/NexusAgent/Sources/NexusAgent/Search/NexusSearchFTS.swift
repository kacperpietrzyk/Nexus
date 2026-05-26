import Foundation
import NexusCore

public final class NexusSearchFTS: FTSSearch {
    private let index: SearchIndex

    public init(index: SearchIndex) {
        self.index = index
    }

    public func search(query: String, limit: Int) async throws -> [UUID] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }

        let hits = await index.search(trimmed, kinds: nil, limit: limit)
        return hits.map(\.itemID)
    }
}
