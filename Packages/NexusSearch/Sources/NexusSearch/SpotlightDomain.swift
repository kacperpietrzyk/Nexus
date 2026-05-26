import Foundation
import NexusCore

/// Stable identifier helpers for `CSSearchableItem.domainIdentifier` and `uniqueIdentifier`.
///
/// We use a per-`ItemKind` subdomain so we can later call
/// `CSSearchableIndex.deleteSearchableItems(withDomainIdentifiers:)` to wipe just one kind
/// without touching others — useful when, say, a single module's data needs reindexing.
public enum SpotlightDomain {
    public static let root = "com.kacperpietrzyk.Nexus"

    public static func subdomain(for kind: ItemKind) -> String {
        "\(root).\(kind.rawValue)"
    }

    /// Identifier for a single `CSSearchableItem`. Stable for the lifetime of the underlying
    /// Linkable — derives from `(kind, id)` only, not `updatedAt`, so updates replace in place.
    public static func uniqueIdentifier(kind: ItemKind, id: UUID) -> String {
        "\(subdomain(for: kind)):\(id.uuidString)"
    }
}
