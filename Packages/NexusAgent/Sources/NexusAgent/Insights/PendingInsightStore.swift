import Foundation

@MainActor
@Observable
public final class PendingInsightStore {
    public struct Entry: Identifiable, Sendable {
        public let id: UUID
        public let kind: String
        public let dedupeKey: String
        public let proposal: Proposal
    }

    public private(set) var pending: [Entry] = []
    public init() {}

    public var count: Int { pending.count }

    public func add(kind: String, dedupeKey: String, proposal: Proposal) {
        guard !pending.contains(where: { $0.dedupeKey == dedupeKey }) else { return }
        pending.append(Entry(id: UUID(), kind: kind, dedupeKey: dedupeKey, proposal: proposal))
    }

    public func resolve(id: UUID) {
        pending.removeAll { $0.id == id }
    }
}
