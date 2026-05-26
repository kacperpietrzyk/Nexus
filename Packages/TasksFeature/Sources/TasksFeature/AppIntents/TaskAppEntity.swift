#if canImport(AppIntents)
import AppIntents
import Foundation
import NexusCore

/// AppEntity facade for `TaskItem` exposed to Siri/Shortcuts. The id is the
/// UUID stringified — Siri persists this id and re-resolves the entity via
/// `EntityStringQuery.entities(for:)` on later runs.
public struct TaskAppEntity: AppEntity, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let tags: [String]

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Task", numericFormat: "\(placeholder: .int) tasks")
    }

    public static let defaultQuery = TaskEntityQuery()

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: tags.isEmpty ? nil : "\(tags.map { "#\($0)" }.joined(separator: " "))",
            image: .init(systemName: "checklist")
        )
    }

    public init(id: String, title: String, tags: [String]) {
        self.id = id
        self.title = title
        self.tags = tags
    }

    public init(task: TaskItem) {
        self.id = task.id.uuidString
        self.title = task.title
        self.tags = task.tags
    }
}
#endif
