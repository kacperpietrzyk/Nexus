import Foundation
import NexusCore
import SwiftData

/// V5 schema: adds `TaskItem.endAt`. Lightweight additive migration from V4.
public enum NexusSchemaV5: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            Link.self,
            DebugItem.self,
            ConflictLog.self,
            QuotaLog.self,
            TaskItem.self,
        ]
    }

    /// Historical V5 `TaskItem` shape, frozen so V6-only fields and models do not
    /// retroactively alter the V5 checksum used by SwiftData migrations.
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
        public var endAt: Date?
        public var snoozedUntil: Date?
        public var statusRaw: String = TaskStatus.open.rawValue
        public var priorityRaw: Int = TaskPriority.none.rawValue
        public var tags: [String] = []
        public var recurrenceRule: String?
        public var recurrenceParentId: UUID?
        public var lastCompletedAt: Date?
        public var orderIndex: Double?
        public var pinnedAsFocus: Bool = false
        public var externalSourceID: String?
        public var externalSourceMetadata: Data?

        public init(
            id: UUID = UUID(),
            title: String,
            body: String = "",
            dueAt: Date? = nil,
            startAt: Date? = nil,
            endAt: Date? = nil,
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
            self.endAt = endAt
            self.snoozedUntil = nil
            self.statusRaw = status.rawValue
            self.priorityRaw = priority.rawValue
            self.tags = tags
            self.recurrenceRule = recurrenceRule
            self.recurrenceParentId = recurrenceParentId
            self.lastCompletedAt = nil
            self.orderIndex = orderIndex
            self.pinnedAsFocus = pinnedAsFocus
            self.externalSourceID = nil
            self.externalSourceMetadata = nil
        }
    }
}
