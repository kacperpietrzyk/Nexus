import Foundation
import SwiftData

/// A durable agent insight/proposal awaiting the user's confirmation. The full
/// `Proposal` is stored as encoded JSON (`proposalJSON`) so the confirm flow
/// works after a relaunch. Synced (CloudKit private DB). `dedupeKey` prevents
/// re-surfacing the same suggestion; not `@Attribute(.unique)` (CloudKit) — the
/// repository dedupes in code.
@Model
public final class AgentInsightRecord {
    public var id: UUID = UUID()
    public var kind: String = ""
    public var dedupeKey: String = ""
    public var title: String = ""
    public var proposalJSON: String = ""
    public var createdAt: Date = Date.now
    public var resolvedAt: Date?

    public init(
        id: UUID = UUID(), kind: String, dedupeKey: String,
        title: String, proposalJSON: String,
        createdAt: Date = .now, resolvedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.dedupeKey = dedupeKey
        self.title = title
        self.proposalJSON = proposalJSON
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }
}
