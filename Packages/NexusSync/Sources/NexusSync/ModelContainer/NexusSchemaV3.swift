import Foundation
import NexusCore
import SwiftData

/// V3 schema: adds `TaskItem` as the production Linkable for Phase 1b. `DebugItem`
/// stays vestigial to keep V2 -> V3 lightweight and avoid type-removal migration risk.
public enum NexusSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            Link.self,
            DebugItem.self,
            ConflictLog.self,
            QuotaLog.self,
            TaskItem.self,
        ]
    }

    /// Historical V3 `TaskItem` shape, frozen so future `NexusCore.TaskItem` fields do not
    /// retroactively alter the V3 checksum used by SwiftData migrations.
    @Model
    public final class TaskItem {
        public var id: UUID = UUID()
        public var kind: ItemKind = ItemKind.task
        public var title: String = ""
        public var body: String = ""
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now
        public var deletedAt: Date?

        public var dueAt: Date?
        public var startAt: Date?
        public var snoozedUntil: Date?
        public var statusRaw: String = TaskStatus.open.rawValue
        public var priorityRaw: Int = TaskPriority.none.rawValue
        public var tags: [String] = []
        public var recurrenceRule: String?
        public var recurrenceParentId: UUID?
        public var lastCompletedAt: Date?
        public var orderIndex: Double?
        public var pinnedAsFocus: Bool = false

        public init(
            id: UUID = UUID(),
            title: String,
            body: String = "",
            dueAt: Date? = nil,
            startAt: Date? = nil,
            priority: TaskPriority = .none,
            status: TaskStatus = .open,
            tags: [String] = [],
            recurrenceRule: String? = nil,
            recurrenceParentId: UUID? = nil,
            orderIndex: Double? = nil,
            pinnedAsFocus: Bool = false
        ) {
            self.id = id
            self.kind = .task
            self.title = title
            self.body = body
            let now = Date.now
            self.createdAt = now
            self.updatedAt = now
            self.deletedAt = nil
            self.dueAt = dueAt
            self.startAt = startAt
            self.snoozedUntil = nil
            self.statusRaw = status.rawValue
            self.priorityRaw = priority.rawValue
            self.tags = tags
            self.recurrenceRule = recurrenceRule
            self.recurrenceParentId = recurrenceParentId
            self.lastCompletedAt = nil
            self.orderIndex = orderIndex
            self.pinnedAsFocus = pinnedAsFocus
        }
    }
}
