import Foundation
import SwiftData

/// Polymorphic edge in the Linkable graph. Stores `(fromKind, fromID, toKind, toID)` as raw fields
/// rather than `@Relationship`-typed pointers. This is decision **D7** in the architecture spec —
/// it lets a Note link to a Task to a Meeting without SwiftData inheritance gymnastics.
///
/// Backlinks query: `Link.where { $0.toID == X }`.
@Model
public final class Link {
    public var id: UUID = UUID()
    public var fromKind: ItemKind = ItemKind.note
    public var fromID: UUID = UUID()
    public var toKind: ItemKind = ItemKind.note
    public var toID: UUID = UUID()
    public var linkKind: LinkKind = LinkKind.mentions
    public var createdAt: Date = Date.now
    public var order: Int?

    public init(
        from: (ItemKind, UUID),
        to: (ItemKind, UUID),
        linkKind: LinkKind,
        order: Int? = nil
    ) {
        self.id = UUID()
        self.fromKind = from.0
        self.fromID = from.1
        self.toKind = to.0
        self.toID = to.1
        self.linkKind = linkKind
        self.createdAt = .now
        self.order = order
    }

    /// Stable diagnostic key derived from `(fromKind, fromID, toKind, toID, linkKind)`. Useful for
    /// logging when `LinkRepository.findOrCreate` detects a duplicate. The actual idempotency check
    /// is predicate-side match in `findOrCreate` — CloudKit forbids `@Attribute(.unique)` so we can't
    /// enforce uniqueness via this key at the storage layer.
    public var idempotencyKey: String {
        "\(fromKind.rawValue):\(fromID.uuidString):\(toKind.rawValue):\(toID.uuidString):\(linkKind.rawValue)"
    }

    public var fromEndpoint: (kind: ItemKind, id: UUID) { (fromKind, fromID) }
    public var toEndpoint: (kind: ItemKind, id: UUID) { (toKind, toID) }
}
