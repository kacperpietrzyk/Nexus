import Foundation
import NexusCore

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
    private let repository: AgentInsightRepository?

    public init(repository: AgentInsightRepository? = nil) {
        self.repository = repository
        if let repository { hydrate(from: repository) }
    }

    public var count: Int { pending.count }

    public func add(kind: String, dedupeKey: String, proposal: Proposal) {
        guard !pending.contains(where: { $0.dedupeKey == dedupeKey }) else { return }
        if let repository, let json = Self.encode(proposal) {
            // The persisted record id becomes the entry id (so resolve lines up).
            if let record = try? repository.add(
                kind: kind, dedupeKey: dedupeKey,
                title: proposal.previews.first?.summary ?? proposal.rationale,
                proposalJSON: json
            ) {
                pending.append(Entry(id: record.id, kind: kind, dedupeKey: dedupeKey, proposal: proposal))
                return
            }
        }
        pending.append(Entry(id: UUID(), kind: kind, dedupeKey: dedupeKey, proposal: proposal))
    }

    public func resolve(id: UUID) {
        pending.removeAll { $0.id == id }
        try? repository?.resolve(id: id)
    }

    private func hydrate(from repository: AgentInsightRepository) {
        let records = (try? repository.open()) ?? []
        pending = records.compactMap { record in
            guard let proposal = Self.decode(record.proposalJSON) else { return nil }
            return Entry(id: record.id, kind: record.kind, dedupeKey: record.dedupeKey, proposal: proposal)
        }
    }

    private static func encode(_ proposal: Proposal) -> String? {
        guard let data = try? JSONEncoder().encode(proposal) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decode(_ json: String) -> Proposal? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Proposal.self, from: data)
    }
}
