import Foundation
import SwiftData

/// Test/preview fixture only — `TaskItem` is the production Linkable from
/// `NexusSchemaV3` onward. DebugItem remains in V3 schema as vestigial because
/// lightweight migration with type removal is not guaranteed, and it remains useful
/// for generic Linkable tests that do not need TaskItem-specific fields.
/// App code should never insert DebugItem in production.
@Model
public final class DebugItem: Searchable {
    public var id: UUID = UUID()
    public var kind: ItemKind = ItemKind.debug
    public var title: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?

    public init(title: String) {
        self.id = UUID()
        self.kind = .debug
        self.title = title
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
    }
}
