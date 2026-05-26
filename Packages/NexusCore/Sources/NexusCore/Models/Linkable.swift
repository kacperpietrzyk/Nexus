import Foundation
import SwiftData

/// Minimal contract every domain entity must satisfy to participate in the polymorphic Link graph
/// and the soft-delete lifecycle. `kind` is stored (NOT computed) so that it can be indexed by FTS
/// and queried via predicates without fetching the concrete subtype.
public protocol Linkable: PersistentModel {
    var id: UUID { get }
    var kind: ItemKind { get }
    var title: String { get set }
    var createdAt: Date { get }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
}
